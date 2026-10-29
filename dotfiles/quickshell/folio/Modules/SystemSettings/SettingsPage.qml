import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import qs.Common
import qs.Widgets

// One page of Settings: a heading, a line on what the page is for, and its
// content in a centred column that scrolls. A part of the page that Settings
// can open at (Settings › Wallpaper) marks itself: page.mark("wallpaper", this).
Flickable {
    id: root
    property string title
    property string description
    property var marks: ({})
    default property alias content: column.data
    readonly property real columnWidth: column.width

    function mark(id, item) { marks[id] = item; }
    // Glides to a marked part; keeps aiming while the page is still laying out.
    property string aim: ""
    function scrollTo(id) {
        aim = id;
        settled = 0;
        settle.restart();
        reaim();
    }
    function reaim() {
        const t = marks[aim];
        const y = t ? t.mapToItem(contentItem, 0, 0).y - 16 : 0;
        glide.to = Math.max(0, Math.min(y, contentHeight - height));
        glide.restart();
    }
    // Layouts place their children a frame late, so aim again for a moment.
    property int settled: 0
    Timer { id: settle; interval: 90; repeat: true; onTriggered: { root.reaim(); if (++root.settled >= 8) stop(); } }

    // A control reached by the keyboard glides into view.
    function reveal(item) {
        const y = KeyNav.scrollFor(root, item, 24);
        if (Math.abs(y - contentY) < 1) return;
        settle.stop();
        glide.to = y;
        glide.restart();
    }
    // Keys a focused control leaves: Up and Down move to the control before
    // or after it (as Shift+Tab and Tab, within the page); Page Up and Page
    // Down scroll.
    Keys.onPressed: event => {
        if (!KeyNav.plain(event) || (event.modifiers & Qt.ShiftModifier)) return;
        KeyNav.key();
        if (event.key === Qt.Key_Up || event.key === Qt.Key_Down) {
            const next = KeyNav.step(column, Window.activeFocusItem, event.key === Qt.Key_Down ? 1 : -1);
            if (next) next.forceActiveFocus(event.key === Qt.Key_Down ? Qt.TabFocusReason : Qt.BacktabFocusReason);
        } else if (event.key === Qt.Key_PageUp || event.key === Qt.Key_PageDown) {
            settle.stop();
            glide.to = Math.max(0, Math.min(contentHeight - height, contentY + (event.key === Qt.Key_PageDown ? 1 : -1) * height * 0.85));
            glide.restart();
        } else return;
        event.accepted = true;
    }

    contentHeight: column.y + column.implicitHeight + 80
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    NumberAnimation { id: glide; target: root; property: "contentY"; duration: Theme.tPanel; easing.type: Easing.OutCubic }

    ColumnLayout {
        id: column
        width: Math.min(760, root.width - 64)
        x: Math.round((root.width - width) / 2); y: 28
        spacing: 0
        Cap { text: "Settings" }
        Label { text: root.title; font.pixelSize: 26 * Theme.textScale; font.weight: Font.DemiBold; Layout.topMargin: 6; Layout.fillWidth: true }
        Text {
            visible: root.description !== ""
            text: root.description
            color: Theme.text2; font.family: Theme.ui; font.pixelSize: Theme.fsM
            wrapMode: Text.WordWrap; maximumLineCount: 3; elide: Text.ElideRight
            Layout.fillWidth: true; Layout.topMargin: 4; Layout.bottomMargin: 8
        }
    }
}
