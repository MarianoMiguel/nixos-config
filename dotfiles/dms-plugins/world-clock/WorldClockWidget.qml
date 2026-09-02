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
        { label: "Campana", short: "CPA", detail: "Buenos Aires · Argentina", zone: "America/Argentina/Buenos_Aires" },
        { label: "New York", short: "NY", detail: "United States", zone: "America/New_York" },
        { label: "Los Angeles", short: "LA", detail: "United States", zone: "America/Los_Angeles" },
        { label: "Sydney", short: "SYD", detail: "Australia", zone: "Australia/Sydney" }
    ]
    // One entry per place: { time, day, hour, offsetMinutes }. Offsets are
    // relative to the first place, the home zone.
    property var times: []

    // The bar shows one away place while it is inside business hours
    // (09:00 to 18:00 local), in list order: New York through the morning,
    // Sydney in the evening. Outside those hours the pill is just the globe.
    readonly property var awayNow: {
        for (let i = 1; i < root.places.length; i++) {
            const entry = root.times[i];
            if (entry && entry.hour >= 9 && entry.hour < 18)
                return { short: root.places[i].short, time: entry.time };
        }
        return null;
    }

    function offsetLabel(minutes) {
        if (minutes === 0)
            return "same time";
        const sign = minutes > 0 ? "+" : "−";
        const abs = Math.abs(minutes);
        const hours = Math.floor(abs / 60);
        const rest = abs % 60;
        return sign + hours + (rest === 0 ? "" : ":" + (rest < 10 ? "0" : "") + rest) + " h";
    }

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
            + "; do LC_ALL=C TZ=\"$tz\" date '+%H:%M%t%a%t%z'; done"]

        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n");
                if (lines.length !== root.places.length)
                    return;
                const zoneMinutes = value => {
                    // %z is ±HHMM.
                    const sign = value.startsWith("-") ? -1 : 1;
                    return sign * (parseInt(value.substr(1, 2), 10) * 60 + parseInt(value.substr(3, 2), 10));
                };
                const homeMinutes = zoneMinutes(lines[0].split("\t")[2] || "+0000");
                root.times = lines.map(line => {
                    const parts = line.split("\t");
                    return {
                        time: parts[0] || "--:--",
                        day: parts[1] || "",
                        hour: parseInt((parts[0] || "0").substr(0, 2), 10),
                        offsetMinutes: zoneMinutes(parts[2] || "+0000") - homeMinutes
                    };
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

            StyledText {
                text: root.awayNow ? root.awayNow.short + " " + root.awayNow.time : ""
                visible: text !== ""
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.Medium
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
            detailsText: "Offsets are relative to Campana"
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
                                text: modelData.detail + (index === 0 || entry.offsetMinutes === undefined
                                    ? "" : " · " + root.offsetLabel(entry.offsetMinutes))
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
