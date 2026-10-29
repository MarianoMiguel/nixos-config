import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import qs.Widgets

// A removable drive on Storage & drives: its label (or make and model), what
// it is and where it is mounted, Open and Eject; a usage bar when it is
// mounted; each volume on its own line when it has several. While an action
// runs its button turns; a failure takes the line in error ink.
Item {
    id: root
    property var drive: ({})
    property string busy: ""                // Drives.busy for this drive
    property string error: ""
    readonly property var vols: drive.volumes || []
    readonly property bool single: vols.length <= 1
    readonly property var first: vols.length ? vols[0] : null
    readonly property bool readable: vols.some(v => !v.locked && v.fstype)
    Layout.fillWidth: true
    implicitHeight: column.implicitHeight + 24

    function fsLine(v) { return Drives.fsName(v.fstype) + (v.encrypted ? ", encrypted" : ""); }
    function freeLine(v) { return v.free > 0 ? Drives.bytes(v.free) + " free" : "Full"; }
    readonly property string subtitle: {
        const d = root.drive, parts = [];
        if (single && d.label) parts.push(d.name);
        parts.push(Drives.bytes(d.size));
        if (!vols.length) parts.push("No readable volume");
        else if (!single) parts.push(vols.length + " volumes");
        else if (first.locked) parts.push("Encrypted · unlock it in Files");
        else if (first.fstype) parts.push(fsLine(first));
        if (d.parked) parts.push("Ejected, safe to remove");
        else if (single && first && !first.locked && first.fstype) parts.push(first.mount || "Not mounted");
        return parts.join(" · ");
    }
    readonly property string status: busy === "eject" ? "Ejecting…" : busy === "unmount" ? "Unmounting…" : busy === "mount" || busy === "open" ? "Mounting…" : ""

    ColumnLayout {
        id: column
        x: 14; y: 12
        width: parent.width - 26
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            Rectangle {
                Layout.preferredWidth: 30; Layout.preferredHeight: 30
                Layout.alignment: Qt.AlignTop
                radius: 9
                color: Theme.rgba(Theme.ink, 0.12)
                Icon { anchors.centerIn: parent; name: root.drive.kind === "usb" ? "usb" : "drive"; size: 16; color: Theme.ink }
            }
            ColumnLayout {
                Layout.fillWidth: true; Layout.minimumWidth: 0
                spacing: 1
                // One volume: its label; several: the drive, each volume below.
                Label { text: (root.single && root.drive.label) || root.drive.name || ""; font.weight: Font.Medium; Layout.fillWidth: true }
                Label {
                    text: root.error || root.status || root.subtitle
                    color: root.error ? Theme.error : Theme.text2
                    font.pixelSize: Theme.fsS
                    Layout.fillWidth: true
                }
            }
            Button {
                visible: root.single && root.readable && !root.drive.parked
                text: "Open"
                busy: root.busy === "open" || root.busy === "mount"
                enabled: root.busy === "" || busy
                Layout.alignment: Qt.AlignVCenter
                onClicked: Drives.open(root.drive.id, "")
            }
            Button {
                visible: !!root.drive.parked && root.readable
                text: "Mount"
                Layout.alignment: Qt.AlignVCenter
                onClicked: Drives.mount(root.drive.id, "")
            }
            Button {
                visible: !root.drive.parked
                icon: "eject"
                text: "Eject"
                busy: root.busy === "eject"
                enabled: root.busy === "" || busy
                Layout.alignment: Qt.AlignVCenter
                onClicked: Drives.eject(root.drive.id)
            }
        }

        // One volume, mounted: how full it is.
        RowLayout {
            visible: root.single && !!root.first && root.first.mount !== "" && root.first.capacity > 0
            Layout.fillWidth: true
            Layout.leftMargin: 42
            spacing: 10
            StorageBar {
                Layout.fillWidth: true
                value: root.first && root.first.capacity > 0 ? root.first.used / (root.first.used + root.first.free) : 0
            }
            Label {
                text: root.first ? root.freeLine(root.first) : ""
                color: Theme.text2
                font.pixelSize: Theme.fsS
                font.features: { "tnum": 1 }
            }
        }

        // Several volumes: one line each, with its own Open.
        Repeater {
            model: root.single ? [] : root.vols
            RowLayout {
                id: line
                required property var modelData
                required property int index
                readonly property var v: modelData
                Layout.fillWidth: true
                Layout.leftMargin: 42
                spacing: 10
                ColumnLayout {
                    Layout.fillWidth: true; Layout.minimumWidth: 0
                    spacing: 3
                    Label { text: line.v.label || ("Volume " + (line.index + 1)); font.pixelSize: Theme.fsS; font.weight: Font.Medium; Layout.fillWidth: true }
                    Label {
                        text: {
                            const v = line.v, parts = [];
                            if (v.locked) parts.push("Encrypted · unlock it in Files");
                            else if (v.fstype) parts.push(root.fsLine(v));
                            parts.push(Drives.bytes(v.size));
                            if (!v.locked && v.fstype) parts.push(v.mount ? (v.capacity > 0 ? root.freeLine(v) : v.mount) : "Not mounted");
                            return parts.join(" · ");
                        }
                        color: Theme.text2
                        font.pixelSize: Theme.fsS
                        font.features: { "tnum": 1 }
                        Layout.fillWidth: true
                    }
                    StorageBar {
                        visible: line.v.mount !== "" && line.v.capacity > 0
                        Layout.fillWidth: true
                        Layout.topMargin: 2
                        implicitHeight: 4
                        value: line.v.capacity > 0 ? line.v.used / (line.v.used + line.v.free) : 0
                    }
                }
                Button {
                    visible: !line.v.locked && !!line.v.fstype && !root.drive.parked
                    text: "Open"
                    enabled: root.busy === ""
                    Layout.alignment: Qt.AlignVCenter
                    onClicked: Drives.open(root.drive.id, line.v.device)
                }
            }
        }
    }
}
