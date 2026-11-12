import QtQuick
import qs.Common

// A usage bar (the kit's progress line): the used part in ink on a well
// track, warning from 90 % and error from 97 %. The fill glides on a spring,
// so a refresh mid-move keeps its velocity.
Item {
    id: root
    property real value: 0                  // used, 0..1
    property real warnAt: 0.9
    property real criticalAt: 0.97
    readonly property color tone: value >= criticalAt ? Theme.error : value >= warnAt ? Theme.warning : Theme.ink
    implicitHeight: 6

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Theme.wellStrong
    }
    Rectangle {
        height: parent.height
        radius: height / 2
        width: root.value > 0 ? Math.max(height, parent.width * Math.min(1, root.value)) : 0
        color: root.tone
        Behavior on width { SpringPanel {} }
        Behavior on color { ColorAnimation { duration: Theme.tQuick } }
    }
}
