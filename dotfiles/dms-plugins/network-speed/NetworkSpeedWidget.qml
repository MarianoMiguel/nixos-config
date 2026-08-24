import QtQuick
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    layerNamespacePlugin: "network-speed"

    readonly property string speedtestPath: "/run/current-system/sw/bin/mariano-network-speedtest"
    property var result: null
    property string testError: ""
    property bool cancelling: false

    readonly property bool testing: speedProcess.running
    readonly property string pillLabel: result ? formatCompactSpeed(result.downloadMbps) : ""
    readonly property color pillColor: testing ? Theme.primary : (testError !== "" ? Theme.error : Theme.surfaceText)

    function formatSpeed(value) {
        const numeric = Number(value);
        if (!isFinite(numeric))
            return "—";
        if (numeric >= 100)
            return numeric.toFixed(0);
        if (numeric >= 10)
            return numeric.toFixed(1);
        return numeric.toFixed(2);
    }

    function formatCompactSpeed(value) {
        return formatSpeed(value) + " Mb/s";
    }

    function formatTestTime(value) {
        const tested = new Date(value);
        if (isNaN(tested.getTime()))
            return "just now";
        return Qt.formatDateTime(tested, "HH:mm");
    }

    function runTest() {
        if (speedProcess.running)
            return;
        testError = "";
        cancelling = false;
        speedProcess.command = [speedtestPath, "run"];
        speedProcess.running = true;
    }

    function cancelTest() {
        if (!speedProcess.running)
            return;
        cancelling = true;
        speedProcess.running = false;
        testError = "Test cancelled.";
    }

    function activateTestAction() {
        if (testing)
            cancelTest();
        else
            runTest();
    }

    function isActivationKey(event) {
        return event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space;
    }

    Process {
        id: speedProcess

        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                if (root.cancelling || !text.trim())
                    return;
                try {
                    const parsed = JSON.parse(text.trim());
                    if (parsed.version !== 1)
                        throw new Error("unsupported result");
                    root.result = parsed;
                    root.testError = "";
                } catch (error) {
                    root.testError = "The speed test returned an invalid result.";
                }
            }
        }

        stderr: StdioCollector {
            id: speedError
        }

        onExited: exitCode => {
            if (root.cancelling)
                return;
            if (exitCode !== 0) {
                const detail = speedError.text.trim();
                root.testError = detail ? detail.split("\n")[0] : "The speed test could not reach a server.";
            }
        }
    }

    Component.onDestruction: cancelTest()

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS

            DankIcon {
                name: root.testing ? "sync" : "speed"
                size: root.iconSize
                color: root.pillColor
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                text: root.pillLabel
                visible: text !== ""
                color: root.pillColor
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.Medium
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    verticalBarPill: Component {
        DankIcon {
            name: root.testing ? "sync" : "speed"
            size: root.iconSize
            color: root.pillColor
        }
    }

    popoutWidth: 420

    popoutContent: Component {
        PopoutComponent {
            id: popout

            headerText: "Network speed"
            detailsText: "On-demand HTTPS test · no share link or result telemetry"
            showCloseButton: true

            Connections {
                target: popout.parentPopout

                function onShouldBeVisibleChanged() {
                    if (popout.parentPopout && !popout.parentPopout.shouldBeVisible)
                        root.cancelTest();
                }
            }

            Column {
                width: parent.width
                spacing: Theme.spacingM

                StyledRect {
                    width: parent.width
                    height: runningRow.implicitHeight + Theme.spacingL * 2
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainerHigh
                    visible: root.testing

                    Row {
                        id: runningRow

                        anchors.centerIn: parent
                        spacing: Theme.spacingM

                        DankSpinner {
                            size: 28
                            running: root.testing
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Column {
                            spacing: Theme.spacingXS

                            StyledText {
                                text: "Testing your connection…"
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.DemiBold
                                color: Theme.surfaceText
                            }

                            StyledText {
                                text: "Usually finishes in about 20 seconds"
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                            }
                        }
                    }
                }

                Row {
                    width: parent.width
                    spacing: Theme.spacingS
                    visible: root.result !== null && !root.testing

                    Repeater {
                        model: root.result ? [
                            { "icon": "download", "label": "Download", "value": root.formatSpeed(root.result.downloadMbps) },
                            { "icon": "upload", "label": "Upload", "value": root.formatSpeed(root.result.uploadMbps) }
                        ] : []

                        StyledRect {
                            required property var modelData

                            width: (popout.width - Theme.spacingS) / 2
                            height: metricColumn.implicitHeight + Theme.spacingL * 2
                            radius: Theme.cornerRadius
                            color: Theme.surfaceContainerHigh

                            Column {
                                id: metricColumn

                                anchors.centerIn: parent
                                spacing: Theme.spacingXS

                                DankIcon {
                                    name: modelData.icon
                                    size: Theme.iconSizeLarge
                                    color: Theme.primary
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }

                                StyledText {
                                    text: modelData.value
                                    font.pixelSize: Theme.fontSizeXLarge
                                    font.weight: Font.Bold
                                    color: Theme.surfaceText
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }

                                StyledText {
                                    text: modelData.label + " · Mbps"
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }
                            }
                        }
                    }
                }

                StyledRect {
                    width: parent.width
                    height: latencyRow.implicitHeight + Theme.spacingM * 2
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainerHigh
                    visible: root.result !== null && !root.testing

                    Row {
                        id: latencyRow

                        anchors.centerIn: parent
                        spacing: Theme.spacingXL

                        StyledText {
                            text: root.result ? "Ping  " + root.formatSpeed(root.result.pingMs) + " ms" : ""
                            font.pixelSize: Theme.fontSizeMedium
                            color: Theme.surfaceText
                        }

                        StyledText {
                            text: root.result ? "Jitter  " + root.formatSpeed(root.result.jitterMs) + " ms" : ""
                            font.pixelSize: Theme.fontSizeMedium
                            color: Theme.surfaceText
                        }
                    }
                }

                StyledText {
                    width: parent.width
                    visible: root.result !== null && !root.testing
                    text: root.result ? root.result.server + " · tested at " + root.formatTestTime(root.result.testedAt) : ""
                    textFormat: Text.PlainText
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }

                StyledText {
                    width: parent.width
                    visible: root.result === null && !root.testing && root.testError === ""
                    text: "No background checks. Run a short test when you need a real measurement."
                    font.pixelSize: Theme.fontSizeMedium
                    color: Theme.surfaceVariantText
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                }

                StyledText {
                    width: parent.width
                    visible: root.testError !== "" && !root.testing
                    text: root.testError
                    textFormat: Text.PlainText
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.error
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                }

                DankButton {
                    id: speedActionButton

                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.testing ? "Cancel test" : (root.result ? "Run again" : "Run speed test")
                    iconName: root.testing ? "close" : "play_arrow"
                    backgroundColor: root.testing ? Theme.buttonBg : Theme.primary
                    textColor: root.testing ? Theme.buttonText : Theme.onPrimary
                    activeFocusOnTab: true
                    Accessible.role: Accessible.Button
                    Accessible.name: text
                    onClicked: {
                        forceActiveFocus();
                        root.activateTestAction();
                    }
                    Keys.onPressed: event => {
                        if (root.isActivationKey(event)) {
                            root.activateTestAction();
                            event.accepted = true;
                        }
                    }

                    StyledRect {
                        anchors.fill: parent
                        z: 10
                        radius: parent.radius
                        color: "transparent"
                        border.width: parent.activeFocus ? 2 : 0
                        border.color: Theme.primary
                    }
                }
            }
        }
    }
}
