import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.Common
import qs.Widgets

// World clock: one row per city (Settings "world.cities", the first is
// home): name, how far it is from home ("Tomorrow, +14 h", "+8 h 45 m"), a
// sky strip whose dots thicken at night with the sun at the hour, and the
// time. QML has no time zones, so `date` reports each zone's UTC offset; it
// is asked again every ten minutes, which catches daylight-saving changes.
SideCard {
    id: root
    required property var feed
    readonly property var cities: feed.cities
    readonly property string zones: cities.map(c => c[1]).join(" ")
    property var offsets: ({})         // zone -> minutes east of UTC

    implicitHeight: col.implicitHeight + 12

    Process {
        id: probe
        command: ["sh", "-c", "for z in \"$@\"; do echo \"$z $(TZ=\"$z\" date +%z)\"; done", "sh"].concat(root.cities.map(c => c[1]))
        stdout: StdioCollector {
            onStreamFinished: {
                const o = {};
                for (const l of text.split("\n")) {
                    const m = /^(\S+) ([+-])(\d\d)(\d\d)$/.exec(l.trim());
                    if (m) o[m[1]] = (m[2] === "-" ? -1 : 1) * (Number(m[3]) * 60 + Number(m[4]));
                }
                root.offsets = o;
            }
        }
    }
    onZonesChanged: probe.running = true
    Component.onCompleted: probe.running = true
    Timer { interval: 600000; running: true; repeat: true; onTriggered: probe.running = true }

    function ymd(ms) { const d = new Date(ms); return d.getUTCFullYear() * 10000 + d.getUTCMonth() * 100 + d.getUTCDate(); }
    function label(i, zone) {
        if (i === 0) return "Home";
        const home = offsets[cities[0][1]], off = offsets[zone];
        if (home === undefined || off === undefined) return "";
        const diff = off - home;
        const a = ymd(feed.now + off * 60000), b = ymd(feed.now + home * 60000);
        const day = a === b ? "Today" : a > b ? "Tomorrow" : "Yesterday";
        if (diff === 0) return day + ", same time";
        const h = Math.floor(Math.abs(diff) / 60), m = Math.abs(diff) % 60;
        return day + ", " + (diff > 0 ? "+" : "−") + (h ? h + " h" : "") + (h && m ? " " : "") + (m ? m + " m" : "");
    }

    ColumnLayout {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 14; rightMargin: 14; topMargin: 6 }
        spacing: 0

        Repeater {
            model: root.cities
            Item {
                id: city
                required property var modelData
                required property int index
                readonly property bool known: root.offsets[modelData[1]] !== undefined
                readonly property real local: root.feed.now + (root.offsets[modelData[1]] || 0) * 60000
                readonly property real hour: { const d = new Date(local); return d.getUTCHours() + d.getUTCMinutes() / 60; }
                Layout.fillWidth: true
                implicitHeight: 46

                Rectangle { visible: city.index > 0; width: parent.width; height: 1; color: Theme.rule }
                RowLayout {
                    anchors.fill: parent
                    spacing: 12
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        spacing: 0
                        Label { text: city.modelData[0]; font.weight: Font.DemiBold; Layout.fillWidth: true; Layout.minimumWidth: 0 }
                        Label { text: root.label(city.index, city.modelData[1]); visible: text !== ""; color: Theme.text2; font.pixelSize: Theme.fsS - 1; Layout.fillWidth: true; Layout.minimumWidth: 0 }
                    }
                    Sky { visible: city.known; hour: city.hour; Layout.preferredWidth: 88; Layout.preferredHeight: 22 }
                    Label {
                        Layout.preferredWidth: 56
                        horizontalAlignment: Text.AlignRight
                        text: city.known ? String(new Date(city.local).getUTCHours()).padStart(2, "0") + ":" + String(new Date(city.local).getUTCMinutes()).padStart(2, "0") : "–"
                        font.pixelSize: Theme.fsL
                        font.weight: Font.DemiBold
                        font.features: ({ "tnum": 1 })
                    }
                }
            }
        }
    }
}
