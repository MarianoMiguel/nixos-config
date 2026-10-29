import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Polkit
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets

// The polkit agent: one PolkitAgent for the shell, and its dialog, a sheet
// printed in on a halftone scrim (workshop/studies/controls/v1.html) with
// the lock's cross grid as the password field. The harness never registers
// an agent (polkit lives on the system bus); fixtures show the dialog with
// made-up requests, accepting "folio".
Scope {
    id: root

    readonly property bool harness: (Quickshell.env("FOLIO_HARNESS") || "") !== ""
    readonly property var agent: agentLoader.item
    readonly property var flow: agent && agent.isActive ? agent.flow : null
    property var fx: null
    readonly property bool open: fx !== null || flow !== null

    // typing | checking | done
    property string phase: "typing"
    property string buffer: ""
    property string pending: ""
    property int lifting: -1
    readonly property int shown: lifting >= 0 ? lifting : buffer.length
    property string message: ""
    property bool messageError: false
    signal refused()
    signal accepted()

    readonly property string actionMessage: fx ? fx.message : flow ? flow.message : ""
    readonly property string actionId: fx ? fx.action : flow ? flow.actionId : ""
    readonly property string identity: fx ? fx.identity : flow && flow.selectedIdentity ? flow.selectedIdentity.string : ""
    readonly property string supplement: flow ? flow.supplementaryMessage : ""
    // PAM's own errors (a missed fingerprint, a locked account) when we have none.
    readonly property string note: message || (flow && flow.supplementaryIsError ? supplement : "")
    readonly property bool fingerprint: fx ? fx.fingerprint
        : flow !== null && !flow.isResponseRequired && (/finger|swipe|sensor/i.test(supplement) || Fingerprint.polkitReady)

    Loader {
        id: agentLoader
        active: !root.harness
        sourceComponent: Component { PolkitAgent {} }
    }

    function reset() {
        phase = "typing"; buffer = ""; pending = ""; lifting = -1;
        message = ""; messageError = false;
        liftTimer.stop();
    }
    onOpenChanged: if (open) reset()

    // Several identities (root and the wheel group's users): prefer ours.
    // Changing it restarts the conversation, which polkit reports as a
    // failure; that one is not the user's.
    property bool switching: false
    Connections {
        target: root.agent
        function onAuthenticationRequestStarted() {
            const f = root.agent.flow;
            const me = Quickshell.env("USER");
            if (!f || !f.identities || f.identities.length < 2) return;
            const mine = f.identities.find(i => !i.isGroup && i.string === me);
            if (!mine || mine === f.selectedIdentity) return;
            root.switching = true;
            f.selectedIdentity = mine;
            root.switching = false;
        }
    }
    Connections {
        target: root.flow
        function onAuthenticationFailed() { if (!root.switching) root.refuse("Not quite. The ink lifts; try again."); }
        function onAuthenticationSucceeded() { root.accept(); }
        function onIsResponseRequiredChanged() { if (root.flow.isResponseRequired && root.pending) root.answer(); }
    }

    function key(event) {
        const k = event.key;
        if (k === Qt.Key_Escape) { cancel(); return; }
        if (phase !== "typing") return;
        if (k === Qt.Key_Return || k === Qt.Key_Enter) { submit(); return; }
        if (k === Qt.Key_Backspace) { type((event.modifiers & Qt.ControlModifier) ? "" : buffer.slice(0, -1)); return; }
        if (event.modifiers & Qt.ControlModifier) return;
        const t = event.text;
        if (t && t.charCodeAt(0) >= 32 && t !== "\u007f") type((buffer + t).slice(0, 256));
    }
    function type(value) {
        liftTimer.stop(); lifting = -1;
        buffer = value;
        if (messageError) { message = ""; messageError = false; }
    }
    function submit() {
        if (phase !== "typing" || !buffer) return;
        phase = "checking"; message = ""; messageError = false;
        pending = buffer;
        if (fx) { fakeCheck.restart(); return; }
        if (flow && flow.isResponseRequired) answer();
    }
    // A password typed during the fingerprint step waits for the prompt.
    function answer() { const p = pending; pending = ""; flow.submit(p); }
    function cancel() {
        if (phase === "done") return;
        if (fx) { phase = "done"; closeTimer.restart(); return; }
        if (flow) flow.cancelAuthenticationRequest();
    }
    function accept() { phase = "done"; buffer = ""; pending = ""; accepted(); closeTimer.restart(); }
    function refuse(text) {
        if (phase === "done") return;
        phase = "typing"; pending = "";
        lifting = buffer.length; buffer = "";
        message = text; messageError = true;
        refused();
        liftTimer.interval = Math.max(1, 420 * Theme.motion);
        liftTimer.restart();
    }
    Timer {
        id: liftTimer
        repeat: true
        onTriggered: {
            interval = Math.max(1, 28 * Theme.motion);
            root.lifting = Math.max(0, root.lifting - 1);
            if (root.lifting === 0) { root.lifting = -1; stop(); }
        }
    }
    Timer {
        id: fakeCheck
        interval: 380
        onTriggered: if (root.pending === "folio") root.accept(); else root.refuse("Not quite. The ink lifts; try again.")
    }
    // A fixture closes itself once the cells have flooded.
    Timer { id: closeTimer; interval: Math.max(1, 520 * Theme.motion); onTriggered: if (root.fx) root.fx = null }

    PolkitDialog { owner: root }

    readonly property var fixtures: ({
        "normal": { "message": "Authentication is required to run `nixos-rebuild switch` as the super user.", "action": "org.freedesktop.policykit.exec", "identity": "mariano", "fingerprint": true },
        "stress": { "message": "Authentication is required to change the system-wide configuration of the network connection “Departamento 4B — Red de invitados de la oficina central, piso 12, ala norte (5 GHz)”, which is shared with all users of this computer and requires administrator privileges.", "action": "org.freedesktop.NetworkManager.settings.modify.system.with-a-very-long-action-identifier", "identity": "mariano.miguel.de.los.santos.echeverria.uriarte", "fingerprint": true },
        "empty": { "message": "", "action": "", "identity": "", "fingerprint": false }
    })

    IpcHandler {
        target: "polkit"
        function fixture(name: string): void { root.fx = root.fixtures[name] || null; root.reset(); }
        function cancel(): void { root.cancel(); }
    }
}
