import Gio from "gi://Gio";
import Meta from "gi://Meta";

import { Extension } from "resource:///org/gnome/shell/extensions/extension.js";
import * as Main from "resource:///org/gnome/shell/ui/main.js";

const DBUS_PATH = "/org/gnome/Shell/Extensions/VicinaeWindowManagement";
const DBUS_INTERFACE = "org.gnome.Shell.Extensions.VicinaeWindowManagement";
const GAP = 8;

const DBUS_XML = `
<node>
  <interface name="${DBUS_INTERFACE}">
    <method name="Execute">
      <arg type="s" direction="in" name="action" />
      <arg type="s" direction="out" name="result" />
    </method>
    <method name="GetState">
      <arg type="s" direction="out" name="state" />
    </method>
  </interface>
</node>`;

const FRACTIONAL_LAYOUTS = {
  "left-half": [0, 0, 1 / 2, 1],
  "center-half": [1 / 4, 0, 1 / 2, 1],
  "right-half": [1 / 2, 0, 1 / 2, 1],
  "top-half": [0, 0, 1, 1 / 2],
  "bottom-half": [0, 1 / 2, 1, 1 / 2],

  "first-third": [0, 0, 1 / 3, 1],
  "first-two-thirds": [0, 0, 2 / 3, 1],
  "center-third": [1 / 3, 0, 1 / 3, 1],
  "last-two-thirds": [1 / 3, 0, 2 / 3, 1],
  "last-third": [2 / 3, 0, 1 / 3, 1],

  "top-third": [0, 0, 1, 1 / 3],
  "top-two-thirds": [0, 0, 1, 2 / 3],
  "middle-third": [0, 1 / 3, 1, 1 / 3],
  "bottom-two-thirds": [0, 1 / 3, 1, 2 / 3],
  "bottom-third": [0, 2 / 3, 1, 1 / 3],

  "first-fourth": [0, 0, 1 / 4, 1],
  "second-fourth": [1 / 4, 0, 1 / 4, 1],
  "third-fourth": [1 / 2, 0, 1 / 4, 1],
  "last-fourth": [3 / 4, 0, 1 / 4, 1],

  "top-left-quarter": [0, 0, 1 / 2, 1 / 2],
  "top-right-quarter": [1 / 2, 0, 1 / 2, 1 / 2],
  "bottom-left-quarter": [0, 1 / 2, 1 / 2, 1 / 2],
  "bottom-right-quarter": [1 / 2, 1 / 2, 1 / 2, 1 / 2],

  "top-left-sixth": [0, 0, 1 / 3, 1 / 2],
  "top-center-sixth": [1 / 3, 0, 1 / 3, 1 / 2],
  "top-right-sixth": [2 / 3, 0, 1 / 3, 1 / 2],
  "bottom-left-sixth": [0, 1 / 2, 1 / 3, 1 / 2],
  "bottom-center-sixth": [1 / 3, 1 / 2, 1 / 3, 1 / 2],
  "bottom-right-sixth": [2 / 3, 1 / 2, 1 / 3, 1 / 2],
  "top-center-two-thirds": [1 / 6, 0, 2 / 3, 2 / 3],
};

class WindowManagementService {
  constructor(extension) {
    this._extension = extension;
  }

  Execute(action) {
    return JSON.stringify(this._extension.execute(action));
  }

  GetState() {
    return JSON.stringify(this._extension.getState());
  }
}

export default class VicinaeWindowManagementExtension extends Extension {
  enable() {
    this._restoreStates = new Map();
    this._hiddenWindows = new Set();
    this._lastApplicationWindow = null;

    this._rememberFocusedWindow();
    this._focusChangedId = global.display.connect(
      "notify::focus-window",
      () => this._rememberFocusedWindow(),
    );

    this._dbusObject = Gio.DBusExportedObject.wrapJSObject(
      DBUS_XML,
      new WindowManagementService(this),
    );
    this._dbusObject.export(Gio.DBus.session, DBUS_PATH);
  }

  disable() {
    if (this._focusChangedId) {
      global.display.disconnect(this._focusChangedId);
      this._focusChangedId = 0;
    }

    this._dbusObject?.unexport();
    this._dbusObject = null;
    this._lastApplicationWindow = null;
    this._restoreStates?.clear();
    this._hiddenWindows?.clear();
  }

  execute(action) {
    if (action === "show-all")
      return this._showAll();

    const window = this._targetWindow();
    if (!window)
      throw new Error("No application window is available to manage");

    if (action === "hide-others")
      return this._hideOthers(window);

    if (action === "restore")
      return this._restore(window);

    const before = this._snapshot(window);
    this._restoreStates.set(window.get_id(), before);

    if (action in FRACTIONAL_LAYOUTS) {
      const workArea = this._workArea(window.get_monitor());
      this._moveResize(window, this._fractionalRect(workArea, FRACTIONAL_LAYOUTS[action]));
    } else {
      this._executeSpecialAction(window, action);
    }

    return {
      action,
      before,
      after: this._snapshot(window),
    };
  }

  getState() {
    const window = this._targetWindow();
    if (!window)
      return { window: null };

    return {
      window: this._snapshot(window),
      workArea: this._workArea(window.get_monitor()),
      restorable: this._restoreStates.has(window.get_id()),
      hiddenWindowCount: this._hiddenWindows.size,
    };
  }

  _executeSpecialAction(window, action) {
    const workArea = this._workArea(window.get_monitor());
    const frame = window.get_frame_rect();

    switch (action) {
      case "maximize":
        window.maximize(Meta.MaximizeFlags.BOTH);
        return;
      case "maximize-height":
        this._moveResize(window, {
          x: frame.x,
          y: workArea.y + GAP,
          width: frame.width,
          height: workArea.height - GAP * 2,
        });
        return;
      case "maximize-width":
        this._moveResize(window, {
          x: workArea.x + GAP,
          y: frame.y,
          width: workArea.width - GAP * 2,
          height: frame.height,
        });
        return;
      case "almost-maximize":
        this._moveResize(window, this._centeredRect(workArea, workArea.width * 0.9, workArea.height * 0.9));
        return;
      case "reasonable-size":
        this._moveResize(
          window,
          this._centeredRect(
            workArea,
            Math.min(1025, workArea.width * 0.6),
            Math.min(900, workArea.height * 0.6),
          ),
        );
        return;
      case "center":
        this._moveResize(window, this._centeredRect(workArea, frame.width, frame.height));
        return;
      case "move-left":
        this._moveResize(window, { ...frame, x: workArea.x + GAP });
        return;
      case "move-right":
        this._moveResize(window, {
          ...frame,
          x: workArea.x + workArea.width - Math.min(frame.width, workArea.width - GAP * 2) - GAP,
        });
        return;
      case "move-up":
        this._moveResize(window, { ...frame, y: workArea.y + GAP });
        return;
      case "move-down":
        this._moveResize(window, {
          ...frame,
          y: workArea.y + workArea.height - Math.min(frame.height, workArea.height - GAP * 2) - GAP,
        });
        return;
      case "previous-display":
        this._moveToDisplay(window, -1);
        return;
      case "next-display":
        this._moveToDisplay(window, 1);
        return;
      case "previous-workspace":
        this._moveToWorkspace(window, -1);
        return;
      case "next-workspace":
        this._moveToWorkspace(window, 1);
        return;
      case "toggle-fullscreen":
        if (window.is_fullscreen())
          window.unmake_fullscreen();
        else
          window.make_fullscreen();
        return;
      default:
        throw new Error(`Unknown window action: ${action}`);
    }
  }

  _targetWindow() {
    const focused = global.display.focus_window;
    if (this._isApplicationWindow(focused) && !this._isVicinae(focused))
      return focused;

    if (this._windowStillExists(this._lastApplicationWindow))
      return this._lastApplicationWindow;

    return null;
  }

  _rememberFocusedWindow() {
    const focused = global.display.focus_window;
    if (this._isApplicationWindow(focused) && !this._isVicinae(focused))
      this._lastApplicationWindow = focused;
  }

  _isVicinae(window) {
    const wmClass = window?.get_wm_class?.() ?? "";
    return wmClass.toLowerCase().includes("vicinae");
  }

  _isApplicationWindow(window) {
    if (!window)
      return false;

    return [
      Meta.WindowType.NORMAL,
      Meta.WindowType.DIALOG,
      Meta.WindowType.MODAL_DIALOG,
      Meta.WindowType.UTILITY,
    ].includes(window.get_window_type());
  }

  _windowStillExists(window) {
    return Boolean(window) && global.get_window_actors().some(actor => actor.meta_window === window);
  }

  _workArea(monitor) {
    const area = Main.layoutManager.getWorkAreaForMonitor(monitor);
    return { x: area.x, y: area.y, width: area.width, height: area.height };
  }

  _fractionalRect(workArea, [x, y, width, height]) {
    const left = Math.round(workArea.x + workArea.width * x) + GAP;
    const top = Math.round(workArea.y + workArea.height * y) + GAP;
    const right = Math.round(workArea.x + workArea.width * (x + width)) - GAP;
    const bottom = Math.round(workArea.y + workArea.height * (y + height)) - GAP;

    return {
      x: left,
      y: top,
      width: Math.max(1, right - left),
      height: Math.max(1, bottom - top),
    };
  }

  _centeredRect(workArea, requestedWidth, requestedHeight) {
    const width = Math.min(Math.round(requestedWidth), workArea.width - GAP * 2);
    const height = Math.min(Math.round(requestedHeight), workArea.height - GAP * 2);
    return {
      x: workArea.x + Math.round((workArea.width - width) / 2),
      y: workArea.y + Math.round((workArea.height - height) / 2),
      width,
      height,
    };
  }

  _moveResize(window, rect) {
    if (window.is_fullscreen?.())
      window.unmake_fullscreen();
    if (window.minimized)
      window.unminimize();
    window.unmaximize(Meta.MaximizeFlags.BOTH);
    window.move_resize_frame(
      true,
      Math.round(rect.x),
      Math.round(rect.y),
      Math.max(1, Math.round(rect.width)),
      Math.max(1, Math.round(rect.height)),
    );
  }

  _moveToDisplay(window, direction) {
    const monitorCount = global.display.get_n_monitors();
    if (monitorCount < 2)
      return;

    const oldMonitor = window.get_monitor();
    const newMonitor = (oldMonitor + direction + monitorCount) % monitorCount;
    const oldArea = this._workArea(oldMonitor);
    const newArea = this._workArea(newMonitor);
    const frame = window.get_frame_rect();
    const relativeX = (frame.x - oldArea.x) / Math.max(1, oldArea.width - frame.width);
    const relativeY = (frame.y - oldArea.y) / Math.max(1, oldArea.height - frame.height);
    const width = Math.min(frame.width, newArea.width - GAP * 2);
    const height = Math.min(frame.height, newArea.height - GAP * 2);

    this._moveResize(window, {
      x: newArea.x + Math.round(Math.max(0, Math.min(1, relativeX)) * (newArea.width - width)),
      y: newArea.y + Math.round(Math.max(0, Math.min(1, relativeY)) * (newArea.height - height)),
      width,
      height,
    });
  }

  _moveToWorkspace(window, direction) {
    const manager = global.workspace_manager;
    const current = window.get_workspace()?.index() ?? manager.get_active_workspace_index();
    const target = current + direction;
    if (target < 0 || target >= manager.get_n_workspaces())
      return;

    window.change_workspace_by_index(target, false);
  }

  _snapshot(window) {
    const frame = window.get_frame_rect();
    const maximized = typeof window.is_maximized === "function"
      ? window.is_maximized()
      : Boolean(window.maximized_horizontally || window.maximized_vertically);
    return {
      id: window.get_id(),
      title: window.get_title() ?? "",
      wmClass: window.get_wm_class() ?? "",
      monitor: window.get_monitor(),
      workspace: window.get_workspace()?.index() ?? -1,
      maximized: Boolean(maximized),
      fullscreen: window.is_fullscreen(),
      rect: { x: frame.x, y: frame.y, width: frame.width, height: frame.height },
    };
  }

  _restore(window) {
    const previous = this._restoreStates.get(window.get_id());
    if (!previous)
      throw new Error("No previous window geometry has been recorded");

    const before = this._snapshot(window);
    if (previous.fullscreen)
      window.make_fullscreen();
    else if (previous.maximized)
      window.maximize(Meta.MaximizeFlags.BOTH);
    else
      this._moveResize(window, previous.rect);

    this._restoreStates.set(window.get_id(), before);
    return { action: "restore", before, after: this._snapshot(window) };
  }

  _hideOthers(target) {
    const targetClass = (target.get_wm_class() ?? "").toLowerCase();
    let hidden = 0;

    for (const actor of global.get_window_actors()) {
      const window = actor.meta_window;
      const windowClass = (window?.get_wm_class?.() ?? "").toLowerCase();
      if (
        !this._isApplicationWindow(window) ||
        this._isVicinae(window) ||
        window === target ||
        (targetClass && windowClass === targetClass) ||
        window.minimized ||
        !window.can_minimize()
      )
        continue;

      window.minimize();
      this._hiddenWindows.add(window);
      hidden += 1;
    }

    return { action: "hide-others", target: this._snapshot(target), hidden };
  }

  _showAll() {
    let shown = 0;
    for (const window of this._hiddenWindows) {
      if (!this._windowStillExists(window))
        continue;
      window.unminimize();
      shown += 1;
    }
    this._hiddenWindows.clear();
    return { action: "show-all", shown };
  }
}
