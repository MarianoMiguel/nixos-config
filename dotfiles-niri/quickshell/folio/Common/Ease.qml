import QtQuick

// The one eased curve, for moves that are never interrupted (prints, fades
// out): cubic-bezier(0.2, 0, 0, 1), as in the kit.
NumberAnimation {
    duration: 320
    easing.type: Easing.BezierSpline
    easing.bezierCurve: [0.2, 0, 0, 1, 1, 1]
}
