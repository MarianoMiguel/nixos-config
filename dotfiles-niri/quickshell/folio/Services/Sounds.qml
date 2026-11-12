pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common

// Folio's interface sounds: short, soft and tonal, one family around D
// (sounds/*.wav, synthesized from scratch by scripts/folio-sounds when the
// shell is built; the harness makes them too).
//
// play(name) plays one through PipeWire (pw-play) at the effects volume and
// says whether it did. Interface sounds follow the "sounds" setting (off by
// default). The notification sounds ("notification", "message") follow each
// app's sound switch instead (Services/Notifs asks only when it is on) and
// keep quiet during Do not disturb, Focus or the schedule, unless the
// notification is critical (opts.urgent). The effects volume
// ("sounds.volume", 0 to 1) is perceptual like the volume keys: the stream's
// gain is its cube. A held key plays at most every 90 ms, other repeats every
// 120 ms, notification sounds once in 1.5 s. audition(name) is the Settings
// page's Play button: it plays whatever the switches say.
//
// In the harness a play is only recorded (Sys.run; `settings dryrun` lists
// it), so tests make no noise. IPC `sounds`: play NAME, audition NAME,
// volume LEVEL, state. Quickshell makes the service on first use, so the
// target answers once something has played (or the Sound page opened).
Singleton {
    id: root

    // The set, in the order Settings lists them.
    readonly property var catalogue: [
        { "name": "notification", "label": "Notification", "icon": "bell" },
        { "name": "message", "label": "Message", "icon": "message" },
        { "name": "error", "label": "Error", "icon": "info" },
        { "name": "low-battery", "label": "Low battery", "icon": "battery" },
        { "name": "pop", "label": "Confirm", "icon": "check" },
        { "name": "volume", "label": "Volume", "icon": "speaker" },
        { "name": "screenshot", "label": "Screenshot", "icon": "image" },
        { "name": "trash", "label": "Move to Trash", "icon": "trash" },
        { "name": "empty-trash", "label": "Empty Trash", "icon": "trash" },
        { "name": "lock", "label": "Lock", "icon": "lock" },
        { "name": "unlock", "label": "Unlock", "icon": "lock" },
        { "name": "plug", "label": "Power connected", "icon": "bolt" },
        { "name": "unplug", "label": "Power disconnected", "icon": "battery" },
        { "name": "device-in", "label": "Device connected", "icon": "usb" },
        { "name": "device-out", "label": "Device removed", "icon": "usb" }
    ]
    readonly property var names: catalogue.map(s => s.name)
    readonly property var alerts: ["notification", "message"]

    readonly property string dir: String(Quickshell.shellDir).replace(/^file:\/\//, "") + "/sounds"
    readonly property real defaultVolume: 0.7
    readonly property bool enabled: pref("sounds") === true
    readonly property real volume: level(pref("sounds.volume"))

    // The preferences Audio keeps (in the harness, the Sound page's changes
    // stay in memory there), never a Sound page fixture's.
    function pref(k) { return Sys.harness && k in Audio.harnessPrefs ? Audio.harnessPrefs[k] : Settings.get(k); }
    function level(v) {
        const n = Number(v);
        return v === undefined || v === null || v === "" || isNaN(n) ? defaultVolume : Math.max(0, Math.min(1, n));
    }
    function setVolume(v) { Audio.setPref("sounds.volume", Math.round(level(v) * 100) / 100); }

    // Chat apps get the softer "message": the notification's category (im,
    // im.received) says so, or the app is a known messenger.
    function chat(n) {
        const h = n.hints || {};
        if (/^im(\.|$)/.test(String(h["category"] || ""))) return true;
        return /\b(slack|telegram\w*|kotatogram|signal|beeper\w*|discord|vesktop|webcord|whatsapp|element|fractal|nheko|teams|mattermost|zulip|gajim|dino|hexchat|polari|threema|skype|ferdium)\b/i
            .test((n.appName || "") + " " + (n.desktopEntry || ""));
    }

    readonly property var gaps: ({ "volume": 90, "alert": 1500 })
    property var last: ({})
    property var history: []               // the last plays and refusals, newest first: {name, why, at}

    // name: one of `names`. opts: urgent (a critical notification: plays
    // through quiet), file (an app's own sound, played by the same rules),
    // audition (Settings' Play: no switches, no rate limit).
    function play(name, opts) {
        opts = opts || {};
        const alert = alerts.indexOf(name) >= 0;
        const key = alert ? "alert" : name;
        const now = Date.now();
        let why = "";
        if (names.indexOf(name) < 0) why = "unknown";
        else if (!opts.audition && alert && Notifs.quiet && !opts.urgent) why = "quiet";
        else if (!opts.audition && !alert && !enabled) why = "off";
        else if (!opts.audition && now - (last[key] || 0) < (gaps[key] || 120)) why = "rate";
        else if (volume <= 0) why = "silent";
        history = [{ "name": name, "why": why || "played", "at": now }].concat(history).slice(0, 30);
        if (why) return false;
        const l = Object.assign({}, last);
        l[key] = now;
        last = l;
        Sys.run(["pw-play", "--media-role", "Notification", "--volume", Math.pow(volume, 3).toFixed(3),
                 "-P", JSON.stringify({ "application.name": "Interstellar", "media.name": name }),
                 opts.file || (dir + (Theme.lumen ? "/lumen/" : "/") + name + ".wav")]);
        return true;
    }
    function audition(name) { return play(name, { "audition": true }); }

    IpcHandler {
        target: "sounds"
        // "played", or why not: unknown | quiet | off | rate | silent.
        function play(name: string): string { root.play(name); return root.history[0].why; }
        function audition(name: string): string { root.audition(name); return root.history[0].why; }
        // The effects volume, 0 to 1 (the harness keeps it in memory).
        function volume(value: real): void { root.setVolume(value); }
        function state(): string {
            return JSON.stringify({ "enabled": root.enabled, "volume": root.volume, "gain": Math.pow(root.volume, 3),
                                    "quiet": Notifs.quiet, "dir": root.dir, "history": root.history.slice(0, 12) });
        }
    }
}
