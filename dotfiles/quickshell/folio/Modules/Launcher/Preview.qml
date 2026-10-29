import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import "Search.js" as Search

// Quick Look for the selected result: what it is and what Enter will do,
// with all of its actions as buttons. The ink button is the one Enter runs;
// Tab moves the keyboard here.
Item {
    id: root
    property var item: null
    property var actions: []
    property int active: 0
    property bool focused: false        // the keyboard is in the actions
    property real now: Date.now()
    property bool awake: true           // false while the launcher is closed
    signal run(int index)

    readonly property string kind: item ? item.kind : ""

    // Files: images print from the file; small text files show their start.
    readonly property string peekPath: kind === "file" && awake && item.type.preview === "text" && item.size < 262144 ? item.path : ""
    property string peekText: ""
    onPeekPathChanged: peekText = ""
    FileView {
        id: peek
        path: root.peekPath
        printErrors: false
        onLoaded: {
            const t = path === root.peekPath ? text() : "";
            root.peekText = t.indexOf("\u0000") >= 0 ? "" : t.slice(0, 4000);
        }
        onLoadFailed: root.peekText = ""
    }
    readonly property string imageSource: kind === "file" && awake && item.type.preview === "image" && item.size < 40000000
        ? "file://" + item.path.split("/").map(encodeURIComponent).join("/") : ""

    ColumnLayout {
        anchors { fill: parent; margins: 20; topMargin: 18; bottomMargin: 16 }
        spacing: 0
        visible: root.item !== null

        Cap {
            text: {
                const it = root.item || {};
                switch (root.kind) {
                case "app": return "Application";
                case "appAction": return "Action · " + (it.appName || "");
                case "system": return "Action";
                case "calc": return "Calculator";
                case "unit": return "Conversion · " + (it.calc ? it.calc.kind : "");
                case "clip": return "Clipboard · " + Search.ago(it.time || 0, root.now);
                case "file": return it.type ? it.type.label + (it.type.ext ? " · " + it.type.ext.toUpperCase() : "") : "File";
                case "emoji": return "Emoji · " + (it.group || "");
                case "web": return "Web";
                }
                return "";
            }
            Layout.fillWidth: true
        }

        // App, desktop action, system action and web: a picture and words.
        ColumnLayout {
            visible: ["calc", "unit", "clip", "file", "emoji"].indexOf(root.kind) < 0
            spacing: 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: 14

            ResultIcon {
                visible: !thumb.visible
                size: 52
                icon: root.item && root.item.icon || ""
                glyph: root.item && root.item.glyph || "grid"
                filled: root.kind === "system" || root.kind === "web"
            }
            // Plate actions show the plate itself, printed as it will be: the
            // next plate dissolves in, a mode change bleeds across it.
            Item {
                id: thumb
                visible: !!(root.item && root.item.plate)
                Layout.fillWidth: true
                Layout.preferredHeight: Math.round(width * 0.56)
                layer.enabled: visible
                layer.effect: MultiEffect {
                    maskEnabled: true
                    maskSource: thumbMask
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 1.0
                }
                // Loaded only while shown: plates are full-size images.
                Loader {
                    anchors.fill: parent
                    active: thumb.visible && root.awake
                    sourceComponent: Plate {
                        plate: root.item && root.item.plate || Art.current
                        forceMode: root.item && root.item.plateMode || ""
                        zoom: 1.15
                    }
                }
                Rectangle {
                    anchors.fill: parent
                    radius: Theme.rS
                    color: "transparent"
                    border.width: 1
                    border.color: Theme.rule
                }
            }
            Rectangle {
                id: thumbMask
                width: thumb.width
                height: thumb.height
                radius: Theme.rS
                visible: false
                layer.enabled: true
            }

            Label {
                text: root.kind === "web" ? "Search the web" : (root.item && root.item.title || "")
                font.pixelSize: Theme.fsL
                font.weight: Font.DemiBold
                wrapMode: Text.Wrap
                maximumLineCount: 2
                lineHeight: 1.1
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.topMargin: 14
            }
            Label {
                visible: text !== ""
                text: root.kind === "app" ? (root.item.genericName || "") : root.kind === "appAction" ? (root.item.appName || "") : ""
                font.pixelSize: Theme.fsS
                color: Theme.text2
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.topMargin: 3
            }
            Label {
                text: {
                    const it = root.item || {};
                    if (root.kind === "web") return "“" + (it.query || "") + "”";
                    return it.description || "";
                }
                font.pixelSize: Theme.fsS
                color: root.kind === "web" ? Theme.text : Theme.text2
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                maximumLineCount: 6
                lineHeight: 1.25
                verticalAlignment: Text.AlignTop
                clip: true
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 0
                Layout.minimumWidth: 0
                Layout.topMargin: 10
            }
            // What it is underneath: a desktop id, a command. Kept as typed.
            Label {
                visible: text !== ""
                text: root.item && root.item.meta || ""
                font.family: Theme.mono
                font.pixelSize: Theme.fsCap
                font.letterSpacing: 0.3
                color: Theme.text3
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.topMargin: 8
            }
        }

        // Calculator and conversions: the sum and its result, printed large;
        // a conversion lists the same amount in other units under it.
        ColumnLayout {
            visible: root.kind === "calc" || root.kind === "unit"
            spacing: 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: 18

            Label {
                text: parent.visible ? root.item.calc.expression + " =" : ""
                font.family: Theme.mono
                font.pixelSize: Theme.fsM
                color: Theme.text2
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                maximumLineCount: 3
                Layout.fillWidth: true
                Layout.minimumWidth: 0
            }
            Text {
                text: parent.visible ? root.item.calc.text : ""
                color: Theme.ink
                font.family: Theme.hero
                font.pixelSize: 72
                fontSizeMode: Text.HorizontalFit
                minimumPixelSize: 26
                textFormat: Text.PlainText
                Layout.fillWidth: true
                Layout.topMargin: 6
            }
            Repeater {
                model: root.kind === "unit" ? root.item.calc.also : []
                Label {
                    required property string modelData
                    required property int index
                    text: "= " + modelData
                    font.family: Theme.mono
                    font.pixelSize: Theme.fsS
                    color: Theme.text2
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.topMargin: index ? 4 : 10
                }
            }
            Item { Layout.fillHeight: true }
        }

        // A file: the image or the start of the text when that is cheap, its
        // name, where it is, when it changed.
        ColumnLayout {
            visible: root.kind === "file"
            spacing: 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: 14

            readonly property bool picture: image.status === Image.Ready && root.imageSource !== ""
            readonly property bool page: root.peekText !== ""

            ResultIcon {
                visible: !parent.picture && !parent.page
                size: 52
                glyph: root.kind === "file" ? root.item.glyph : "note"
                filled: true
            }
            Rectangle {
                visible: parent.picture
                radius: Theme.rS
                color: Theme.well
                border.width: 1
                border.color: Theme.rule
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 0
                Image {
                    id: image
                    anchors { fill: parent; margins: 6 }
                    source: root.imageSource
                    sourceSize: Qt.size(520, 360)
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    smooth: true
                    mipmap: true
                }
            }
            Rectangle {
                visible: parent.page
                radius: Theme.rS
                color: Theme.well
                border.width: 1
                border.color: Theme.rule
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 0
                Text {
                    anchors { fill: parent; margins: 10 }
                    text: root.peekText
                    color: Theme.text2
                    font.family: Theme.mono
                    font.pixelSize: Theme.fsCap
                    lineHeight: 1.15
                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    clip: true
                }
            }
            Label {
                text: root.kind === "file" ? root.item.name : ""
                font.pixelSize: Theme.fsL
                font.weight: Font.DemiBold
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                maximumLineCount: parent.picture || parent.page ? 1 : 3
                lineHeight: 1.1
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.topMargin: 12
            }
            Label {
                text: root.kind === "file" ? root.item.folder : ""
                elide: Text.ElideMiddle
                font.pixelSize: Theme.fsS
                color: Theme.text2
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.topMargin: 3
            }
            Label {
                text: root.kind === "file" ? root.item.description : ""
                font.pixelSize: Theme.fsS
                color: Theme.text3
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.topMargin: 2
            }
            Item { visible: !parent.picture && !parent.page; Layout.fillHeight: true }
        }

        // An emoji, large, with the words it is found by.
        ColumnLayout {
            visible: root.kind === "emoji"
            spacing: 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: 10

            Text {
                text: root.kind === "emoji" ? root.item.char : ""
                font.pixelSize: 84
                textFormat: Text.PlainText
            }
            Label {
                text: root.kind === "emoji" ? root.item.title : ""
                font.pixelSize: Theme.fsL
                font.weight: Font.DemiBold
                wrapMode: Text.Wrap
                maximumLineCount: 2
                lineHeight: 1.1
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.topMargin: 8
            }
            Label {
                text: root.kind === "emoji" ? root.item.keywords : ""
                visible: text !== ""
                font.pixelSize: Theme.fsS
                color: Theme.text2
                wrapMode: Text.WordWrap
                maximumLineCount: 3
                lineHeight: 1.25
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.topMargin: 6
            }
            Item { Layout.fillHeight: true }
            Label {
                text: root.kind === "emoji" ? Search.codepoints(root.item.char) : ""
                font.family: Theme.mono
                font.pixelSize: Theme.fsCap
                font.letterSpacing: 0.3
                color: Theme.text3
                Layout.fillWidth: true
                Layout.minimumWidth: 0
            }
        }

        // Clipboard: the whole text, as copied.
        ColumnLayout {
            visible: root.kind === "clip"
            spacing: 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: 12

            Rectangle {
                radius: Theme.rS
                color: Theme.well
                border.width: 1
                border.color: Theme.rule
                Layout.fillWidth: true
                Layout.fillHeight: true
                Text {
                    anchors { fill: parent; margins: 12 }
                    text: root.kind === "clip" ? root.item.text.slice(0, 4000) : ""
                    color: Theme.text
                    font.family: Theme.mono
                    font.pixelSize: Theme.fsS
                    lineHeight: 1.2
                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    clip: true
                }
            }
            Cap {
                text: {
                    if (root.kind !== "clip") return "";
                    const t = root.item.text;
                    const lines = t.split("\n").length;
                    return t.length + " characters" + (lines > 1 ? " · " + lines + " lines" : "");
                }
                Layout.fillWidth: true
                Layout.topMargin: 8
            }
        }

        // Actions: Enter runs the ink one.
        ListView {
            id: actionList
            model: root.actions
            spacing: 6
            interactive: contentHeight > height
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            currentIndex: root.active
            onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(contentHeight, 4 * 32 + 3 * 6)
            Layout.topMargin: 14

            delegate: Rectangle {
                id: button
                required property var modelData
                required property int index
                readonly property bool on: index === root.active
                width: ListView.view.width
                height: 32
                radius: Theme.rS
                color: on ? Theme.ink : (hover.containsMouse ? Theme.wellStrong : Theme.well)
                border.width: on ? 0 : 1
                border.color: Theme.rule

                RowLayout {
                    anchors { fill: parent; leftMargin: 12; rightMargin: 7 }
                    spacing: 8
                    Label {
                        text: button.modelData.label
                        font.pixelSize: Theme.fsS
                        font.weight: Font.Medium
                        color: button.on ? Theme.paper : (button.modelData.danger ? Theme.error : Theme.text)
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                    }
                    KeyCap {
                        visible: button.on
                        text: "↵"
                        inverted: true
                    }
                }
                MouseArea {
                    id: hover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.run(button.index)
                }
            }
        }
    }
}
