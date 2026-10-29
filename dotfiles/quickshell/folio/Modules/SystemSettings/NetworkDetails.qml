import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets

// Facts about a connection (address, router, DNS, signal…) as label and
// value, two to a line on a wide page; empty values are left out. A click on
// a value copies it. rows: [[label, value], …]
GridLayout {
    id: root
    property var rows: []
    readonly property var shown: rows.filter(r => r[1] !== undefined && r[1] !== null && String(r[1]) !== "")
    Layout.fillWidth: true
    Layout.minimumWidth: 0
    columns: width > 520 ? 2 : 1
    columnSpacing: 18
    rowSpacing: 4
    uniformCellWidths: true

    Repeater {
        model: root.shown
        RowLayout {
            id: fact
            required property var modelData
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            spacing: 10
            Label { text: fact.modelData[0]; color: Theme.text3; font.pixelSize: Theme.fsS; Layout.preferredWidth: 92; Layout.minimumWidth: 92 }
            Label {
                id: value
                text: String(fact.modelData[1])
                font.pixelSize: Theme.fsS
                color: copy.containsMouse || activeFocus ? Theme.ink : Theme.text
                Layout.fillWidth: true; Layout.minimumWidth: 0
                function copyIt() { Quickshell.clipboardText = String(fact.modelData[1]); Toasts.show(fact.modelData[0] + " copied", { "icon": "check" }); }
                // Space or Enter copies it too.
                activeFocusOnTab: true
                Keys.onPressed: event => KeyNav.press(event, () => value.copyIt())
                MouseArea {
                    id: copy
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: value.copyIt()
                }
                FocusRing {
                    anchors.fill: undefined
                    width: Math.min(value.implicitWidth, value.width); height: value.height
                    radius: Theme.rXs; gap: 2
                }
            }
        }
    }
}
