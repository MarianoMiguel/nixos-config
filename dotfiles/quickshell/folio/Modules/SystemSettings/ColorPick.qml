import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Widgets
import "../../Common/Looks.js" as Looks

// Any color for the theme: a hue strip, a vividness strip and a #rrggbb
// field. Dragging shows the color at once (moved); letting go, Enter or the
// arrow keys choose it (chosen), and apps follow. Under it, the color as the
// theme will show it in light and dark, kept readable by Looks.derive.
ColumnLayout {
    id: root
    property string theme: Theme.name
    property string value: ""                 // the custom #rrggbb, if any
    signal moved(string hex)
    signal chosen(string hex)
    spacing: 10

    // Hue and vividness of the current value. Placed by hand, not bound, so
    // dragging can move them; a new value places them again.
    property real hue: 0
    property real vivid: 0
    function place() {
        const o = Looks.oklch(value || "#5a7cf0");
        hue = o[2];
        vivid = Math.max(0, Math.min(1, (o[1] - 0.02) / 0.2));
    }
    Component.onCompleted: place()
    onValueChanged: if (!strip.pressed && !vividStrip.pressed) place()
    // The picked color for a hue and vividness; derive() sets the lightness.
    function at(h, v) { return Looks.lch(0.62, 0.02 + v * 0.2, h); }
    readonly property string hex: at(hue, vivid)
    readonly property var light: Looks.derive(theme, "light", hex)
    readonly property var dark: Looks.derive(theme, "dark", hex)

    component Strip: Item {
        id: s
        property real fraction
        property alias pressed: area.pressed
        property alias fill: bar.gradient
        signal dragged(real f)
        signal released()
        Layout.fillWidth: true
        implicitHeight: 26
        activeFocusOnTab: true
        Keys.onPressed: event => {
            const step = event.modifiers & Qt.ShiftModifier ? 0.1 : 0.02;
            if (event.key === Qt.Key_Left || event.key === Qt.Key_Right) {
                s.dragged(Math.max(0, Math.min(1, s.fraction + (event.key === Qt.Key_Left ? -step : step))));
                s.released();
                event.accepted = true;
            }
        }
        FocusRing { radius: height / 2 }
        Rectangle { id: bar; anchors.fill: parent; radius: height / 2; border.width: 1; border.color: Theme.rule }
        Rectangle {
            x: s.fraction * (s.width - width); anchors.verticalCenter: parent.verticalCenter
            width: 22; height: 22; radius: 11; color: "transparent"
            border.width: 3; border.color: "#ffffff"
            Rectangle { anchors.fill: parent; anchors.margins: -1; radius: 12; color: "transparent"; border.width: 1; border.color: Theme.rgba(Theme.shade, 0.35) }
        }
        MouseArea {
            id: area
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            preventStealing: true
            function to(x) { s.dragged(Math.max(0, Math.min(1, x / s.width))); }
            onPressed: mouse => to(mouse.x)
            onPositionChanged: mouse => to(mouse.x)
            onReleased: s.released()
        }
    }

    Strip {
        id: strip
        fraction: root.hue / 360
        fill: Gradient {
            orientation: Gradient.Horizontal
                GradientStop { position: 0.0000; color: root.at(0, 1) }
                GradientStop { position: 0.0833; color: root.at(30, 1) }
                GradientStop { position: 0.1667; color: root.at(60, 1) }
                GradientStop { position: 0.2500; color: root.at(90, 1) }
                GradientStop { position: 0.3333; color: root.at(120, 1) }
                GradientStop { position: 0.4167; color: root.at(150, 1) }
                GradientStop { position: 0.5000; color: root.at(180, 1) }
                GradientStop { position: 0.5833; color: root.at(210, 1) }
                GradientStop { position: 0.6667; color: root.at(240, 1) }
                GradientStop { position: 0.7500; color: root.at(270, 1) }
                GradientStop { position: 0.8333; color: root.at(300, 1) }
                GradientStop { position: 0.9167; color: root.at(330, 1) }
                GradientStop { position: 1.0000; color: root.at(360, 1) }
        }
        onDragged: f => { root.hue = f * 360; root.moved(root.hex); }
        onReleased: root.chosen(root.hex)
    }
    Strip {
        id: vividStrip
        fraction: root.vivid
        fill: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: root.at(root.hue, 0) }
            GradientStop { position: 0.5; color: root.at(root.hue, 0.5) }
            GradientStop { position: 1; color: root.at(root.hue, 1) }
        }
        onDragged: f => { root.vivid = f; root.moved(root.hex); }
        onReleased: root.chosen(root.hex)
    }
    RowLayout {
        Layout.fillWidth: true; spacing: 10
        Field {
            id: field
            Layout.preferredWidth: 120
            text: root.value || root.hex
            placeholder: "#rrggbb"
            error: text !== "" && !/^#?[0-9a-fA-F]{6}$/.test(text)
            onAccepted: t => { const h = (t.startsWith("#") ? t : "#" + t).toLowerCase(); if (/^#[0-9a-f]{6}$/.test(h)) root.chosen(h); }
        }
        // The color as the theme shows it, in light and in dark.
        Repeater {
            model: [["Light", root.light, Looks.BACKGROUND[root.theme].light], ["Dark", root.dark, Looks.BACKGROUND[root.theme].dark]]
            Rectangle {
                required property var modelData
                Layout.preferredWidth: 96; Layout.preferredHeight: 34; radius: Theme.rS
                color: modelData[2]; border.color: Theme.rule
                Rectangle { anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 6 } width: 22; height: 22; radius: 11; color: parent.modelData[1][0] }
                Text { anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 36 } text: parent.modelData[0]; color: parent.modelData[1][0]; font.family: Theme.ui; font.pixelSize: Theme.fsS; font.weight: Font.DemiBold }
            }
        }
        Label {
            Layout.fillWidth: true; Layout.minimumWidth: 0
            color: Theme.text2; font.pixelSize: Theme.fsS
            text: {
                const l = Looks.oklch(root.light[0])[0], d = Looks.oklch(root.dark[0])[0], p = Looks.oklch(root.hex)[0];
                return Math.abs(l - p) < 0.03 && Math.abs(d - p) < 0.03 ? "Shown as picked." : "Deepened or lightened to stay readable.";
            }
        }
    }
}
