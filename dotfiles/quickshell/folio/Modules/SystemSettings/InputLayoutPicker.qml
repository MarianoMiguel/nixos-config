import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import qs.Common
import qs.Services
import qs.Widgets

// Adding a keyboard layout: a search over xkb's layouts and variants that
// opens inside the card on a spring. Layouts already in use are marked and
// cannot be added twice. Escape or a pick closes it.
Item {
    id: root
    property bool open: false
    property alias query: search.text
    signal picked(string id)
    Layout.fillWidth: true
    implicitHeight: open ? body.implicitHeight : 0
    opacity: open ? 1 : 0
    // Closed, its field and list leave the Tab order.
    visible: open || height > 0.5
    clip: true
    Behavior on implicitHeight { SpringPanel {} }
    Behavior on opacity { SpringSoft {} }
    // Where the keyboard goes back to when it closes with focus inside.
    property Item returnFocus: null
    onOpenChanged: {
        if (open) { Qt.callLater(search.focusNow); return; }
        if (returnFocus && KeyNav.inside(Window.activeFocusItem, root)) returnFocus.forceActiveFocus();
        search.text = "";
    }

    // Plain layouts before their variants, each alphabetical.
    readonly property var all: Input.catalog.layouts.slice().sort((a, b) => ((a.variant ? 1 : 0) - (b.variant ? 1 : 0)) || a.name.localeCompare(b.name))
    readonly property var used: Input.layouts.map(l => l.id)
    readonly property var matches: {
        const q = search.text.trim().toLowerCase();
        if (!q) return all;
        const hits = all.filter(l => l.name.toLowerCase().indexOf(q) >= 0 || l.id.toLowerCase().indexOf(q) >= 0);
        // Names that start with the words typed come first.
        return hits.filter(l => l.name.toLowerCase().indexOf(q) === 0).concat(hits.filter(l => l.name.toLowerCase().indexOf(q) !== 0));
    }

    ColumnLayout {
        id: body
        width: parent.width
        spacing: 8
        Rectangle { Layout.fillWidth: true; Layout.leftMargin: 14; Layout.rightMargin: 14; Layout.preferredHeight: 1; color: Theme.rule }
        RowLayout {
            Layout.fillWidth: true; Layout.leftMargin: 14; Layout.rightMargin: 14; spacing: 8
            Field {
                id: search
                Layout.fillWidth: true
                icon: "search"
                placeholder: "Search " + root.all.length + " layouts by language or country"
                onAccepted: { const m = root.matches.find(l => root.used.indexOf(l.id) < 0); if (m) root.picked(m.id); }
                onCancelled: root.open = false
            }
            Button { text: "Done"; onClicked: root.open = false }
        }
        Cap {
            Layout.fillWidth: true; Layout.leftMargin: 16
            text: root.matches.length === 0 ? "No layout matches “" + search.text + "”" : root.matches.length + (root.matches.length === 1 ? " layout" : " layouts")
        }
        ListView {
            id: list
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(6, root.matches.length) * 44
            Layout.bottomMargin: 6
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: root.matches
            reuseItems: true
            delegate: ListRow {
                required property var modelData
                readonly property bool taken: root.used.indexOf(modelData.id) >= 0
                width: list.width
                implicitHeight: 44
                icon: ""
                title: modelData.name
                subtitle: modelData.layout + (modelData.variant ? " · " + modelData.variant : "") + (taken ? " · already added" : "")
                dim: taken
                clickable: !taken
                onClicked: root.picked(modelData.id)
            }
        }
    }
}
