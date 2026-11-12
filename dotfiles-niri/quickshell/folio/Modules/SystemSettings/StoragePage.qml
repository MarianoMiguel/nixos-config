import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import qs.Widgets

// Storage & drives: how full this computer is, the removable drives plugged
// in (Open, Eject), the Trash (emptying it counts down in a toast; Cancel
// stops it) and how to reclaim space on NixOS: the commands to run, which
// this page never runs. Data and actions are Services/Drives; its fixtures
// (`drives fixture normal|stress|empty`, `drives plug`) drive every state.
SettingsPage {
    id: page
    title: "Storage & drives"
    description: "How full this computer is, the drives plugged into it, and the Trash."

    Component.onCompleted: Drives.watch()
    Component.onDestruction: Drives.unwatch()

    function separate(m) { return Drives.volumes.some(v => v.mount === m); }
    function list(parts) { return parts.length > 1 ? parts.slice(0, -1).join(", ") + " and " + parts[parts.length - 1] : parts[0]; }
    // What a filesystem holds, and how it is formatted.
    function note(v) {
        if (!v || !v.mount) return "";
        let what = v.source || "";
        if (v.mount === "/") {
            const parts = ["the system"];
            if (!separate("/nix")) parts.push("the Nix store");
            if (!separate("/home")) parts.push("your home folder");
            what = "Holds " + list(parts);
        } else if (v.mount === "/home") what = "Your files and settings";
        else if (v.mount.indexOf("/nix") === 0) what = "Packages and every kept system generation";
        else if (v.name === "Boot") what = "Kernels for the boot menu";
        const fs = Drives.fsName(v.fstype) + (v.encrypted ? ", encrypted" : "");
        return what && fs ? what + " · " + fs : what || fs;
    }
    readonly property string disksLine: Drives.disks.map(d => (d.model || "Disk") + " · " + Drives.bytes(d.size) + (d.bus ? " " + d.bus : "")).join("; ")
    readonly property string trashLine: {
        const t = Drives.trash;
        if (!t.known) return "Counting…";
        if (Drives.emptying) return "Emptying in a few seconds";
        if (t.items === 0) return "Empty";
        const n = Number(t.items).toLocaleString(Qt.locale("en_US"), "f", 0);
        return n + (t.items === 1 ? " item · " : " items · ") + Drives.bytes(t.size);
    }
    readonly property string cleanupLine: {
        const c = Drives.cleanup;
        if (!c.known) return "";
        const kept = c.generations === 1 ? "1 system generation kept" : c.generations + " system generations kept";
        if (!c.gc) return "Not scheduled · " + kept;
        const when = c.next > 0 ? new Date(c.next).toLocaleDateString(Qt.locale("en_GB"), "dddd d MMMM") : "";
        return "Runs on its own" + (when ? ", next on " + when : "") + " · " + kept;
    }

    // ------------------------------------------------------- This computer
    Section {
        title: "This computer"
        hint: page.disksLine
    }
    Notice {
        visible: Drives.usageRead && Drives.volumeIds.length === 0
        text: "Could not read how full the disks are."
    }
    Card {
        visible: Drives.volumeIds.length > 0
        divided: true
        Repeater {
            model: Drives.volumeIds
            StorageVolume {
                required property string modelData
                volume: Drives.volume(modelData) || ({})
                note: page.note(volume)
                onReclaim: page.scrollTo("reclaim")
            }
        }
    }

    // ---------------------------------------------------- Removable drives
    Section {
        title: "Removable drives"
        hint: "USB drives and memory cards. Eject one before unplugging it, so nothing is lost."
        Component.onCompleted: page.mark("drives", this)
    }
    Notice {
        visible: !Drives.available
        text: "Drive detection needs UDisks2, which is not running."
    }
    Notice {
        visible: Drives.available && Drives.driveIds.length === 0
        icon: "usb"
        text: "No removable drives. Plug in a USB drive or a memory card and it shows up here."
    }
    Card {
        visible: Drives.available && Drives.driveIds.length > 0
        divided: true
        Repeater {
            model: Drives.driveIds
            StorageDrive {
                required property string modelData
                drive: Drives.drive(modelData) || ({})
                busy: Drives.busy[modelData] || ""
                error: Drives.errors[modelData] || ""
            }
        }
    }
    Card {
        visible: Drives.available
        Layout.topMargin: 10
        SettingRow {
            icon: "usb"
            label: "Mount drives when they are plugged in"
            hint: "Their files are ready to open at once."
            Toggle {
                checked: Settings.get("drives.automount") !== false
                onToggled: v => Settings.set("drives.automount", v)
            }
        }
    }

    // --------------------------------------------------------------- Trash
    Section {
        title: "Trash"
        hint: "Files you delete wait here until you empty it. Emptying can't be undone."
        Component.onCompleted: page.mark("trash", this)
    }
    Card {
        Item {
            Layout.fillWidth: true
            implicitHeight: 60
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14; anchors.rightMargin: 12
                spacing: 12
                Rectangle {
                    Layout.preferredWidth: 30; Layout.preferredHeight: 30
                    radius: 9
                    color: Theme.rgba(Theme.ink, 0.12)
                    StorageGlyph { anchors.centerIn: parent; size: 16; color: Theme.ink }
                }
                ColumnLayout {
                    Layout.fillWidth: true; Layout.minimumWidth: 0
                    spacing: 1
                    Label { text: "Trash"; font.weight: Font.Medium; Layout.fillWidth: true }
                    Label { text: page.trashLine; color: Theme.text2; font.pixelSize: Theme.fsS; font.features: { "tnum": 1 }; Layout.fillWidth: true }
                }
                Button { text: "Open"; onClicked: Drives.openTrash() }
                Button {
                    text: "Empty Trash"
                    enabled: Drives.trash.known && Drives.trash.items > 0 && !Drives.emptying
                    onClicked: Drives.askEmptyTrash()
                }
            }
        }
    }

    // ------------------------------------------------------- Reclaim space
    Section {
        title: "Reclaim space"
        hint: "NixOS keeps earlier systems so you can roll back to them. These commands free their space; copy one into a terminal. This page never runs them."
        Component.onCompleted: page.mark("reclaim", this)
    }
    Card {
        SettingRow {
            icon: "reload"
            label: "Automatic cleanup"
            hint: page.cleanupLine
        }
    }
    Card {
        Layout.topMargin: 10
        divided: true
        StorageCommand {
            title: "Delete old generations and unused packages"
            hint: "Keeps the last two weeks of systems to roll back to."
            command: "sudo nix-collect-garbage --delete-older-than 14d"
        }
        StorageCommand {
            title: "Remove their boot entries"
            hint: "After a cleanup, so the boot menu and /boot keep only systems that still exist."
            command: "sudo /run/current-system/bin/switch-to-configuration boot"
        }
        StorageCommand {
            title: "Deduplicate the store"
            hint: Drives.cleanup.optimise ? "Runs on its own here; worth running right after a big cleanup." : "Links identical files in the Nix store together."
            command: "nix store optimise"
        }
        StorageCommand {
            title: "Shrink the system journal"
            hint: "Keeps the newest 500 MB of logs."
            command: "sudo journalctl --vacuum-size=500M"
        }
        StorageCommand {
            title: "Find what fills your home folder"
            hint: "Only reads; it can take a minute."
            command: "du -xh -d1 ~ 2>/dev/null | sort -h | tail -n 15"
        }
    }
}
