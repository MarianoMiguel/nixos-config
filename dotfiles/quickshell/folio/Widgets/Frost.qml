import QtQuick
import QtQuick.Effects
import qs.Common

// The blur niri gives a sheet, for a sheet drawn over a plate inside the same
// window (the compositor only frosts what is behind a window). Put it under
// the Sheet with the same geometry; source is the plate it sits on.
Item {
    id: root
    property Item source
    property real radius: Theme.rL
    property real amount: 1

    ShaderEffectSource {
        id: grab
        anchors.fill: parent
        visible: false
        live: true
        sourceItem: root.source
        // Depends on x and y so a moving sheet keeps sampling under itself.
        sourceRect: {
            root.x; root.y; root.width; root.height;
            if (!root.source) return Qt.rect(0, 0, 0, 0);
            const p = root.mapToItem(root.source, 0, 0);
            return Qt.rect(p.x, p.y, root.width, root.height);
        }
    }
    MultiEffect {
        anchors.fill: parent
        source: grab
        blurEnabled: true
        blur: root.amount
        blurMax: 48
        saturation: 0.2
        maskEnabled: true
        maskSource: mask
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1.0
    }
    Item {
        id: mask
        anchors.fill: parent
        visible: false
        layer.enabled: true
        Rectangle { anchors.fill: parent; radius: root.radius; color: "white" }
    }
}
