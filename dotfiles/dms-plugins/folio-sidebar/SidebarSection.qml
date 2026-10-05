import QtQuick
import QtQuick.Controls
import qs.Common
import qs.Widgets

Column {
    id: root
    property string title
    property string icon
    property string summary: ""
    property bool expanded: false
    property Component body
    property bool visited: false
    signal toggled()
    spacing: 8
    onExpandedChanged: { if (expanded) visited = true; }
    Component.onCompleted: { if (expanded) visited = true; }

    Button {
        id: heading
        width: parent.width
        height: 56
        padding: 0
        leftPadding: 0
        rightPadding: 0
        Accessible.name: root.title + (root.summary ? ", " + root.summary : "")
        onClicked: root.toggled()
        background: Rectangle {
            radius: Theme.cornerRadius
            color: heading.hovered || heading.visualFocus ? Theme.surfaceContainerHigh : "transparent"
            border.width: heading.visualFocus ? 1 : 0
            border.color: Theme.primary
        }
        contentItem: Item {
            DankIcon {
                id: glyph
                anchors.left: parent.left; anchors.leftMargin: 0
                anchors.verticalCenter: parent.verticalCenter
                name: root.icon; size: 20; color: Theme.primary
            }
            Column {
                anchors.left: glyph.right; anchors.leftMargin: 12
                anchors.right: chevron.left; anchors.rightMargin: 0
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3
                StyledText {
                    width: parent.width; text: root.title
                    font.pixelSize: 14; font.weight: Font.Medium
                    color: Theme.surfaceText
                }
                StyledText {
                    width: parent.width; text: root.summary
                    visible: text.length > 0
                    font.pixelSize: 11; color: Theme.surfaceVariantText
                    elide: Text.ElideRight
                }
            }
            DankIcon {
                id: chevron
                anchors.right: parent.right; anchors.rightMargin: 0
                anchors.verticalCenter: parent.verticalCenter
                name: root.expanded ? "remove" : "add"
                size: 18; color: Theme.surfaceVariantText
            }
        }
    }

    // Keep the controller alive after first opening; only the surface collapses.
    // Focus drafts and CodexBar's existing refresh cadence survive drawer closes.
    Loader {
        id: content
        width: parent.width
        active: root.visited
        visible: root.expanded
        height: visible ? (item?.implicitHeight || item?.height || 0) : 0
        sourceComponent: root.body
    }
    Rectangle { width: parent.width; height: 1; color: Theme.outlineVariant }
}
