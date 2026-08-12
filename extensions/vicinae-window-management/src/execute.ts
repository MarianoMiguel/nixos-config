import { execFile } from "node:child_process";
import { promisify } from "node:util";

import { closeMainWindow, showHUD, showToast, Toast } from "@vicinae/api";

const execFileAsync = promisify(execFile);
const GDBUS = "/run/current-system/sw/bin/gdbus";
const DESTINATION = "org.gnome.Shell";
const OBJECT_PATH = "/org/gnome/Shell/Extensions/VicinaeWindowManagement";
const INTERFACE = "org.gnome.Shell.Extensions.VicinaeWindowManagement";

export async function executeAction(action: string, title?: string): Promise<void> {
  try {
    await execFileAsync(
      GDBUS,
      [
        "call",
        "--session",
        "--dest",
        DESTINATION,
        "--object-path",
        OBJECT_PATH,
        "--method",
        `${INTERFACE}.Execute`,
        action,
      ],
      { timeout: 3000 },
    );
    await showHUD(title ?? action.replaceAll("-", " "), { clearRootSearch: true });
  } catch (error) {
    await closeMainWindow();
    await showToast({
      style: Toast.Style.Failure,
      title: "Window action failed",
      message: error instanceof Error ? error.message : String(error),
    });
  }
}
