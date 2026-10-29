import QtQuick
import qs.Common
import qs.Services

// The login score (workshop/studies/motion): when the session starts, a
// window's content arrives at its moment (Shell.delay(part)) from where it
// lives: the bar from the top, the dock from below, the island grows. Windows
// created later (a new screen) are simply there.
Item {
    id: root
    property Item target
    property string part
    property real fromY: 0
    property real fromScale: 1
    visible: false

    Component.onCompleted: {
        if (!target) return;
        const wait = Shell.delay(part);
        if (wait <= 0 || Theme.motion < 0.05) return;
        target.y = fromY;
        target.opacity = 0;
        target.scale = fromScale;
        timer.interval = wait;
        timer.start();
    }
    Timer { id: timer; onTriggered: arrive.start() }
    ParallelAnimation {
        id: arrive
        NumberAnimation { target: root.target; property: "y"; to: 0; duration: 620 * Theme.motion; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.2, 0, 0, 1, 1, 1] }
        NumberAnimation { target: root.target; property: "scale"; to: 1; duration: 620 * Theme.motion; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.2, 0, 0, 1, 1, 1] }
        NumberAnimation { target: root.target; property: "opacity"; to: 1; duration: 320 * Theme.motion }
    }
}
