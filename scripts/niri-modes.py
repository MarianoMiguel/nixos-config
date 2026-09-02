#!/usr/bin/env python3
"""Per-workspace window modes for niri: tile, float, and focus.

tile   niri's native scrollable tiling. The passive default: the daemon
       does nothing to a tile workspace beyond an explicit `set tile`,
       which un-floats windows and dissolves a focus-mode column.
float  every window on the workspace floats, like a classic desktop.
       New windows are floated as they open.
focus  every window joins a single centered tabbed column, so exactly
       one app is visible at a time with zero neighbor peek. Cycling
       moves one app per step.

All enforcement uses per-window and per-workspace niri IPC actions, so a
mode applies to exactly one workspace: the other monitor keeps its own
modes untouched.

float and focus modes are locked in: when the layout drifts from the mode
(a window un-floats, or leaves the focus column), the daemon re-asserts it,
so a workspace always matches its bar label. Moving a window to another
workspace is the intended way out; switching the mode restructures in place.

The daemon owns the state and exposes a JSON-lines protocol on
$XDG_RUNTIME_DIR/niri-modes.sock; `niri-modes set|get|cycle-mode|cycle|watch`
are thin clients used by the DMS bar widget and the niri keybinds.
"""

import argparse
import json
import os
import re
import socket
import subprocess
import sys
import threading
import time

PROTOCOL_VERSION = 1
MODES = ("tile", "float", "focus")

FOCUS_WIDTH = os.environ.get("NIRI_MODES_FOCUS_WIDTH", "80%")

# Shell surfaces and picture-in-picture windows float by window rule and are
# managed by their own daemons; the modes must never drag them into a layout.
EXEMPT_RE = re.compile(
    os.environ.get(
        "NIRI_MODES_EXEMPT_RE",
        r"(?i)quickshell|danklinux\.dms|xdg-desktop-portal"
        r"|mariano\.voiceagent|picture.?in.?picture",
    )
)


def socket_path():
    runtime_dir = os.environ.get("XDG_RUNTIME_DIR")
    if not runtime_dir:
        sys.exit("XDG_RUNTIME_DIR is not set")
    return os.path.join(runtime_dir, "niri-modes.sock")


def niri_json(command):
    result = subprocess.run(
        ["niri", "msg", "--json", command],
        capture_output=True, text=True, timeout=10,
    )
    if result.returncode != 0:
        raise RuntimeError(f"niri msg {command}: {result.stderr.strip()}")
    return json.loads(result.stdout)


def action(*args):
    """Run one niri action; report success instead of raising.

    Failures are expected for actions the running niri may not support yet
    (callers fall back) and for no-ops like consuming past the last column.
    """
    result = subprocess.run(
        ["niri", "msg", "action", *[str(a) for a in args]],
        capture_output=True, text=True, timeout=10,
    )
    return result.returncode == 0


def is_exempt(window):
    subject = f"{window.get('app_id') or ''} {window.get('title') or ''}"
    return bool(EXEMPT_RE.search(subject))


class Daemon:
    def __init__(self):
        self.lock = threading.RLock()
        self.modes = {}            # workspace id -> mode (absent == tile)
        self.workspaces = {}       # workspace id -> workspace object
        self.windows = {}          # window id -> window object
        self.dirty = set()         # focus-mode workspaces awaiting enforcement
        self.toggled_tabbed = set()  # workspaces we made tabbed via the toggle fallback
        self.drift_timers = {}     # workspace id -> debounce Timer for re-enforcement
        self.watchers = []         # write files of `watch` clients

    # ----- state ---------------------------------------------------------

    def resync(self):
        workspaces = niri_json("workspaces")
        windows = niri_json("windows")
        with self.lock:
            self.workspaces = {w["id"]: w for w in workspaces}
            self.windows = {w["id"]: w for w in windows}
            for gone in set(self.modes) - set(self.workspaces):
                self.forget_workspace(gone)

    def forget_workspace(self, workspace_id):
        self.modes.pop(workspace_id, None)
        self.dirty.discard(workspace_id)
        self.toggled_tabbed.discard(workspace_id)
        timer = self.drift_timers.pop(workspace_id, None)
        if timer is not None:
            timer.cancel()

    def mode_of(self, workspace_id):
        return self.modes.get(workspace_id, "tile")

    def state(self):
        with self.lock:
            outputs = {}
            focused = None
            for workspace in self.workspaces.values():
                if workspace.get("is_focused"):
                    focused = workspace["id"]
                if workspace.get("is_active") and workspace.get("output"):
                    outputs[workspace["output"]] = {
                        "workspace_id": workspace["id"],
                        "idx": workspace.get("idx"),
                        "name": workspace.get("name"),
                        "mode": self.mode_of(workspace["id"]),
                    }
            return {
                "version": PROTOCOL_VERSION,
                "type": "state",
                "outputs": outputs,
                "modes": {str(k): v for k, v in self.modes.items()},
                "focused_workspace_id": focused,
            }

    def broadcast(self):
        line = json.dumps(self.state()) + "\n"
        with self.lock:
            alive = []
            for watcher in self.watchers:
                try:
                    watcher.write(line)
                    watcher.flush()
                    alive.append(watcher)
                except OSError:
                    pass
            self.watchers = alive

    # ----- workspace resolution -------------------------------------------

    def resolve_workspace(self, output=None, workspace_id=None):
        with self.lock:
            if workspace_id is not None:
                return self.workspaces.get(workspace_id)
            for workspace in self.workspaces.values():
                if output:
                    if workspace.get("output") == output and workspace.get("is_active"):
                        return workspace
                elif workspace.get("is_focused"):
                    return workspace
        return None

    def workspace_windows(self, workspace_id):
        return [
            w for w in self.windows.values()
            if w.get("workspace_id") == workspace_id and not is_exempt(w)
        ]

    # ----- enforcement -----------------------------------------------------

    def set_mode(self, workspace, mode):
        workspace_id = workspace["id"]
        with self.lock:
            previous = self.mode_of(workspace_id)
            if mode == "tile":
                self.modes.pop(workspace_id, None)
            else:
                self.modes[workspace_id] = mode
            self.dirty.discard(workspace_id)

            if mode == "float":
                self.enforce_float(workspace_id)
            elif mode == "focus":
                if workspace.get("is_focused"):
                    self.enforce_focus(workspace_id)
                else:
                    self.dirty.add(workspace_id)
            elif mode == "tile" and previous != "tile":
                if workspace.get("is_focused"):
                    self.enforce_tile(workspace_id, previous)
                else:
                    self.dirty.add(workspace_id)
        self.broadcast()

    def enforce_float(self, workspace_id):
        """Idempotent and focus-preserving: only --id actions."""
        for window in self.workspace_windows(workspace_id):
            if not window.get("is_floating"):
                action("move-window-to-floating", "--id", window["id"])

    def enforce_tile(self, workspace_id, previous="tile"):
        """Un-float everything; after focus mode, split the column back up."""
        for window in self.workspace_windows(workspace_id):
            if window.get("is_floating"):
                action("move-window-to-tiling", "--id", window["id"])
        if previous != "focus":
            return
        self.resync()
        windows = self.workspace_windows(workspace_id)
        if not action("set-column-display", "normal") and workspace_id in self.toggled_tabbed:
            if windows:
                action("focus-window", "--id", windows[0]["id"])
            action("toggle-column-tabbed-display")
        self.toggled_tabbed.discard(workspace_id)
        for window in windows[1:]:
            action("focus-window", "--id", window["id"])
            action("expel-window-from-column")

    def enforce_focus(self, workspace_id):
        """Consolidate the workspace into one centered tabbed column.

        Runs only while the workspace is focused, because consume and
        column-display actions operate on the focused column.
        """
        for window in self.workspace_windows(workspace_id):
            if window.get("is_floating"):
                action("move-window-to-tiling", "--id", window["id"])
        self.resync()

        windows = self.workspace_windows(workspace_id)
        if not windows:
            return
        focused_before = next((w["id"] for w in windows if w.get("is_focused")), None)

        def column_of(window):
            position = (window.get("layout") or {}).get("pos_in_scrolling_layout")
            return position[0] if isinstance(position, list) and position else None

        columns = {column_of(w) for w in windows}
        if None in columns:
            merges = len(windows) - 1
            base = windows[0]
        else:
            merges = len(columns) - 1
            base = min(windows, key=lambda w: (column_of(w), w["id"]))

        action("focus-window", "--id", base["id"])
        for _ in range(merges):
            if not action("consume-window-into-column"):
                break

        if not action("set-column-display", "tabbed"):
            # Older niri only has the toggle; apply it once per consolidation.
            if workspace_id not in self.toggled_tabbed:
                action("toggle-column-tabbed-display")
                self.toggled_tabbed.add(workspace_id)
        action("set-column-width", FOCUS_WIDTH)
        action("reset-window-height", "--id", base["id"])
        action("center-window", "--id", base["id"])
        if focused_before is not None and focused_before != base["id"]:
            action("focus-window", "--id", focused_before)

    def focus_drift(self, workspace_id):
        """Cheap check on cached state: has the focus column broken up?

        Windows with no scrolling-layout position (e.g. mid interactive
        move) are ignored rather than counted as drift; they resolve to a
        real position or a workspace change, and both re-check.
        """
        windows = self.workspace_windows(workspace_id)
        if any(w.get("is_floating") for w in windows):
            return True
        columns = set()
        for window in windows:
            position = (window.get("layout") or {}).get("pos_in_scrolling_layout")
            if isinstance(position, list) and position:
                columns.add(position[0])
        return len(columns) > 1

    def schedule_enforce(self, workspace_id):
        """Debounce drift enforcement so event bursts (and drags in
        progress) coalesce into one re-check against fresh state."""
        with self.lock:
            timer = self.drift_timers.pop(workspace_id, None)
            if timer is not None:
                timer.cancel()
            timer = threading.Timer(0.3, self.enforce_after_drift, (workspace_id,))
            timer.daemon = True
            self.drift_timers[workspace_id] = timer
            timer.start()

    def enforce_after_drift(self, workspace_id):
        with self.lock:
            self.drift_timers.pop(workspace_id, None)
        if self.mode_of(workspace_id) != "focus":
            return
        self.resync()
        with self.lock:
            if not self.focus_drift(workspace_id):
                return
            if (self.workspaces.get(workspace_id) or {}).get("is_focused"):
                self.enforce_focus(workspace_id)
            else:
                self.dirty.add(workspace_id)

    def cycle_windows(self, direction):
        workspace = self.resolve_workspace()
        if workspace is None:
            return False
        mode = self.mode_of(workspace["id"])
        if mode == "focus":
            return action("focus-window-down" if direction == "next" else "focus-window-up")
        return action("focus-column-right" if direction == "next" else "focus-column-left")

    # ----- events ----------------------------------------------------------

    def handle_event(self, event):
        if "WorkspacesChanged" in event:
            with self.lock:
                incoming = event["WorkspacesChanged"].get("workspaces", [])
                self.workspaces = {w["id"]: w for w in incoming}
                for gone in set(self.modes) - set(self.workspaces):
                    self.forget_workspace(gone)
            self.broadcast()
        elif "WindowsChanged" in event:
            with self.lock:
                incoming = event["WindowsChanged"].get("windows", [])
                self.windows = {w["id"]: w for w in incoming}
        elif "WindowOpenedOrChanged" in event:
            window = event["WindowOpenedOrChanged"].get("window") or {}
            if "id" not in window:
                return
            with self.lock:
                previous = self.windows.get(window["id"])
                self.windows[window["id"]] = window
                arrived = previous is None or \
                    previous.get("workspace_id") != window.get("workspace_id")
                workspace_id = window.get("workspace_id")
                mode = self.mode_of(workspace_id) if workspace_id else "tile"
                if is_exempt(window):
                    return
                if mode == "float":
                    # Applies to arrivals and to a window the user un-floated
                    # in place: the mode is locked, so it floats right back.
                    if not window.get("is_floating"):
                        action("move-window-to-floating", "--id", window["id"])
                elif mode == "focus":
                    if arrived:
                        workspace = self.workspaces.get(workspace_id) or {}
                        if workspace.get("is_focused"):
                            self.enforce_focus(workspace_id)
                        else:
                            self.dirty.add(workspace_id)
                    elif self.focus_drift(workspace_id):
                        self.schedule_enforce(workspace_id)
        elif "WindowClosed" in event:
            with self.lock:
                self.windows.pop(event["WindowClosed"].get("id"), None)
        elif "WorkspaceActivated" in event:
            payload = event["WorkspaceActivated"]
            workspace_id = payload.get("id")
            with self.lock:
                for workspace in self.workspaces.values():
                    same_output = workspace.get("output") == \
                        (self.workspaces.get(workspace_id) or {}).get("output")
                    if same_output:
                        workspace["is_active"] = workspace["id"] == workspace_id
                    if payload.get("focused"):
                        workspace["is_focused"] = workspace["id"] == workspace_id
                if payload.get("focused") and workspace_id in self.dirty:
                    self.dirty.discard(workspace_id)
                    mode = self.mode_of(workspace_id)
                    if mode == "focus":
                        self.enforce_focus(workspace_id)
                    elif mode == "tile":
                        self.enforce_tile(workspace_id, "focus")
            self.broadcast()
        elif "WindowLayoutsChanged" in event:
            # set-column-width is asynchronous: the column resizes only when
            # the app acks the configure, after enforce_focus has already
            # centered it, so the column grows rightward off-center. Re-center
            # when a focus column's size actually lands; centering changes
            # position, not size, so this does not re-trigger itself.
            #
            # Height is locked to automatic (full) as well: niri top-aligns a
            # column shorter than the workspace and has no action to move it
            # down, so full height is the only vertically centered height.
            # Resetting an already-automatic height emits no event, so the
            # reset->change->reset chain converges after one round.
            recenter = []
            drifted = set()
            with self.lock:
                for change in event["WindowLayoutsChanged"].get("changes", []):
                    if not (isinstance(change, list) and len(change) == 2):
                        continue
                    window = self.windows.get(change[0])
                    if window is None:
                        continue
                    layout_before = window.get("layout") or {}
                    window["layout"] = change[1]
                    workspace_id = window.get("workspace_id")
                    if is_exempt(window) or self.mode_of(workspace_id) != "focus":
                        continue
                    before = layout_before.get("tile_size") or []
                    after = change[1].get("tile_size") or []
                    if before != after:
                        recenter.append((window["id"], before[1:2] != after[1:2]))
                    # A position change can mean the window left the focus
                    # column (expel, drag-out): re-consolidate after settling.
                    if layout_before.get("pos_in_scrolling_layout") != \
                            change[1].get("pos_in_scrolling_layout") and \
                            self.focus_drift(workspace_id):
                        drifted.add(workspace_id)
            for window_id, height_changed in recenter:
                if height_changed:
                    action("reset-window-height", "--id", window_id)
                action("center-window", "--id", window_id)
            for workspace_id in drifted:
                self.schedule_enforce(workspace_id)

    def event_loop(self):
        while True:
            try:
                self.resync()
                self.broadcast()
                stream = subprocess.Popen(
                    ["niri", "msg", "--json", "event-stream"],
                    stdout=subprocess.PIPE, text=True,
                )
                for line in stream.stdout:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        event = json.loads(line)
                    except json.JSONDecodeError:
                        continue
                    try:
                        self.handle_event(event)
                    except Exception as error:  # keep the stream alive
                        print(f"event error: {error}", file=sys.stderr)
                stream.wait()
            except Exception as error:
                print(f"event stream lost: {error}", file=sys.stderr)
            time.sleep(2)

    # ----- request handling --------------------------------------------------

    def handle_request(self, request, write_file):
        op = request.get("op")
        if op == "get":
            return self.state()
        if op == "watch":
            with self.lock:
                self.watchers.append(write_file)
            return self.state()
        if op in ("set", "cycle-mode"):
            workspace = self.resolve_workspace(
                output=request.get("output") or None,
                workspace_id=request.get("workspace_id"),
            )
            if workspace is None:
                return {"ok": False, "error": "no matching workspace"}
            if op == "set":
                mode = request.get("mode")
                if mode not in MODES:
                    return {"ok": False, "error": f"unknown mode {mode!r}"}
            else:
                current = self.mode_of(workspace["id"])
                mode = MODES[(MODES.index(current) + 1) % len(MODES)]
            self.set_mode(workspace, mode)
            return {"ok": True, **self.state()}
        if op == "cycle":
            ok = self.cycle_windows(
                "next" if request.get("dir") != "prev" else "prev")
            return {"ok": ok}
        if op == "recenter":
            with self.lock:
                window = next(
                    (w for w in self.windows.values() if w.get("is_focused")),
                    None,
                )
            if window is None:
                return {"ok": False, "error": "no focused window"}
            if not window.get("is_floating"):
                # Tiled columns cannot be positioned vertically (niri
                # top-aligns short columns), so full height is the only
                # vertically centered height; center-window then handles
                # the horizontal axis. For floating windows center-window
                # alone centers both axes.
                action("reset-window-height", "--id", window["id"])
            ok = action("center-window", "--id", window["id"])
            return {"ok": ok}
        return {"ok": False, "error": f"unknown op {op!r}"}

    def serve(self):
        path = socket_path()
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass
        server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        server.bind(path)
        os.chmod(path, 0o600)
        server.listen(8)

        threading.Thread(target=self.event_loop, daemon=True).start()

        while True:
            connection, _ = server.accept()
            threading.Thread(
                target=self.client_loop, args=(connection,), daemon=True,
            ).start()

    def client_loop(self, connection):
        read_file = connection.makefile("r")
        write_file = connection.makefile("w")
        try:
            for line in read_file:
                line = line.strip()
                if not line:
                    continue
                try:
                    request = json.loads(line)
                except json.JSONDecodeError:
                    request = {}
                response = self.handle_request(request, write_file)
                write_file.write(json.dumps(response) + "\n")
                write_file.flush()
        except OSError:
            pass
        finally:
            with self.lock:
                if write_file in self.watchers:
                    self.watchers.remove(write_file)


# ----- client side --------------------------------------------------------


def request(payload, stream=False):
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        client.connect(socket_path())
    except OSError as error:
        sys.exit(f"niri-modes daemon is not reachable: {error}")
    client.sendall((json.dumps(payload) + "\n").encode())
    read_file = client.makefile("r")
    first = read_file.readline()
    if not first:
        sys.exit("niri-modes daemon closed the connection")
    print(first, end="", flush=True)
    if stream:
        for line in read_file:
            print(line, end="", flush=True)
        return None
    return json.loads(first)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    commands = parser.add_subparsers(dest="command", required=True)

    commands.add_parser("daemon")
    commands.add_parser("get")
    commands.add_parser("watch")
    commands.add_parser("recenter")

    set_parser = commands.add_parser("set")
    set_parser.add_argument("mode", choices=MODES)
    set_parser.add_argument("--output")

    cycle_mode_parser = commands.add_parser("cycle-mode")
    cycle_mode_parser.add_argument("--output")

    cycle_parser = commands.add_parser("cycle")
    cycle_parser.add_argument("dir", choices=("next", "prev"))

    arguments = parser.parse_args()

    if arguments.command == "daemon":
        Daemon().serve()
    elif arguments.command == "get":
        request({"op": "get"})
    elif arguments.command == "watch":
        request({"op": "watch"}, stream=True)
    elif arguments.command == "set":
        response = request({
            "op": "set", "mode": arguments.mode, "output": arguments.output,
        })
        if not response.get("ok"):
            sys.exit(response.get("error", "failed"))
    elif arguments.command == "cycle-mode":
        response = request({"op": "cycle-mode", "output": arguments.output})
        if not response.get("ok"):
            sys.exit(response.get("error", "failed"))
    elif arguments.command == "cycle":
        request({"op": "cycle", "dir": arguments.dir})
    elif arguments.command == "recenter":
        request({"op": "recenter"})


if __name__ == "__main__":
    main()
