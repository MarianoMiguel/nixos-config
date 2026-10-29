import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets

// Network: Wi-Fi (on and off, the network in use and its details, networks
// in range with the saved ones first, joining with an inline password,
// hidden networks, forgetting with undo), Ethernet, and VPN (Tailscale and
// NetworkManager's own). Network.prompt, set by the sidebar or IPC, opens
// that network's password field. No airplane mode: on a laptop reached only
// over the network, one switch that cuts every radio is a trap.
SettingsPage {
    id: page
    title: "Network"
    description: "Wi-Fi, Ethernet and VPN. Saved networks join on their own when they are in range."

    // Which form is open, by network name, so list refreshes keep it.
    property string open: ""
    property bool hiddenOpen: false
    property string draft: ""
    readonly property bool editing: open !== "" || hiddenOpen
    function openForm(name) { draft = ""; hiddenOpen = false; open = name; }
    function openHidden() { draft = ""; open = ""; hiddenOpen = true; Network.clearError(); }
    function closeForm() { open = ""; hiddenOpen = false; draft = ""; Network.clearError(); }

    // The lists hold still while a form is open, so a refresh never moves it.
    property var shown: []
    Connections {
        target: Network
        function onNetworksChanged() { if (!page.editing) page.shown = Network.networks; }
        function onPromptChanged() { page.takePrompt(); }
        function onPromptHiddenChanged() { page.takePrompt(); }
        // A saved network whose password stopped working asks for the new one.
        function onJoinErrorChanged() {
            const e = Network.joinError;
            if (e.kind === "password" && !page.hiddenOpen && page.open !== e.ssid && page.shown.some(n => n.ssid === e.ssid && (n.kind === "psk" || n.kind === "sae"))) page.openForm(e.ssid);
        }
        function onJoiningChanged() { if (Network.joining === "" && !Network.joinError.ssid && page.editing) page.closeForm(); }
    }
    onEditingChanged: if (!editing) shown = Network.networks
    function takePrompt() {
        if (Network.prompt !== "") { const p = Network.prompt; Network.prompt = ""; openForm(p); Qt.callLater(() => page.scrollTo("join")); }
        if (Network.promptHidden) { Network.promptHidden = false; openHidden(); Qt.callLater(() => page.scrollTo("hidden")); }
    }
    Component.onCompleted: { Network.watch(); Tailscale.refresh(); shown = Network.networks; takePrompt(); }
    Component.onDestruction: Network.unwatch()

    readonly property bool wifiShownOn: Network.wifiOn && !Network.wifiLeaving
    readonly property var cur: Network.current
    readonly property var saved: shown.filter(n => n.known && !n.active && !Network.forgetting[n.uuid])
    readonly property var others: shown.filter(n => !n.known && !n.active)
    readonly property var far: Network.known.filter(k => !Network.forgetting[k.uuid] && !shown.some(n => n.ssid === k.ssid) && !(cur && cur.uuid === k.uuid))

    function bare(a) { return (a || "").replace(/\/\d+$/, ""); }
    function quality(s) { return s >= 75 ? "excellent" : s >= 50 ? "good" : s >= 25 ? "fair" : "weak"; }
    function line(n) {
        if (Network.joining === n.ssid) return "Joining…";
        const e = Network.joinError;
        if (e.ssid === n.ssid && e.kind !== "password") return e.text;
        return [n.known ? "Saved" : "", n.security, n.bands.join(" & ")].filter(x => x).join(" · ");
    }
    function choose(n) {
        Network.clearError();
        if (!Network.join(n.ssid, "")) openForm(n.ssid);
    }

    // ------------------------------------------------------------------ Wi-Fi

    Section { title: "Wi-Fi"; hint: "This laptop joins the saved networks it can see, strongest first."; Component.onCompleted: page.mark("wifi", this) }

    Notice { visible: !Network.wifiAvailable; icon: "wifi"; text: "No Wi-Fi adapter found." + (Network.ethernet.length ? " Ethernet below still works." : "") }

    Card {
        visible: Network.wifiAvailable
        divided: true
        SettingRow {
            icon: "wifi"
            label: "Wi-Fi"
            hint: !Network.wifiHardware ? "Turned off by a hardware switch or the firmware" : !page.wifiShownOn ? "Off"
                : page.cur ? "Connected" : (Network.joining || Network.connecting) ? "Joining “" + (Network.joining || Network.connecting) + "”…" : "On · not connected"
            Toggle {
                checked: page.wifiShownOn
                enabled: Network.wifiHardware
                opacity: enabled ? 1 : 0.45
                onToggled: v => { if (v) Network.setWifi(true); else Network.turnWifiOff(); }
            }
        }
        // The network in use, its details, and what to do with it.
        ColumnLayout {
            visible: page.wifiShownOn && !!page.cur
            Layout.fillWidth: true
            spacing: 0
            NetworkRow {
                readonly property bool forgotten: !!page.cur && !!Network.forgetting[page.cur.uuid]
                icon: "wifi"
                signal: page.cur ? page.cur.signal : 0
                selected: true
                clickable: false
                secure: !!page.cur && page.cur.kind !== "open"
                title: page.cur ? page.cur.ssid : ""
                subtitle: !page.cur ? "" : forgotten ? "Forgotten · disconnects when the toast closes" : Network.leaving === page.cur.uuid ? "Disconnecting…"
                    : ["Connected", page.cur.security, page.cur.band].filter(x => x).join(" · ")
                Button { text: "Disconnect"; enabled: !!page.cur && Network.leaving !== page.cur.uuid; onClicked: Network.disconnectSoon() }
            }
            NetworkDetails {
                Layout.leftMargin: 56; Layout.rightMargin: 14; Layout.topMargin: 2
                rows: !page.cur ? [] : [
                    ["IP address", page.bare(page.cur.ip4)], ["Router", page.cur.gateway], ["DNS", page.cur.dns.join(", ")],
                    ["Signal", page.cur.signal ? page.cur.signal + "% · " + page.quality(page.cur.signal) : ""], ["Security", page.cur.security],
                    ["Band", page.cur.band ? page.cur.band + (page.cur.channel ? " · channel " + page.cur.channel : "") : ""],
                    ["Link speed", (page.cur.rate || "").replace("Mbit/s", "Mb/s")], ["IPv6", page.bare(page.cur.ip6)],
                    ["MAC address", page.cur.mac], ["Interface", page.cur.device]
                ]
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 56; Layout.rightMargin: 12; Layout.topMargin: 10; Layout.bottomMargin: 12
                spacing: 10
                Toggle {
                    checked: !!page.cur && page.cur.autoconnect
                    onToggled: v => Network.setAutoconnect(page.cur.uuid, v)
                }
                Label { text: "Join automatically"; font.pixelSize: Theme.fsS; Layout.fillWidth: true; Layout.minimumWidth: 0 }
                Button {
                    text: "Forget this network"
                    enabled: !!page.cur && !Network.forgetting[page.cur.uuid]
                    onClicked: Network.forget(page.cur.uuid, page.cur.ssid)
                }
            }
        }
    }

    Notice {
        visible: Network.wifiAvailable && !page.wifiShownOn
        icon: "wifi"
        text: Network.wifiHardware ? "Wi-Fi is off. Saved networks stay saved." : "Wi-Fi is blocked by a hardware switch or the firmware; turn it on there first."
        action: Network.wifiHardware ? "Turn on" : ""
        onActed: Network.setWifi(true)
        Layout.topMargin: 10
    }

    // Networks in range: saved first, then the rest, then a hidden one.
    RowLayout {
        visible: page.wifiShownOn
        Layout.fillWidth: true
        Layout.topMargin: 22
        Layout.bottomMargin: 8
        spacing: 10
        Cap { text: page.saved.length || page.far.length ? "Saved networks" : "Networks in range"; Layout.fillWidth: true; Layout.minimumWidth: 0 }
        Button { text: Network.scanning ? "Scanning" : "Scan"; icon: "reload"; busy: Network.scanning; onClicked: Network.scan() }
    }

    Card {
        visible: page.wifiShownOn && (page.saved.length > 0 || page.far.length > 0)
        divided: true
        Repeater { model: page.saved; delegate: wifiRow }
        Repeater {
            model: page.far
            NetworkRow {
                required property var modelData
                icon: "wifi"
                signal: 0
                dim: true
                clickable: false
                title: modelData.ssid
                subtitle: modelData.hidden ? "Saved · hidden network" : "Saved · not in range"
                Button { text: "Forget"; onClicked: Network.forget(modelData.uuid, modelData.ssid) }
            }
        }
    }

    Cap { visible: page.wifiShownOn && (page.saved.length > 0 || page.far.length > 0); text: "Other networks"; Layout.topMargin: 18; Layout.bottomMargin: 8; Layout.fillWidth: true }

    Card {
        visible: page.wifiShownOn
        divided: true
        Repeater { model: page.others; delegate: wifiRow }
        Item {
            visible: page.others.length === 0
            Layout.fillWidth: true
            implicitHeight: 52
            Label {
                anchors { left: parent.left; right: parent.right; leftMargin: 16; rightMargin: 16; verticalCenter: parent.verticalCenter }
                text: Network.scanning ? "Looking for networks…" : page.saved.length ? "No other networks in range." : "No networks in range. Scan again, or join a hidden one."
                color: Theme.text2; font.pixelSize: Theme.fsS
            }
        }
        NetworkRow {
            id: hiddenRow
            icon: "plus"
            title: "Join a hidden network…"
            subtitle: "One that does not show its name"
            open: page.hiddenOpen
            clickable: !page.hiddenOpen && Network.joining === ""
            busy: page.hiddenOpen && Network.joining !== ""
            panel: hiddenForm
            onClicked: page.openHidden()
            Component.onCompleted: page.mark("hidden", this)
        }
    }

    // A network in range: click to join; a secured one opens its password field.
    Component {
        id: wifiRow
        NetworkRow {
            id: row
            required property var modelData
            readonly property var n: modelData
            icon: "wifi"
            signal: n.signal
            secure: n.secure
            title: n.ssid
            subtitle: page.line(n)
            subtitleColor: Network.joinError.ssid === n.ssid && Network.joinError.kind !== "password" ? Theme.error : Theme.text2
            busy: Network.joining === n.ssid
            open: page.open === n.ssid
            clickable: Network.joining === "" && !open
            panel: passwordForm
            onClicked: page.choose(n)
            onOpenChanged: if (open) page.mark("join", row)
            Component.onCompleted: if (open) page.mark("join", row)
            Button { visible: row.n.known && !row.open; text: "Forget"; onClicked: Network.forget(row.n.uuid, row.n.ssid) }
        }
    }

    // The password for page.open: show/hide, Enter joins, wrong ones say so.
    Component {
        id: passwordForm
        ColumnLayout {
            id: form
            readonly property string name: page.open
            readonly property var net: Network.networks.find(n => n.ssid === name) || null
            property string local: ""
            readonly property string err: local !== "" ? local
                : Network.joinError.ssid === name && Network.joinError.kind === "password"
                    ? (net && net.known ? "The saved password did not work. Type the current one." : Network.joinError.text) : ""
            function go() {
                if (pw.text.length < 8 || pw.text.length > 64) { local = "Wi-Fi passwords are 8 to 63 characters (or a 64-digit key)."; return; }
                local = "";
                Network.join(name, pw.text);
            }
            // A refused password is selected, so typing again replaces it.
            Connections { target: Network; function onJoinErrorChanged() { if (form.err !== "") pw.focusNow(); } }
            spacing: 6
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Item {
                    Layout.fillWidth: true; Layout.minimumWidth: 0
                    implicitHeight: pw.implicitHeight
                    Field {
                        id: pw
                        anchors.fill: parent
                        password: true
                        icon: "lock"
                        placeholder: "Password"
                        onTextChanged: { page.draft = text; form.local = ""; }
                        onAccepted: form.go()
                        onCancelled: page.closeForm()
                        Component.onCompleted: { text = page.draft; focusNow(); }
                    }
                    Rectangle {
                        anchors.fill: parent
                        visible: form.err !== ""
                        radius: Theme.rS
                        color: "transparent"
                        border.width: 2
                        border.color: Theme.error
                    }
                }
                Button { text: "Join"; primary: true; busy: Network.joining === form.name; enabled: pw.text.length > 0; onClicked: form.go() }
                Button { text: "Cancel"; enabled: Network.joining !== form.name; onClicked: page.closeForm() }
            }
            Text {
                visible: form.err !== ""
                text: form.err
                color: Theme.error; font.family: Theme.ui; font.pixelSize: Theme.fsS
                wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight
                Layout.fillWidth: true
            }
        }
    }

    // A hidden network: its name, its security, and a password unless open.
    Component {
        id: hiddenForm
        ColumnLayout {
            id: hf
            property string kind: "psk"
            property string local: ""
            readonly property string err: local !== "" ? local
                : Network.joinError.ssid !== "" && Network.joinError.ssid === ssidField.text.trim() ? Network.joinError.text : ""
            function go() {
                const n = ssidField.text.trim();
                if (!n) { local = "Type the network’s name."; return; }
                if (n.length > 32) { local = "Network names are at most 32 characters."; return; }
                if (kind !== "open" && (pass.text.length < 8 || pass.text.length > 64)) { local = "Wi-Fi passwords are 8 to 63 characters (or a 64-digit key)."; return; }
                local = "";
                Network.join(n, kind === "open" ? "" : pass.text, { "hidden": true, "kind": kind });
            }
            spacing: 8
            Field { id: ssidField; Layout.fillWidth: true; icon: "wifi"; placeholder: "Network name"; onTextChanged: hf.local = ""; onAccepted: hf.kind === "open" ? hf.go() : pass.focusNow(); onCancelled: page.closeForm(); Component.onCompleted: focusNow() }
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Label { text: "Security"; color: Theme.text2; font.pixelSize: Theme.fsS }
                Choice {
                    options: [{ "value": "open", "label": "None" }, { "value": "psk", "label": "WPA/WPA2" }, { "value": "sae", "label": "WPA3" }]
                    value: hf.kind
                    onChosen: v => { hf.kind = v; hf.local = ""; }
                }
                Item { Layout.fillWidth: true }
            }
            Field {
                id: pass
                visible: hf.kind !== "open"
                Layout.fillWidth: true
                password: true; icon: "lock"; placeholder: "Password"
                onTextChanged: { page.draft = text; hf.local = ""; }
                onAccepted: hf.go()
                onCancelled: page.closeForm()
            }
            Text {
                visible: hf.err !== ""
                text: hf.err
                color: Theme.error; font.family: Theme.ui; font.pixelSize: Theme.fsS
                wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight
                Layout.fillWidth: true
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Item { Layout.fillWidth: true }
                Button { text: "Cancel"; enabled: Network.joining === ""; onClicked: page.closeForm() }
                Button { text: "Join"; primary: true; busy: Network.joining !== ""; enabled: ssidField.text.trim() !== ""; onClicked: hf.go() }
            }
        }
    }

    // --------------------------------------------------------------- Ethernet

    Section { visible: Network.ethernet.length > 0; title: "Ethernet"; hint: "Plug in a cable and it connects on its own."; Component.onCompleted: page.mark("ethernet", this) }
    Card {
        visible: Network.ethernet.length > 0
        divided: true
        Repeater {
            model: Network.ethernet
            ColumnLayout {
                id: wire
                required property var modelData
                readonly property var e: modelData
                Layout.fillWidth: true
                spacing: 0
                NetworkRow {
                    icon: "ethernet"
                    selected: wire.e.connected
                    clickable: false
                    title: wire.e.connected && wire.e.name ? wire.e.name : "Ethernet"
                    subtitle: wire.e.connected ? ["Connected", wire.e.speed, wire.e.device].filter(x => x).join(" · ")
                        : (!wire.e.carrier ? "Cable unplugged" : wire.e.state === "connecting" ? "Connecting…" : "Not connected") + " · " + wire.e.device
                }
                NetworkDetails {
                    visible: wire.e.connected
                    Layout.leftMargin: 56; Layout.rightMargin: 14; Layout.bottomMargin: 12
                    rows: [["IP address", page.bare(wire.e.ip4)], ["Router", wire.e.gateway], ["DNS", wire.e.dns.join(", ")],
                           ["Speed", wire.e.speed], ["IPv6", page.bare(wire.e.ip6)], ["MAC address", wire.e.mac]]
                }
            }
        }
    }

    // -------------------------------------------------------------------- VPN

    Section {
        title: "VPN"
        hint: Tailscale.available ? "Tailscale reaches this laptop from anywhere; turning it off waits a moment so it can be undone." : "Private networks this laptop can join."
        Component.onCompleted: page.mark("vpn", this)
    }

    Notice {
        visible: !Tailscale.available && Network.vpns.length === 0
        icon: "shield"
        text: "No VPN set up: Tailscale is not installed and NetworkManager has no VPN connections."
    }

    Card {
        visible: Tailscale.available
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            SettingRow {
                icon: "shield"
                label: "Tailscale"
                hint: Tailscale.leaving ? "Turning off…" : Tailscale.busy ? (Tailscale.state === "Starting" ? "Connecting…" : "Disconnecting…")
                    : Tailscale.on ? "Connected" + (Tailscale.tailnet ? " · " + Tailscale.tailnet : "")
                    : Tailscale.state === "NeedsLogin" ? "Signed out" : Tailscale.state === "NeedsMachineAuth" ? "Waiting for the tailnet’s admin to approve this laptop" : "Off"
                Toggle {
                    checked: (Tailscale.on || Tailscale.state === "Starting") && !Tailscale.leaving
                    enabled: Tailscale.canToggle && !Tailscale.busy && Tailscale.state !== "NeedsLogin"
                    opacity: enabled ? 1 : 0.45
                    onToggled: v => { if (v) Tailscale.setOn(true); else Tailscale.turnOffSoon(); }
                }
            }
            NetworkDetails {
                visible: Tailscale.on && !Tailscale.leaving
                Layout.leftMargin: 56; Layout.rightMargin: 14; Layout.bottomMargin: 12
                rows: [["Tailnet", Tailscale.tailnet], ["This laptop", Tailscale.dnsName], ["Tailscale IP", Tailscale.ips[0] || ""], ["IPv6", Tailscale.ips[1] || ""],
                       ["Exit node", Tailscale.exitNode ? Tailscale.exitNode.name + (Tailscale.exitNode.online ? "" : " (offline)")
                                                        : "None" + (Tailscale.exitNodeOptions ? " · " + Tailscale.exitNodeOptions + " available" : "")],
                       ["Devices", Tailscale.peers ? Tailscale.peersOnline + " of " + Tailscale.peers + " online" : ""]]
            }
            Text {
                visible: !Tailscale.canToggle || Tailscale.state === "NeedsLogin"
                text: Tailscale.state === "NeedsLogin" ? "Sign in with “tailscale login” in a terminal; this page follows once it is up."
                    : "To switch Tailscale from here, run “tailscale set --operator=$USER” once."
                color: Theme.text2; font.family: Theme.ui; font.pixelSize: Theme.fsS
                wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight
                Layout.fillWidth: true; Layout.leftMargin: 56; Layout.rightMargin: 14; Layout.bottomMargin: 12
            }
        }
    }

    Cap { visible: Network.vpns.length > 0; text: Tailscale.available ? "Other VPN connections" : "VPN connections"; Layout.topMargin: 18; Layout.bottomMargin: 8; Layout.fillWidth: true }
    Card {
        visible: Network.vpns.length > 0
        divided: true
        Repeater {
            model: Network.vpns
            NetworkRow {
                required property var modelData
                icon: modelData.type === "WireGuard" ? "link" : "shield"
                selected: modelData.state === "on"
                busy: modelData.state === "starting"
                clickable: false
                title: modelData.name
                subtitle: modelData.type + " · " + (modelData.state === "on" ? "Connected" : modelData.state === "starting" ? "Connecting…" : "Off")
                Button { text: modelData.active ? "Disconnect" : "Connect"; onClicked: Network.setVpn(modelData.uuid, !modelData.active) }
            }
        }
    }
}
