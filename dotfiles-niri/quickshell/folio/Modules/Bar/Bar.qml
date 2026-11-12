import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common

// The bar: lifted paper across the top of every screen. The mark, the
// workspaces and the focused app on the left; the island's place in the
// middle; privacy, date, tray and the status pill on the right.
Scope {
    id: root

    // Test data (fixture normal | stress | empty); null shows the live system.
    property var fx: null
    readonly property var fixtures: ({
        "normal": {
            "app": "Ghostty", "title": "~/Development/personal/nixos-config", "workspaces": 4, "active": 0,
            "mic": false, "camera": false, "screen": false,
            "battery": true, "percent": 84, "charging": false, "low": false,
            "online": true, "wired": false, "bluetooth": true, "btConnected": true, "muted": false, "tray": ["message", "shield"]
        },
        "stress": {
            "app": "Visual Studio Code — Insiders",
            "title": "folio.js — nixos-config [SSH: bonhart-agent] — Visual Studio Code — Insiders (Workspace) — Restricted Mode — 3 problems",
            "workspaces": 12, "active": 6, "mic": true, "camera": true, "screen": true,
            "battery": true, "percent": 6, "charging": false, "low": true,
            "online": false, "wired": false, "bluetooth": true, "btConnected": false, "muted": true,
            "tray": ["message", "shield", "folder", "globe", "mail", "calendar", "cup"]
        },
        "empty": {
            "app": "Desktop", "title": "", "workspaces": 1, "active": 0,
            "mic": false, "camera": false, "screen": false,
            "battery": false, "percent": 0, "charging": false, "low": false,
            "online": true, "wired": true, "bluetooth": false, "btConnected": false, "muted": false, "tray": []
        }
    })

    IpcHandler {
        target: "bar"
        // normal | stress | empty; anything else (live) returns to real data.
        function fixture(name: string): void { root.fx = root.fixtures[name] ? Object.assign({}, root.fixtures[name]) : null; }
    }

    Variants {
        model: Quickshell.screens
        BarWindow {
            required property var modelData
            screen: modelData
            fx: root.fx
        }
    }
}
