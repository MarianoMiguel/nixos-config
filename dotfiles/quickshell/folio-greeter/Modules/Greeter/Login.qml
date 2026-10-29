import QtQuick
import Quickshell
import Quickshell.Services.Greetd

// The conversation with greetd for one user. greetd runs the system's
// `greetd` PAM stack in order: with pam_fprintd first (Bonhart), PAM says
// "Place your finger…", listens for a few seconds, then asks for the
// password. A password typed before PAM asks for it waits here and goes the
// moment it does. A finger works only while PAM listens; restart() listens
// again. In the harness (FOLIO_HARNESS) a pretend greetd plays the same
// messages: "folio" is the only password, `touch` is a finger.
Scope {
    id: root

    readonly property bool harness: (Quickshell.env("FOLIO_HARNESS") || "") !== ""
    readonly property bool available: harness || Greetd.available
    property var fx: ({})                   // the pretend greetd's script (harness)

    property string user: ""
    property bool active: false             // a session is being configured
    property bool awaiting: false           // PAM asked; respond() answers
    property bool listening: false          // PAM is waiting for a finger
    property bool fingerSeen: false         // this system offers a finger at all
    property string question: ""            // PAM's prompt when it is not just "Password:"
    property string pending: ""             // typed before PAM asked
    readonly property bool checking: pending !== "" || answered

    signal notice(string message, bool error)
    signal failed(string message)
    signal ready()
    signal broke(string message)

    property bool answered: false

    function begin(name) {
        if (!available || !name) return;
        reset();
        user = name;
        active = true;
        if (harness) fake.begin();
        else Greetd.createSession(name);
    }
    function cancel() {
        reset();
        if (harness) fake.stop();
        else if (Greetd.state !== GreetdState.Inactive) Greetd.cancelSession();
    }
    // Listen for a finger again: a fresh conversation for the same user.
    function restart() { const u = user; cancel(); begin(u); }
    function submit(password) {
        if (!active) begin(user);
        stall.restart();
        if (awaiting) answer(password);
        else pending = password;
    }
    function launch(command, env) {
        if (harness) { fake.launch(command, env); return; }
        Greetd.launch(command, env);
    }

    function reset() {
        stall.stop();
        active = false; awaiting = false; listening = false; answered = false;
        question = ""; pending = "";
    }
    function answer(text) {
        awaiting = false;
        answered = true;
        listening = false;
        if (harness) fake.respond(text);
        else Greetd.respond(text);
    }
    // A prompt from PAM. `secret` hides the answer; either takes the password.
    function asked(message, secret) {
        listening = false;
        awaiting = true;
        const m = (message || "").trim();
        question = /^password:?$/i.test(m) ? "" : m.replace(/:\s*$/, "");
        if (pending !== "") { const p = pending; pending = ""; answer(p); }
    }
    function told(message, error) {
        const m = (message || "").trim();
        if (!m) return;
        if (!error && /finger|swipe|sensor|reader/i.test(m)) { listening = true; fingerSeen = true; return; }
        if (/time(d)? ?out/i.test(m)) return;           // the reader gave up: the password prompt follows
        if (error && /finger|match/i.test(m)) { listening = false; notice("Not that finger. Type your password.", true); return; }
        notice(m, error);
    }

    // A check that never answers must not leave the screen unusable.
    Timer {
        id: stall
        interval: 25000
        onTriggered: if (root.active && root.checking) { root.cancel(); root.broke("The check took too long. Try again."); }
    }

    Connections {
        target: root.harness ? null : Greetd
        function onAuthMessage(message, error, responseRequired, echoResponse) {
            if (responseRequired) root.asked(message, !echoResponse);
            else root.told(message, error);
        }
        function onAuthFailure(message) { root.reset(); root.failed(message || ""); }
        function onReadyToLaunch() { stall.stop(); root.answered = false; root.awaiting = false; root.listening = false; root.ready(); }
        function onError(error) { root.reset(); root.broke(error || "greetd refused"); }
    }

    // The pretend greetd for the harness: the same messages, no PAM.
    QtObject {
        id: fake
        function begin() {
            fakeOpen.restart();
        }
        function stop() { fakeOpen.stop(); fakeFinger.stop(); fakeCheck.stop(); }
        function respond(text) { fakeCheck.answer = text; fakeCheck.restart(); }
        function touch() {
            if (!root.listening) return;
            fakeFinger.stop();
            root.listening = false;
            stall.stop();
            root.pending = "";
            root.ready();
        }
        function launch(command, env) {
            console.warn("Greeter (harness): would launch", JSON.stringify(command), JSON.stringify(env));
            root.launched(command.join(" "));
        }
    }
    signal launched(string command)          // harness only: greetd took the session
    function touch() { if (harness) fake.touch(); }
    Timer {
        id: fakeOpen
        interval: 150
        onTriggered: {
            if (root.fx.finger) { root.told("Place your finger on the fingerprint reader", false); fakeFinger.restart(); }
            else root.asked("Password: ", true);
        }
    }
    Timer {
        id: fakeFinger
        interval: 5000
        onTriggered: { root.told("Verification timed out", true); root.asked("Password: ", true); }
    }
    Timer {
        id: fakeCheck
        property string answer: ""
        interval: 420
        onTriggered: {
            if (answer === "folio") { root.answered = false; stall.stop(); root.ready(); return; }
            root.reset();
            root.failed(root.fx.lockout || "Authentication failed");
        }
    }
}
