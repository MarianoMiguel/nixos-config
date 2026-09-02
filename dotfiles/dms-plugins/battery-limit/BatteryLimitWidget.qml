import QtQuick
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

// A one-click charge-cap toggle that sits beside DMS's battery pill. The
// system side lives in modules/nixos/battery.nix: the `battery-charge-limit`
// helper writes the sysfs threshold (as this unprivileged process, thanks to a
// udev rule) and records the choice so a reboot restores it. This widget is
// only a view and a switch over that helper.
PluginComponent {
    id: root

    layerNamespacePlugin: "battery-limit"

    // Must match healthLimit in modules/nixos/battery.nix.
    readonly property int healthLimit: 80
    // Installed by environment.systemPackages; this path is stable per NixOS
    // generation and matches the DMS service's PATH.
    readonly property string helper: "/run/current-system/sw/bin/battery-charge-limit"

    // The live end-threshold read back from the helper. 100 means "charge
    // fully"; anything at or below 90 counts as the health cap being on.
    property int limit: 100
    property bool busy: false
    readonly property bool limited: root.limit > 0 && root.limit <= 90

    function refresh() {
        if (!readProcess.running)
            readProcess.running = true;
    }

    function setLimited(on) {
        if (root.busy)
            return;
        root.busy = true;
        // Optimistic update keeps the switch and pill snappy; the read after
        // the helper exits reconciles with the actual hardware value.
        root.limit = on ? root.healthLimit : 100;
        applyProcess.command = [root.helper, on ? "health" : "full"];
        applyProcess.running = true;
    }

    Process {
        id: readProcess

        command: [root.helper, "read"]
        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                const value = parseInt(text.trim(), 10);
                if (!isNaN(value) && value > 0)
                    root.limit = value;
            }
        }
    }

    Process {
        id: applyProcess

        running: false
        onExited: exitCode => {
            root.busy = false;
            root.refresh();
        }
    }

    // Catch changes made elsewhere (DMS settings, a shell one-liner) so the
    // pill never drifts from the real threshold.
    Timer {
        interval: 60000
        repeat: true
        running: true
        onTriggered: root.refresh()
    }

    Component.onCompleted: refresh()

    horizontalBarPill: Component {
        DankIcon {
            name: "battery_saver"
            size: root.iconSize
            color: root.limited ? Theme.primary : Theme.surfaceText
            opacity: root.limited ? 1.0 : 0.6
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    verticalBarPill: Component {
        DankIcon {
            name: "battery_saver"
            size: root.iconSize
            color: root.limited ? Theme.primary : Theme.surfaceText
            opacity: root.limited ? 1.0 : 0.6
        }
    }

    popoutWidth: 320

    popoutContent: Component {
        PopoutComponent {
            id: popout

            headerText: "Battery charge limit"
            detailsText: root.limited
                ? "Charging stops at " + root.healthLimit + "% to preserve battery health"
                : "Charging to 100% for maximum runtime"
            showCloseButton: true

            Connections {
                target: popout.parentPopout

                function onShouldBeVisibleChanged() {
                    if (popout.parentPopout && popout.parentPopout.shouldBeVisible)
                        root.refresh();
                }
            }

            Column {
                width: parent.width
                spacing: Theme.spacingM

                DankToggle {
                    width: parent.width
                    text: "Limit charge to " + root.healthLimit + "%"
                    description: "Best while docked. Turn off before unplugging so it charges fully."
                    checked: root.limited
                    enabled: !root.busy
                    onToggled: checked => root.setLimited(checked)
                }

                StyledRect {
                    width: parent.width
                    height: statusRow.implicitHeight + Theme.spacingM * 2
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainerHigh

                    Row {
                        id: statusRow

                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: Theme.spacingM
                        anchors.rightMargin: Theme.spacingM
                        anchors.verticalCenter: parent.verticalCenter

                        StyledText {
                            text: "Current limit"
                            font.pixelSize: Theme.fontSizeMedium
                            color: Theme.surfaceVariantText
                            width: parent.width - valueText.width
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledText {
                            id: valueText

                            text: root.limit + "%"
                            font.pixelSize: Theme.fontSizeLarge
                            font.weight: Font.Bold
                            color: root.limited ? Theme.primary : Theme.surfaceText
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }
            }
        }
    }
}
