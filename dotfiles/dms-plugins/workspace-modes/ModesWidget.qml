// Bar pill showing the current workspace's window mode on this monitor,
// with a COSMIC-style popout to switch between tile, float, and focus.
//
// Each bar instance resolves its own output, and every switch is sent with
// --output, so a click here never changes the mode on another monitor.

import QtQuick
import QtQuick.Window
import Quickshell
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    layerNamespacePlugin: "workspace-modes"

    property string outputName: ""

    // Mirror the daemon's plugin-global state. getGlobalVar is read on demand
    // and refreshed whenever the daemon publishes via globalVarChanged.
    property var modesOutputs: ({})
    property bool modesConnected: false

    function _refreshGlobals() {
        if (!root.pluginService || !root.pluginId) {
            root.modesOutputs = ({});
            root.modesConnected = false;
            return;
        }
        root.modesOutputs = root.pluginService.getGlobalVar(root.pluginId, "modesOutputs", ({}));
        root.modesConnected = root.pluginService.getGlobalVar(root.pluginId, "modesConnected", false);
    }

    onPluginServiceChanged: root._refreshGlobals()
    Component.onCompleted: root._refreshGlobals()

    Connections {
        target: root.pluginService
        function onGlobalVarChanged(changedPluginId, varName) {
            if (changedPluginId === root.pluginId)
                root._refreshGlobals();
        }
    }

    readonly property var modeOptions: [
        {
            "id": "tile",
            "label": "Tile",
            "icon": "view_week",
            "detail": "Scrollable columns, niri's native layout"
        },
        {
            "id": "float",
            "label": "Float",
            "icon": "layers",
            "detail": "Free windows; Super+drag moves, Super+right-drag resizes"
        },
        {
            "id": "focus",
            "label": "Focus",
            "icon": "crop_free",
            "detail": "One centered app at a time, nothing else visible"
        }
    ]

    readonly property var outputState: {
        const all = root.modesOutputs;
        if (!all || !root.outputName)
            return null;
        return all[root.outputName] || null;
    }

    readonly property string currentMode: outputState ? (outputState.mode || "tile") : "tile"

    readonly property var currentOption: {
        for (const option of modeOptions) {
            if (option.id === currentMode)
                return option;
        }
        return modeOptions[0];
    }

    readonly property color pillColor: {
        if (!root.modesConnected)
            return Theme.surfaceVariantText;
        return currentMode === "tile" ? Theme.surfaceText : Theme.primary;
    }

    function setMode(mode) {
        const command = ["niri-modes", "set", mode];
        // Only scope the switch to this monitor when the daemon actually reports
        // an output by this name. A stale or mismatched Screen.name would
        // otherwise pass --output <unknown>, which niri-modes rejects, turning
        // the click into a silent no-op; falling back to the focused output is
        // always correct on a single monitor.
        const outputs = root.modesOutputs;
        if (root.outputName !== "" && outputs && outputs[root.outputName])
            command.push("--output", root.outputName);
        console.info("WorkspaceModes: setMode", mode, "output=" + root.outputName, "scoped=" + (command.length > 3));
        Quickshell.execDetached(command);
    }

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS

            Component.onCompleted: root.outputName = Screen.name

            DankIcon {
                name: root.currentOption.icon
                size: Theme.iconSize
                color: root.pillColor
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                text: root.currentOption.label
                visible: root.currentMode !== "tile"
                color: root.pillColor
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.Medium
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    verticalBarPill: Component {
        DankIcon {
            name: root.currentOption.icon
            size: Theme.iconSize
            color: root.pillColor

            Component.onCompleted: root.outputName = Screen.name
        }
    }

    popoutWidth: 380

    popoutContent: Component {
        PopoutComponent {
            id: popout

            headerText: "Workspace mode"
            detailsText: root.modesConnected
                ? "Applies only to this monitor's current workspace"
                : "niri-modes is not running"
            showCloseButton: true

            Column {
                width: parent.width
                spacing: Theme.spacingS

                Repeater {
                    model: root.modeOptions

                    StyledRect {
                        id: optionCard

                        required property var modelData

                        readonly property bool active: root.currentMode === modelData.id

                        width: parent.width
                        height: optionRow.implicitHeight + Theme.spacingM * 2
                        radius: Theme.cornerRadius
                        color: active ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh
                        border.width: active ? 2 : 0
                        border.color: Theme.primary

                        Row {
                            id: optionRow

                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.spacingM
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.spacingM
                            spacing: Theme.spacingM

                            DankIcon {
                                name: modelData.icon
                                size: Theme.iconSizeLarge
                                color: active ? Theme.primary : Theme.surfaceText
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Column {
                                width: parent.width - Theme.iconSizeLarge - Theme.spacingM
                                spacing: 2
                                anchors.verticalCenter: parent.verticalCenter

                                StyledText {
                                    text: modelData.label
                                    font.pixelSize: Theme.fontSizeMedium
                                    font.weight: Font.DemiBold
                                    color: active ? Theme.primary : Theme.surfaceText
                                }

                                StyledText {
                                    width: parent.width
                                    text: modelData.detail
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                    wrapMode: Text.WordWrap
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.setMode(optionCard.modelData.id)
                        }
                    }
                }

                StyledText {
                    width: parent.width
                    text: "Mod+Alt+Space cycles modes · Mod+Alt+Scroll steps one app in focus mode"
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }
    }
}
