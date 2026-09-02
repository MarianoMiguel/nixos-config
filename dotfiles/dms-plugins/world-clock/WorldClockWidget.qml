import QtQuick
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    layerNamespacePlugin: "world-clock"

    // The QML JS engine has no timezone database, so a `date` loop over TZ
    // values does the conversions. Campana shares Argentina's single
    // Buenos Aires zone.
    readonly property var places: [
        { label: "Campana", detail: "Buenos Aires · Argentina", zone: "America/Argentina/Buenos_Aires" },
        { label: "New York", detail: "United States", zone: "America/New_York" },
        { label: "Los Angeles", detail: "United States", zone: "America/Los_Angeles" },
        { label: "Sydney", detail: "Australia", zone: "Australia/Sydney" }
    ]
    property var times: []

    function refresh() {
        if (!clockProcess.running)
            clockProcess.running = true;
    }

    function msUntilNextMinute() {
        const now = new Date();
        return 60000 - now.getSeconds() * 1000 - now.getMilliseconds() + 250;
    }

    Process {
        id: clockProcess

        running: false
        // %t is strftime's tab; LC_ALL=C keeps the weekday names stable for
        // the day-difference display regardless of session locale.
        command: ["/bin/sh", "-c",
            "for tz in " + root.places.map(p => p.zone).join(" ")
            + "; do LC_ALL=C TZ=\"$tz\" date '+%H:%M%t%a'; done"]

        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n");
                if (lines.length !== root.places.length)
                    return;
                root.times = lines.map(line => {
                    const parts = line.split("\t");
                    return { time: parts[0] || "--:--", day: parts[1] || "" };
                });
            }
        }
    }

    // Re-run on each minute boundary; the popout also refreshes on open so a
    // stale post-suspend timer never shows old times to the user.
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
        Row {
            spacing: Theme.spacingXS

            DankIcon {
                name: "public"
                size: root.iconSize
                color: Theme.surfaceText
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    verticalBarPill: Component {
        DankIcon {
            name: "public"
            size: root.iconSize
            color: Theme.surfaceText
        }
    }

    popoutWidth: 340

    popoutContent: Component {
        PopoutComponent {
            id: popout

            headerText: "World clock"
            detailsText: "Local weekday shown next to each time"
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
                spacing: Theme.spacingS

                Repeater {
                    model: root.places

                    StyledRect {
                        required property var modelData
                        required property int index

                        readonly property var entry: root.times[index] || {}

                        width: parent.width
                        height: placeColumn.implicitHeight + Theme.spacingM * 2
                        radius: Theme.cornerRadius
                        color: Theme.surfaceContainerHigh

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
                                text: modelData.detail
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
                                text: entry.day || ""
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            StyledText {
                                text: entry.time || "--:--"
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
