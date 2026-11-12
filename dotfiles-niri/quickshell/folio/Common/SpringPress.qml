import QtQuick

// Presses and small state changes: quick, a touch of give.
SpringAnimation {
    spring: 7
    damping: 0.42
    mass: 0.6
    epsilon: 0.002
}
