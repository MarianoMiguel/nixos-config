import QtQuick
import Quickshell
import qs.Services

QtObject {
    id: root

    property var pluginService: null
    property string trigger: "sys"

    signal itemsChanged

    readonly property var actions: [
        { name: "Choose Theme", icon: "palette", section: "Appearance", detail: "Preview and apply one of 22 coordinated themes", action: "theme", keywords: "colors style osaka jade quattro" },
        { name: "Choose Wallpaper", icon: "wallpaper", section: "Appearance", detail: "Browse every wallpaper with visual previews", action: "wallpaper", keywords: "background image quattro" },
        { name: "Toggle Window Gaps", icon: "border_outer", section: "Appearance", detail: "Turn Niri window spacing on or off", action: "style-gaps", keywords: "layout spacing" },
        { name: "Toggle Window Borders", icon: "select_all", section: "Appearance", detail: "Turn Niri window borders on or off", action: "style-border", keywords: "layout outline" },

        { name: "Network Settings", icon: "wifi", section: "Connections", detail: "Wi-Fi, wired network and connection settings", action: "network-settings", keywords: "internet ethernet" },
        { name: "Test Network Speed", icon: "speed", section: "Connections", detail: "Run the integrated download and upload test", action: "network-speed", keywords: "internet bandwidth" },
        { name: "Toggle Wi-Fi", icon: "wifi_tethering", section: "Connections", detail: "Enable or disable wireless networking", action: "wifi-toggle", keywords: "internet radio" },
        { name: "Toggle Bluetooth", icon: "bluetooth", section: "Connections", detail: "Enable or disable Bluetooth", action: "bluetooth-toggle", keywords: "radio devices" },
        { name: "Proton VPN", icon: "vpn_lock", section: "Connections", detail: "Open the Proton VPN application", action: "proton-vpn", keywords: "privacy tunnel" },

        { name: "Display Settings", icon: "monitor", section: "Displays", detail: "Arrange, scale and configure monitors", action: "display-settings", keywords: "screen resolution" },
        { name: "Toggle Laptop Display", icon: "laptop", section: "Displays", detail: "Enable or disable the built-in panel safely", action: "display-toggle-internal", keywords: "screen monitor internal" },

        { name: "Full Screenshot", icon: "screenshot_monitor", section: "Capture", detail: "Capture every display to Pictures/Screenshots", action: "capture-full", keywords: "image print screen" },
        { name: "Region Screenshot", icon: "screenshot_region", section: "Capture", detail: "Select a region to capture", action: "capture-region", keywords: "image area" },
        { name: "Start or Stop Region Recording", icon: "screen_record", section: "Capture", detail: "Select a region and toggle video recording", action: "capture-video", keywords: "video screencast" },
        { name: "Toggle Recording Audio", icon: "audio_file", section: "Capture", detail: "Include or exclude system audio in recordings", action: "capture-audio-toggle", keywords: "video sound" },

        { name: "Picture-in-Picture Controls", icon: "picture_in_picture_alt", section: "Windows", detail: "Open the pinned-window control palette", action: "pip-controls", keywords: "floating pin" },
        { name: "Toggle Pin Focused Window", icon: "push_pin", section: "Windows", detail: "Keep the focused window visible across workspaces", action: "pip-toggle-pin", keywords: "floating picture" },
        { name: "Toggle Scratchpad", icon: "inventory_2", section: "Windows", detail: "Show or hide this display's scratchpad", action: "scratchpad-toggle", keywords: "hide workspace" },
        { name: "Send Window to Scratchpad", icon: "move_to_inbox", section: "Windows", detail: "Move the focused window into the scratchpad", action: "scratchpad-send", keywords: "hide workspace" },

        { name: "Power & Sleep Settings", icon: "bedtime", section: "Power", detail: "Configure suspend, locking and screen timeouts", action: "power-settings", keywords: "battery idle suspend" },

        { name: "Toggle Quiet Mode", icon: "notifications_off", section: "Focus", detail: "Toggle Do Not Disturb", action: "notifications-toggle", keywords: "silence dnd" },
        { name: "Quiet for One Hour", icon: "timer", section: "Focus", detail: "Silence notifications for the next hour", action: "notifications-1h", keywords: "dnd" },
        { name: "Quiet Until Morning", icon: "dark_mode", section: "Focus", detail: "Silence notifications until tomorrow morning", action: "notifications-morning", keywords: "dnd sleep" },
        { name: "Resume Notifications", icon: "notifications_active", section: "Focus", detail: "Turn Do Not Disturb off", action: "notifications-resume", keywords: "dnd sound" },
        { name: "Toggle Stay Awake", icon: "coffee", section: "Focus", detail: "Prevent the system from sleeping", action: "keep-awake-toggle", keywords: "caffeine inhibit" },
        { name: "Reminders", icon: "alarm_add", section: "Focus", detail: "Create or manage private local reminders", action: "reminders", keywords: "timer task" },
        { name: "Dictate", icon: "mic", section: "Focus", detail: "Start voice dictation into the focused application", action: "dictate", keywords: "speech voice" },
        { name: "Toggle Night Light", icon: "nightlight", section: "Focus", detail: "Reduce blue light for nighttime use", action: "night-light-toggle", keywords: "warm display" },

        { name: "Lock Now", icon: "lock", section: "Security", detail: "Lock this session immediately", action: "lock-now", keywords: "password fingerprint" },
        { name: "Preview Lock Screen", icon: "preview", section: "Security", detail: "Open the lock screen in demonstration mode", action: "lock-preview", keywords: "password fingerprint" },
        { name: "Lock Screen Settings", icon: "admin_panel_settings", section: "Security", detail: "Configure locking and screensaver behavior", action: "lock-settings", keywords: "password fingerprint" },
        { name: "Set Up Fingerprints", icon: "fingerprint", section: "Security", detail: "Enroll login or administrator fingerprints", action: "fingerprint", keywords: "biometric sudo unlock" },

        { name: "All Settings", icon: "settings", section: "System", detail: "Open the complete system settings", action: "settings", keywords: "configure preferences" },
        { name: "Update NixOS Packages", icon: "system_update", section: "System", detail: "Update reviewed inputs and switch generations safely", action: "update", keywords: "upgrade rebuild" }
    ]

    function getItems(query) {
        const needle = (query || "").toLowerCase().trim();
        return actions.filter(entry => {
            const haystack = [entry.name, entry.section, entry.detail, entry.keywords].join(" ").toLowerCase();
            return needle.length === 0 || haystack.includes(needle);
        }).map(entry => ({
            name: entry.name,
            icon: "material:" + entry.icon,
            comment: entry.section + " · " + entry.detail,
            action: entry.action,
            categories: [entry.section]
        }));
    }

    function executeItem(item) {
        if (!item?.action)
            return;
        Quickshell.execDetached(["/run/current-system/sw/bin/mariano-system-action", item.action]);
    }
}
