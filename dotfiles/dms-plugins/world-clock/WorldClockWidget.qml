import QtQuick
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    layerNamespacePlugin: "world-clock"

    // QML's Date cannot resolve arbitrary time zones, so `date +%z` provides
    // each zone's current UTC offset (DST included) and every displayed clock
    // is derived from one UTC instant plus that offset. Campana shares
    // Argentina's single Buenos Aires zone and is the home reference.
    readonly property var places: [
        { label: "Campana", detail: "Buenos Aires · Argentina", zone: "America/Argentina/Buenos_Aires" },
        { label: "New York", detail: "United States", zone: "America/New_York" },
        { label: "Los Angeles", detail: "United States", zone: "America/Los_Angeles" },
        { label: "Sydney", detail: "Australia", zone: "Australia/Sydney" }
    ]
    // One UTC-offset in minutes per place, in the same order.
    property var offsets: []
    // The real instant the offsets were sampled, in ms since the epoch.
    property double baseUtc: 0
    // How far the popout slider has shifted the clocks, in minutes from now.
    property int scrubMinutes: 0

    function refresh() {
        if (!clockProcess.running)
            clockProcess.running = true;
    }

    function msUntilNextMinute() {
        const now = new Date();
        return 60000 - now.getSeconds() * 1000 - now.getMilliseconds() + 250;
    }

    // Wall clock for place `i` at the current scrub, read off the shared UTC
    // instant. Returns the HH:MM string and a ±Nd badge when the scrubbed date
    // differs from Campana's.
    function cell(i) {
        if (i >= root.offsets.length)
            return { time: "--:--", badge: "" };
        const ms = root.baseUtc + (root.scrubMinutes + root.offsets[i]) * 60000;
        const d = new Date(ms);
        const hh = ("0" + d.getUTCHours()).slice(-2);
        const mm = ("0" + d.getUTCMinutes()).slice(-2);
        const homeMs = root.baseUtc + (root.scrubMinutes + root.offsets[0]) * 60000;
        const dayDelta = Math.floor(ms / 86400000) - Math.floor(homeMs / 86400000);
        const badge = dayDelta > 0 ? "+" + dayDelta + "d" : (dayDelta < 0 ? dayDelta + "d" : "");
        return { time: hh + ":" + mm, badge: badge };
    }

    function offsetLabel(i) {
        if (i === 0 || i >= root.offsets.length)
            return "";
        const minutes = root.offsets[i] - root.offsets[0];
        if (minutes === 0)
            return "same time";
        const sign = minutes > 0 ? "+" : "−";
        const abs = Math.abs(minutes);
        const hours = Math.floor(abs / 60);
        const rest = abs % 60;
        return sign + hours + (rest === 0 ? "" : ":" + (rest < 10 ? "0" : "") + rest) + " h";
    }

    function scrubLabel() {
        if (root.scrubMinutes === 0)
            return "Now in Campana";
        const sign = root.scrubMinutes > 0 ? "+" : "−";
        const abs = Math.abs(root.scrubMinutes);
        const hours = Math.floor(abs / 60);
        const rest = abs % 60;
        return "Campana " + sign + hours + ":" + (rest < 10 ? "0" : "") + rest;
    }

    Process {
        id: clockProcess

        running: false
        // %z is ±HHMM; one line per zone in `places` order.
        command: ["/bin/sh", "-c",
            "for tz in " + root.places.map(p => p.zone).join(" ")
            + "; do TZ=\"$tz\" date '+%z'; done"]

        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n");
                if (lines.length !== root.places.length)
                    return;
                root.offsets = lines.map(value => {
                    const sign = value.trim().startsWith("-") ? -1 : 1;
                    const v = value.trim();
                    return sign * (parseInt(v.substr(1, 2), 10) * 60 + parseInt(v.substr(3, 2), 10));
                });
                root.baseUtc = Date.now();
            }
        }
    }

    // Keep "now" current at each minute boundary. Scrub is an offset from now,
    // so live ticking and a held scrub coexist. The popout also refreshes on
    // open so a post-suspend view is never stale.
    Timer {
        interval: root.msUntilNextMinute()
        repeat: true
        running: true
        onTriggered: {
            root.refresh();
            interval = root.msUntilNextMinute();
        }
    }

    Component.onCompleted: refresh()

    horizontalBarPill: Component {
        DankIcon {
            name: "public"
            size: root.iconSize
            color: Theme.surfaceText
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    verticalBarPill: Component {
        DankIcon {
            name: "public"
            size: root.iconSize
            color: Theme.surfaceText
        }
    }

    popoutWidth: 360

    popoutContent: Component {
        PopoutComponent {
            id: popout

            headerText: "World clock"
            detailsText: "Drag the slider to compare a time across places"
            showCloseButton: true

            Connections {
                target: popout.parentPopout

                function onShouldBeVisibleChanged() {
                    if (popout.parentPopout && popout.parentPopout.shouldBeVisible) {
                        root.scrubMinutes = 0;
                        root.refresh();
                    }
                }
            }

            Column {
                width: parent.width
                spacing: Theme.spacingM

                // Scrubber: a ±12 h slider around now, snapped to 15 minutes.
                StyledRect {
                    width: parent.width
                    height: scrubberColumn.implicitHeight + Theme.spacingM * 2
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainerHigh

                    Column {
                        id: scrubberColumn

                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: Theme.spacingM
                        anchors.rightMargin: Theme.spacingM
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.spacingS

                        Row {
                            width: parent.width

                            StyledText {
                                text: root.scrubLabel()
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: Font.DemiBold
                                color: Theme.surfaceText
                                width: parent.width - resetButton.width
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            StyledText {
                                id: resetButton

                                text: "Now"
                                visible: root.scrubMinutes !== 0
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: Font.Bold
                                color: Theme.primary
                                anchors.verticalCenter: parent.verticalCenter

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.scrubMinutes = 0
                                }
                            }
                        }

                        Item {
                            id: slider

                            width: parent.width
                            height: 22

                            readonly property int handleSize: 18
                            readonly property real span: width - handleSize
                            // −720..+720 minutes maps across the track.
                            readonly property real fraction: (root.scrubMinutes + 720) / 1440

                            StyledRect {
                                id: track
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width
                                height: 6
                                radius: 3
                                color: Theme.surfaceVariantText
                                opacity: 0.35
                            }

                            StyledRect {
                                anchors.verticalCenter: parent.verticalCenter
                                height: 6
                                radius: 3
                                color: Theme.primary
                                x: Math.min(slider.width / 2, handle.x + slider.handleSize / 2)
                                width: Math.abs(handle.x + slider.handleSize / 2 - slider.width / 2)
                            }

                            StyledRect {
                                id: handle
                                width: slider.handleSize
                                height: slider.handleSize
                                radius: slider.handleSize / 2
                                color: Theme.primary
                                anchors.verticalCenter: parent.verticalCenter
                                x: slider.fraction * slider.span
                            }

                            MouseArea {
                                anchors.fill: parent
                                preventStealing: true

                                function apply(px) {
                                    const frac = Math.max(0, Math.min(1, (px - slider.handleSize / 2) / slider.span));
                                    root.scrubMinutes = Math.round((frac * 1440 - 720) / 15) * 15;
                                }

                                onPressed: mouse => apply(mouse.x)
                                onPositionChanged: mouse => apply(mouse.x)
                            }
                        }
                    }
                }

                Repeater {
                    model: root.places

                    StyledRect {
                        required property var modelData
                        required property int index

                        readonly property var view: {
                            root.baseUtc;
                            root.scrubMinutes;
                            root.offsets;
                            return root.cell(index);
                        }

                        width: parent.width
                        height: placeColumn.implicitHeight + Theme.spacingM * 2
                        radius: Theme.cornerRadius
                        color: index === 0 ? Theme.primary : Theme.surfaceContainerHigh
                        opacity: index === 0 ? 0.18 : 1

                        Column {
                            id: placeColumn

                            anchors.left: parent.left
                            anchors.leftMargin: Theme.spacingM
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 0

                            StyledText {
                                text: modelData.label
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.DemiBold
                                color: Theme.surfaceText
                            }

                            StyledText {
                                text: modelData.detail + (root.offsetLabel(index) === ""
                                    ? "" : " · " + root.offsetLabel(index))
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                            }
                        }

                        Row {
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.spacingM
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.spacingS

                            StyledText {
                                text: parent.parent.view.badge
                                visible: text !== ""
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            StyledText {
                                text: parent.parent.view.time
                                font.pixelSize: Theme.fontSizeXLarge
                                font.weight: Font.Bold
                                color: Theme.surfaceText
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }
                }
            }
        }
    }
}
