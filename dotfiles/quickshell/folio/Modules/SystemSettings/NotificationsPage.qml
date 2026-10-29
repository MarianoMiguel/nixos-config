import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import qs.Widgets

// Notifications: when they may interrupt (Do not disturb, a focus session,
// a daily schedule, urgent ones let through), what each app's do, and the
// history. Everything goes through Notifs, which applies it; a fixture
// (IPC notifications fixture normal|stress|empty) shows test data instead.
SettingsPage {
    id: page
    title: "Notifications"
    description: "What may interrupt you, and when. Held notifications wait quietly in the sidebar."

    readonly property var view: Notifs.view
    readonly property var schedule: view.schedule || { "on": false, "from": 1320, "to": 420 }
    readonly property bool scheduledNow: Notifs.inWindow(schedule, Notifs.minute)
    function hm(m) { return String(Math.floor(m / 60)).padStart(2, "0") + ":" + String(m % 60).padStart(2, "0"); }
    function clock(t) { return Qt.formatTime(new Date(t), "HH:mm"); }
    function many(n) { return n > 999 ? "999+" : String(n); }

    readonly property string dndHint: Notifs.dndOn ? "On until you turn it off. Nothing peeks or plays."
        : Notifs.focusOn ? "A focus session is holding notifications until " + clock(Notifs.focusEnds) + "."
        : scheduledNow ? "Quiet hours are holding notifications until " + hm(schedule.to) + "."
        : "Off. Notifications peek from the island as they arrive."
    readonly property string scheduleHint: {
        if (schedule.from === schedule.to) return "Pick two different times.";
        const span = "Every day from " + hm(schedule.from) + " to " + hm(schedule.to) + (schedule.to < schedule.from ? " the next day" : "");
        return schedule.on && scheduledNow ? span + " · quiet now" : span + ".";
    }

    // ------------------------------------------------------------ quiet
    Section {
        title: "Do not disturb"
        hint: "While it is on, notifications skip the island and make no sound; they still collect in the sidebar."
        Component.onCompleted: page.mark("dnd", this)
    }
    Card {
        divided: true
        SettingRow {
            icon: "moon"; label: "Do not disturb"; hint: page.dndHint
            Toggle { checked: Notifs.dndOn; onToggled: v => Notifs.setDnd(v) }
        }
        SettingRow {
            icon: "cup"; label: "Focus session"
            hint: Notifs.focusOn ? "Until " + page.clock(Notifs.focusEnds) + ", then everything comes back." : "Deep work for a while; it ends on its own."
            RowLayout {
                spacing: 8
                Button { visible: !Notifs.focusOn; text: "25 min"; onClicked: Notifs.startFocus(25) }
                Button { visible: !Notifs.focusOn; text: "50 min"; onClicked: Notifs.startFocus(50) }
                Button { visible: Notifs.focusOn; text: "End now"; onClicked: Notifs.stopFocus() }
            }
        }
        SettingRow {
            icon: "calendar"; label: "On a schedule"; hint: page.scheduleHint
            Toggle { checked: !!page.schedule.on; onToggled: v => Notifs.setSchedule({ "on": v }) }
        }
        SettingRow {
            icon: "sun"; label: "Quiet hours"
            hint: page.schedule.on ? "Quarter-hour steps; hold − or + to move faster." : "Used while the schedule is on."
            RowLayout {
                spacing: 8
                opacity: page.schedule.on ? 1 : 0.55
                Label { text: "From"; color: Theme.text2; font.pixelSize: Theme.fsS }
                NotifyTime { value: page.schedule.from; onMoved: v => Notifs.setSchedule({ "from": v }) }
                Label { text: "to"; color: Theme.text2; font.pixelSize: Theme.fsS }
                NotifyTime { value: page.schedule.to; onMoved: v => Notifs.setSchedule({ "to": v }) }
            }
        }
        SettingRow {
            icon: "bolt"; label: "Let urgent notifications through"
            hint: "Critical ones, like a battery about to run out, still peek and play while it is quiet."
            Toggle { checked: page.view.critical !== false; onToggled: v => Notifs.setCritical(v) }
        }
    }

    // ------------------------------------------------------------ lock screen
    Section { title: "Lock screen"; Component.onCompleted: page.mark("lock", this) }
    Notice {
        icon: "lock"
        text: "The lock screen shows no notifications, so nothing previews while it is locked."
    }

    // ------------------------------------------------------------ apps
    Section {
        title: "Apps"
        hint: Notifs.apps.length ? Notifs.apps.length + " apps have sent notifications. Open one for its banners and sound; off drops them without a trace." : ""
        Component.onCompleted: page.mark("apps", this)
    }
    Card {
        visible: Notifs.apps.length > 0
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            Repeater {
                model: Notifs.apps
                NotifyAppRow {
                    required property var modelData
                    required property int index
                    app: modelData
                    first: index === 0
                    expanded: Notifs.openApp === modelData.key
                    onToggled: Notifs.openApp = expanded ? "" : modelData.key
                    onChanged: (field, value) => Notifs.setApp(modelData.key, field, value)
                }
            }
        }
    }
    Notice {
        visible: Notifs.apps.length === 0
        icon: "bell"
        text: "No app has sent a notification yet. Each one appears here after its first, with switches for banners and sound."
    }

    // ------------------------------------------------------------ history
    Section { title: "History"; Component.onCompleted: page.mark("history", this) }
    Card {
        SettingRow {
            icon: "bell"; label: "Clear notifications"
            hint: Notifs.waiting + Notifs.recent === 0 ? "Nothing waiting and nothing from the last day."
                : page.many(Notifs.waiting) + " waiting in the sidebar · " + page.many(Notifs.recent) + " from the last day"
            Button {
                text: "Clear"; icon: "close"
                enabled: Notifs.waiting + Notifs.recent > 0
                onClicked: Notifs.clearHistory()
            }
        }
    }
}
