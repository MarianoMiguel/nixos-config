import QtQuick

// Panels, sheets, the island's size: firm, no visible overshoot. Springs keep
// their velocity when retargeted, so a panel reversed mid-flight turns smoothly.
SpringAnimation {
    spring: 3.4
    damping: 0.36
    mass: 1
    epsilon: 0.25
}
