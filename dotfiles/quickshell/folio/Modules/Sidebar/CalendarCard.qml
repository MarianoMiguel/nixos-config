import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Widgets

// This month, Monday first, today in an ink circle and a dot under days
// with events; under it the next event. Without a calendar source it says
// so instead of inventing events.
SideCard {
    id: root
    required property var feed

    readonly property date now: new Date(feed.now)
    readonly property string todayKey: key(now)
    readonly property var days: {
        const y = now.getFullYear(), m = now.getMonth();
        const first = (new Date(y, m, 1).getDay() + 6) % 7, count = new Date(y, m + 1, 0).getDate();
        const out = [];
        for (let i = 0; i < 42; i++) {
            const d = new Date(y, m, 1 - first + i);
            if (i >= 35 && d.getMonth() !== m) break;
            out.push({ "n": d.getDate(), "out": d.getMonth() !== m, "key": key(d) });
        }
        return out;
    }
    readonly property var marked: { const s = {}; for (const e of feed.events) s[e.date] = true; return s; }
    readonly property var today: feed.events.filter(e => e.date === todayKey)
    readonly property var next: feed.events.find(e => e.allDay ? e.date >= todayKey : endOf(e) > feed.now) || null

    function key(d) { return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0"); }
    function minutes(t) { const m = /(\d{1,2})[:.](\d{2})\s*([AaPp])?/.exec(t || ""); if (!m) return 0; let h = Number(m[1]) % (m[3] ? 12 : 24); if (m[3] && m[3].toLowerCase() === "p") h += 12; return h * 60 + Number(m[2]); }
    function endOf(e) {
        let len = minutes(e.end) - minutes(e.start);
        if (len <= 0) len += 1440;
        return e.at + len * 60000;
    }
    function when(e) {
        if (e.allDay) return e.date === todayKey ? "today" : weekday(e.at);
        if (e.at <= feed.now) return "now";
        const min = Math.round((e.at - feed.now) / 60000);
        if (min < 60) return "in " + min + "m";
        if (e.date === todayKey) return "in " + Math.round(min / 60) + "h";
        const tomorrow = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1);
        return e.date === key(tomorrow) ? "tomorrow" : weekday(e.at);
    }
    function weekday(ms) { return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][new Date(ms).getDay()]; }

    implicitHeight: col.implicitHeight + 22

    ColumnLayout {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 14; rightMargin: 14; topMargin: 12 }
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            Cap { text: root.now.toLocaleDateString(Qt.locale("es_AR"), "MMMM 'de' yyyy"); Layout.fillWidth: true; Layout.minimumWidth: 0 }
            Cap {
                visible: root.feed.calConnected
                text: root.today.length === 0 ? "Nothing today" : root.today.length === 1 ? "1 event" : root.today.length + " events"
            }
        }

        GridLayout {
            Layout.fillWidth: true
            Layout.topMargin: 8
            columns: 7
            columnSpacing: 0
            rowSpacing: 2
            uniformCellWidths: true

            Repeater {
                model: ["L", "M", "M", "J", "V", "S", "D"]
                Text {
                    required property string modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: 20
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: modelData
                    color: Theme.text3
                    font.family: Theme.mono
                    font.pixelSize: Theme.fsCap - 0.5
                    font.weight: Font.Medium
                }
            }
            Repeater {
                model: root.days
                Item {
                    id: cell
                    required property var modelData
                    readonly property bool today: modelData.key === root.todayKey
                    Layout.fillWidth: true
                    Layout.preferredHeight: 28
                    Rectangle {
                        visible: cell.today
                        anchors.centerIn: parent
                        width: 28; height: 28; radius: 14
                        color: Theme.ink
                    }
                    Text {
                        anchors.centerIn: parent
                        text: cell.modelData.n
                        color: cell.today ? Theme.inkText : cell.modelData.out ? Theme.text3 : Theme.text
                        font.family: Theme.ui
                        font.pixelSize: Theme.fsS
                        font.weight: cell.today ? Font.DemiBold : Font.Normal
                        font.features: ({ "tnum": 1 })
                    }
                    Rectangle {
                        visible: !!root.marked[cell.modelData.key]
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 2
                        width: 3; height: 3; radius: 1.5
                        color: cell.today ? Theme.inkText : Theme.ink
                    }
                }
            }
        }

        // The next event
        RowLayout {
            visible: root.next !== null
            Layout.fillWidth: true
            Layout.topMargin: 8
            Layout.leftMargin: 2
            Layout.rightMargin: 2
            spacing: 10
            Rectangle { implicitWidth: 3; implicitHeight: 30; radius: 1.5; color: Theme.ink }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 0
                Label { text: root.next ? root.next.title : ""; font.weight: Font.DemiBold; Layout.fillWidth: true; Layout.minimumWidth: 0 }
                Label {
                    text: !root.next ? "" : (root.next.allDay ? "All day" : root.next.start + " – " + root.next.end) + (root.next.location ? " · " + root.next.location : "")
                    color: Theme.text2
                    font.pixelSize: Theme.fsS
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                }
            }
            Cap { text: root.next ? root.when(root.next) : "" }
        }

        // No source
        RowLayout {
            visible: !root.feed.calConnected
            Layout.fillWidth: true
            Layout.topMargin: 8
            Layout.leftMargin: 2
            spacing: 8
            Icon { name: "calendar"; size: 15; color: Theme.text3 }
            Label { text: "No calendar connected"; color: Theme.text2; font.pixelSize: Theme.fsS; Layout.fillWidth: true; Layout.minimumWidth: 0 }
        }
    }
}
