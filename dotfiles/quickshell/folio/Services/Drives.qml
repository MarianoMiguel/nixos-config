pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common

// Storage: how full the internal filesystems are (df, never du over the
// system), the removable drives UDisks2 knows (busctl's JSON of its objects,
// read again whenever `udisksctl monitor` reports), the Trash, and NixOS's
// automatic cleanup. Signals tell the shell when a drive arrives, is ejected
// or is pulled out; new drives are mounted unless Settings say otherwise
// (drives.automount).
//
// Mount, unmount, eject (unmount, lock, power off), open in Files and
// emptying the Trash go through Sys.run, so the harness only records them.
// Drive actions run as one small script ($XDG_RUNTIME_DIR/folio-drives/act.sh,
// written at start) that leaves its exit status and error next to it for a
// watcher to read back: the shell hears "target is busy" instead of guessing.
//
// Fixtures (IPC `drives fixture normal|stress|empty`, "" for live) replace
// all of it with a made-up machine; `drives plug usb|card|long|locked|multi|busy`
// and `drives unplug` simulate a drive arriving and being pulled out. With a
// fixture, actions change the fixture and never run (outside the harness
// they are not even recorded: fixture devices are not real ones).
Singleton {
    id: root

    // ------------------------------------------------------------ the model
    readonly property var model: shape(fake ? fxRaw : liveRaw)
    readonly property bool available: model.udisks           // UDisks2 answered: removable drives can show
    readonly property var disks: model.disks                 // internal disks: [{model, size, bus}]
    readonly property var volumes: model.volumes             // internal filesystems, "/" first
    readonly property var drives: model.drives               // removable drives, in the order they arrived
    readonly property var trash: model.trash                 // {known, items, size}
    readonly property var cleanup: model.cleanup             // {known, gc, next, optimise, generations}
    readonly property bool usageRead: fake || !!liveRaw.usageRead   // df has answered once
    // Ids for Repeaters. They change only when the set does, so rows keep
    // their state (and their bars glide) across refreshes.
    property var volumeIds: []
    property var driveIds: []

    // What this shell is doing.
    property var busy: ({})            // drive id → "mount" | "open" | "unmount" | "eject"
    property var errors: ({})          // drive id → what went wrong, in a sentence
    property var parked: ({})          // drive id → true: ejected but still plugged in (card readers)
    property int trashToast: 0
    readonly property bool emptying: trashToast > 0 && Toasts.items.some(t => t.id === trashToast)

    property string fixture: ""
    readonly property bool fake: fixture !== ""
    property var fxRaw: ({})
    property var liveRaw: ({ "udisks": true, "disks": [], "drives": [], "usage": {}, "trash": {}, "cleanup": {} })
    property int watchers: 0

    signal added(var d)                 // plugged in (not the drives present at start)
    signal ejected(var d)               // safe to remove
    signal unplugged(var d, bool wasMounted)
    signal failed(var d, string kind, string reason)   // reason: busy | auth | format | other

    readonly property string runDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/folio-drives"

    // ------------------------------------------------------------- reading

    function drive(id) { return drives.find(d => d.id === id) || null; }
    function volume(id) { return volumes.find(v => v.id === id) || null; }
    // "SanDisk Ultra · 32 GB"
    function title(d) { return d ? d.name + (d.size > 0 ? " · " + bytes(d.size) : "") : ""; }
    // Decimal units, as drives are sold: 1.0 TB, 32 GB, 6.4 GB.
    function bytes(n) {
        if (!(n >= 0)) return "";
        const units = ["bytes", "kB", "MB", "GB", "TB", "PB"];
        let v = n, i = 0;
        while (v >= 1000 && i < units.length - 1) { v /= 1000; i++; }
        if (i === 0) return Math.round(v) + " bytes";
        if (Math.round(v) >= 1000 && i < units.length - 1) { v /= 1000; i++; }
        return (v < 10 ? (Math.round(v * 10) / 10).toFixed(1) : String(Math.round(v))) + " " + units[i];
    }
    function fsName(t) {
        const names = { "vfat": "FAT32", "exfat": "exFAT", "ntfs": "NTFS", "ntfs3": "NTFS", "ext2": "ext2", "ext3": "ext3", "ext4": "ext4", "btrfs": "Btrfs",
                        "xfs": "XFS", "f2fs": "F2FS", "iso9660": "ISO 9660", "udf": "UDF", "hfsplus": "HFS+", "apfs": "APFS", "crypto_LUKS": "LUKS", "zfs": "ZFS" };
        return names[t] || t || "";
    }

    function watch() { watchers++; refresh(); refreshTrash(); refreshCleanup(); }
    function unwatch() { watchers = Math.max(0, watchers - 1); }
    function refresh() { if (!fake) { kick.restart(); refreshUsage(); } }
    function refreshUsage() { if (!fake) usage.running = true; }
    function refreshTrash() { if (!fake) trashProbe.running = true; }
    function refreshCleanup() { if (!fake) cleanupProbe.running = true; }

    // ------------------------------------------------------------- actions

    // Mounts one volume (device) or every volume that can be mounted.
    function mount(id, device) {
        const d = drive(id);
        if (!d) return;
        const vols = d.volumes.filter(v => !v.mount && !v.locked && v.fstype && (!device || v.device === device || v.mountDevice === device));
        if (vols.length) act("mount", id, vols.map(v => ["mount", v.mountDevice || v.device]));
    }
    function unmount(id, device) {
        const d = drive(id);
        if (!d) return;
        const vols = d.volumes.filter(v => v.mount && (!device || v.device === device || v.mountDevice === device));
        if (vols.length) act("unmount", id, vols.map(v => ["unmount", v.mountDevice || v.device]));
    }
    // Unmounts everything on the drive, locks what was unlocked, then powers
    // it off (or ejects a disc), like Files' "Safely remove".
    function eject(id) {
        const d = drive(id);
        if (!d || busy[id] || d.parked) return;
        const ops = [];
        for (const v of d.volumes) {
            if (v.mount) ops.push(["unmount", v.mountDevice || v.device]);
            if (v.encrypted && !v.locked) ops.push(["lock", v.device]);
        }
        if (d.device && d.canPowerOff) ops.push(["off", d.device]);
        else if (d.device && d.optical) ops.push(["eject", d.device]);
        ejectState[id] = "running";
        if (ops.length) act("eject", id, ops);
        else done("eject", id, "0\n");
    }
    // Opens a volume (device, or the drive's first readable one) in Files,
    // mounting it first when it is not.
    function open(id, device) {
        const d = drive(id);
        if (!d) return;
        const v = device ? d.volumes.find(x => x.device === device || x.mountDevice === device)
                         : (d.volumes.find(x => x.mount) || d.volumes.find(x => !x.locked && x.fstype));
        if (!v || v.locked) return;
        if (busy[id] === "mount") { openAfter[id] = v.mountDevice || v.device; return; }
        if (v.mount) exec(["xdg-open", v.mount]);
        else act("open", id, [["mount", v.mountDevice || v.device], ["open", v.mountDevice || v.device]]);
    }
    function openTrash() { exec(["gio", "open", "trash:///"]); }
    // Emptying cannot be undone: a countdown toast, Cancel stops it.
    function askEmptyTrash() {
        if (emptying || !trash.known || trash.items === 0) return;
        trashToast = Toasts.countdown("Emptying the Trash", () => { root.trashToast = 0; root.emptyTrash(); }, 5, Icons.get("trash").length ? "trash" : "folder");
    }
    function emptyTrash() {
        Sounds.play("empty-trash");
        if (fake) {
            if (Sys.harness) Sys.run(["gio", "trash", "--empty"]);
            patch(r => r.trash = { "known": true, "items": 0, "size": 0 });
            return;
        }
        if (Sys.run(["gio", "trash", "--empty"])) { later(1500, refreshTrash); later(6000, refreshTrash); }
    }

    function exec(cmd) {
        if (fake) { if (Sys.harness) Sys.run(cmd); return false; }
        return Sys.run(cmd);
    }

    // One drive action: ops ([verb, device]) run in order as one script,
    // stopping at the first failure; its status and error come back to done().
    // Kept as a file so `settings dryrun` reads "act.sh … unmount:/dev/sdb1".
    readonly property string actPath: runDir + "/act.sh"
    readonly property string actScript: [
        '# Folio (Services/Drives.qml): one drive action. Written at start; do not edit.',
        'out=$1; shift; st=0',
        'for op; do',
        '  d=${op#*:}',
        '  case ${op%%:*} in',
        '    mount) udisksctl mount -b "$d" ;;',
        '    unmount) udisksctl unmount -b "$d" ;;',
        '    lock) udisksctl lock -b "$d" ;;',
        '    off) udisksctl power-off -b "$d" ;;',
        '    eject) eject "$d" ;;',
        '    open) t=$(findmnt -fno TARGET --source "$d"); setsid -f xdg-open "${t:-$d}" ;;',
        '  esac >/dev/null 2>"$out.err" || grep -qE "AlreadyMounted|NotMounted|AlreadyLocked" "$out.err" || { st=1; break; }',
        'done',
        '{ echo "$st"; cat "$out.err"; } >"$out.tmp" 2>/dev/null; mv -f "$out.tmp" "$out"; rm -f "$out.err"'
    ].join("\n")
    // Waits (up to five minutes: a slow stick can take that long to flush)
    // for an action's result, prints it and removes the file.
    readonly property string waitScript: 'f=$1; i=0; while [ ! -e "$f" ]; do i=$((i+1)); [ "$i" -gt 1200 ] && exit 0; sleep 0.25; done; cat "$f"; rm -f "$f"'

    property int seq: 0
    property var ejectState: ({})        // drive id → "running" | "done" (bookkeeping, not bound)
    property var openAfter: ({})         // drive id → device to open once its mount is done
    function act(kind, id, ops) {
        if (busy[id]) return;
        setFor("busy", id, kind);
        setFor("errors", id, "");
        const out = runDir + "/act-" + Date.now() + "-" + (++seq);
        const cmd = ["sh", actPath, out].concat(ops.map(o => o[0] + ":" + o[1]));
        if (fake) {
            if (Sys.harness) Sys.run(cmd);   // listed by `settings dryrun`
            simulate(kind, id, ops);
            return;
        }
        if (!Sys.run(cmd)) { later(400, () => root.done(kind, id, "")); return; }   // the harness: recorded only
        const w = waiter.createObject(root, { "kind": kind, "driveId": id, "command": ["sh", "-c", waitScript, "sh", out] });
        w.running = true;
    }
    Component {
        id: waiter
        Process {
            id: w
            property string kind
            property string driveId
            stdout: StdioCollector {
                onStreamFinished: {
                    root.done(w.kind, w.driveId, text);
                    Qt.callLater(() => w.destroy());
                }
            }
        }
    }
    // text: "0" or "1", then the error. Empty: nothing ran (the harness) or
    // the watcher gave up; either way, just stop being busy.
    function done(kind, id, text) {
        setFor("busy", id, "");
        const lines = String(text || "").split("\n");
        const code = lines[0].trim();
        const msg = lines.slice(1).join(" ").trim();
        const d = drive(id) || (known && known[id]) || null;
        const then = openAfter[id];
        delete openAfter[id];
        if (then && kind === "mount" && code === "0") act("open", id, [["mount", then], ["open", then]]);
        if (code === "0" || code === "") {
            if (kind === "eject" && ejectState[id] === "running") {
                if (code === "0") {
                    ejectState[id] = "done";
                    if (drive(id)) setFor("parked", id, true);   // still there (no power-off): safe now
                    if (d) root.ejected(d);
                } else delete ejectState[id];
            }
        } else {
            if (kind === "eject") delete ejectState[id];
            const reason = /DeviceBusy|target is busy|in use/i.test(msg) ? "busy"
                         : /NotAuthorized|not authorized|AuthenticationRequired/i.test(msg) ? "auth"
                         : /wrong fs type|unknown filesystem|NotSupported|not supported/i.test(msg) ? "format" : "other";
            setFor("errors", id, explain(kind, reason));
            later(15000, () => { if (root.errors[id] === root.explain(kind, reason)) root.setFor("errors", id, ""); });
            if (d) root.failed(d, kind, reason);
        }
        refresh();
    }
    function explain(kind, reason) {
        if (reason === "busy") return kind === "mount" || kind === "open" ? "Busy. Try again in a moment." : "In use. Close the files on it, then eject again.";
        if (reason === "auth") return "The system did not allow it.";
        if (reason === "format") return "Its format can't be read here.";
        return kind === "eject" ? "Could not eject it." : kind === "unmount" ? "Could not unmount it." : "Could not open it.";
    }
    function setFor(prop, id, value) {
        const m = Object.assign({}, root[prop]);
        if (value) m[id] = value; else delete m[id];
        root[prop] = m;
    }

    // ------------------------------------------------------- arrivals, exits

    property var known: null             // drive id → its last shape; null before the first look
    property bool primed: false          // false: the next change only records what is there
    property bool livePrimed: false
    onModelChanged: diff()
    function put(prop, value) { if (JSON.stringify(root[prop]) !== JSON.stringify(value)) root[prop] = value; }
    function diff() {
        const list = model.drives;
        put("driveIds", list.map(d => d.id));
        put("volumeIds", model.volumes.map(v => v.id));
        const now = {};
        for (const d of list) now[d.id] = d;
        const before = known;
        known = now;
        if (!before || !primed) return;
        for (const d of list) if (!before[d.id]) { root.added(d); automount(d); }
        for (const id in before) if (!now[id]) gone(before[id]);
    }
    function gone(d) {
        const st = ejectState[d.id];
        delete ejectState[d.id];
        for (const p of ["busy", "errors", "parked"]) if (root[p][d.id]) setFor(p, d.id, "");
        if (st === "running") root.ejected(d);
        else if (st !== "done") root.unplugged(d, d.mounted);
    }
    function automount(d) {
        if (Settings.get("drives.automount") === false) return;
        const vols = d.volumes.filter(v => !v.mount && !v.locked && v.fstype && v.auto !== false);
        if (vols.length) act("mount", d.id, vols.map(v => ["mount", v.mountDevice || v.device]));
    }

    // ------------------------------------------------------------- shaping

    function clean(s) { return String(s || "").replace(/_/g, " ").replace(/\s+/g, " ").trim(); }
    function nameOf(d) {
        let vendor = clean(d.vendor), model = clean(d.model);
        if (/^(usb|generic|mass storage)$/i.test(vendor) || (vendor && model.toLowerCase().indexOf(vendor.toLowerCase()) === 0)) vendor = "";
        if (d.kind === "card" && !vendor) return "Memory card";
        const n = (vendor + " " + model).trim();
        return n || (d.kind === "optical" ? "Disc" : "USB drive");
    }
    // The raw form (from UDisks2 and df, or a fixture) → what pages read.
    function shape(raw) {
        raw = raw || {};
        const usage = raw.usage || {};
        const removable = {};
        const drives = (raw.drives || []).map(d => {
            const vols = (d.volumes || []).map(v => {
                removable[v.device] = true;
                removable[v.mountDevice || v.device] = true;
                const u = v.mount ? usage[v.mount] : null;
                return Object.assign({}, v, { "used": u ? u.used : -1, "free": u ? u.free : -1, "capacity": u ? u.size : -1 });
            });
            const mounted = vols.some(v => v.mount);
            return Object.assign({}, d, {
                "name": nameOf(d), "volumes": vols, "mounted": mounted,
                "label": (vols.find(v => v.label) || {}).label || "",
                "parked": !!parked[d.id] && !mounted
            });
        });
        const names = { "/": "System", "/home": "Home", "/nix": "Nix store", "/nix/store": "Nix store", "/boot": "Boot", "/boot/efi": "Boot", "/efi": "Boot" };
        const rank = m => m === "/" ? 0 : m === "/home" ? 1 : m.indexOf("/nix") === 0 ? 2 : (m === "/boot" || m === "/efi" || m === "/boot/efi") ? 9 : 5;
        const volumes = Object.keys(usage)
            .filter(m => usage[m].size > 0 && !/^\/(run\/media|media|run\/user)\//.test(m) && !removable[usage[m].source])
            .map(m => Object.assign({ "id": m, "mount": m, "name": names[m] || m }, usage[m]))
            .sort((a, b) => rank(a.mount) - rank(b.mount) || a.mount.localeCompare(b.mount));
        return {
            "udisks": raw.udisks !== false, "disks": raw.disks || [], "volumes": volumes, "drives": drives,
            "trash": Object.assign({ "known": false, "items": 0, "size": 0 }, raw.trash || {}),
            "cleanup": Object.assign({ "known": false, "gc": false, "next": 0, "optimise": false, "generations": 0 }, raw.cleanup || {})
        };
    }

    // ------------------------------------------------------------ live data

    function setLive(key, value) { const r = Object.assign({}, liveRaw); r[key] = value; liveRaw = r; }

    // Byte strings (ay) from busctl's JSON, NUL-terminated UTF-8.
    function utf8(bytes) {
        let out = "", i = 0;
        bytes = bytes || [];
        while (i < bytes.length && bytes[i] !== 0) {
            const b = bytes[i++];
            if (b < 0x80) out += String.fromCharCode(b);
            else if (b < 0xe0) out += String.fromCharCode(((b & 0x1f) << 6) | (bytes[i++] & 0x3f));
            else if (b < 0xf0) out += String.fromCharCode(((b & 0x0f) << 12) | ((bytes[i++] & 0x3f) << 6) | (bytes[i++] & 0x3f));
            else out += String.fromCodePoint(((b & 0x07) << 18) | ((bytes[i++] & 0x3f) << 12) | ((bytes[i++] & 0x3f) << 6) | (bytes[i++] & 0x3f));
        }
        return out;
    }
    function readUdisks(text) {
        let objs = null;
        try { objs = JSON.parse(text).data[0]; } catch (e) { objs = null; }
        if (!objs) { setLive("udisks", false); return; }
        const I = "org.freedesktop.UDisks2.";
        const val = (o, k, dflt) => o && o[k] !== undefined ? o[k].data : dflt;
        const blocks = [], drv = {};
        for (const path in objs) {
            const o = objs[path];
            if (o[I + "Drive"]) drv[path] = { "D": o[I + "Drive"], "nvme": !!o[I + "NVMe.Controller"] };
            if (o[I + "Block"]) blocks.push({ "path": path, "B": o[I + "Block"], "fs": o[I + "Filesystem"], "part": o[I + "Partition"], "enc": o[I + "Encrypted"] });
        }
        const dev = b => utf8(val(b.B, "Device", []));
        const disks = [], drives = [];
        for (const path in drv) {
            const D = drv[path].D;
            const bus = val(D, "ConnectionBus", "");
            const optical = val(D, "Optical", false) || String(val(D, "Media", "")).indexOf("optical") === 0;
            const whole = blocks.find(b => val(b.B, "Drive", "/") === path && !b.part);
            if (whole && val(whole.B, "HintIgnore", false)) continue;
            const isRemovable = val(D, "Removable", false) || val(D, "MediaRemovable", false) || val(D, "Ejectable", false) || ["usb", "sdio", "ieee1394"].indexOf(bus) >= 0;
            if (!isRemovable) {
                if (whole) disks.push({ "model": clean(val(D, "Vendor", "") + " " + val(D, "Model", "")), "size": val(D, "Size", 0),
                                        "bus": drv[path].nvme ? "NVMe" : val(D, "RotationRate", 0) !== 0 ? "HDD" : "SSD" });
                continue;
            }
            if (!val(D, "MediaAvailable", true) && !optical) continue;      // an empty card slot
            const vols = [];
            for (const b of blocks) {
                if (val(b.B, "Drive", "/") !== path) continue;
                if (b.part && val(b.part, "IsContainer", false)) continue;
                if (val(b.B, "HintIgnore", false)) continue;
                const use = val(b.B, "IdUsage", "");
                if (use !== "filesystem" && use !== "crypto") continue;
                const clear = b.enc ? blocks.find(c => val(c.B, "CryptoBackingDevice", "/") === b.path) : null;
                const fsb = clear || b;
                const mps = val(fsb.fs, "MountPoints", []);
                vols.push({
                    "device": dev(b), "mountDevice": dev(fsb),
                    "label": val(fsb.B, "IdLabel", "") || val(b.B, "IdLabel", "") || (b.part ? val(b.part, "Name", "") : ""),
                    "fstype": b.enc ? (clear ? val(clear.B, "IdType", "") : "") : val(b.B, "IdType", ""),
                    "size": val(b.B, "Size", 0), "mount": mps.length ? utf8(mps[0]) : "",
                    "encrypted": !!b.enc, "locked": !!b.enc && !clear, "auto": val(b.B, "HintAuto", true),
                    "number": b.part ? val(b.part, "Number", 0) : 0
                });
            }
            vols.sort((a, b) => a.number - b.number);
            const media = String(val(D, "Media", ""));
            drives.push({
                "id": path.slice(path.lastIndexOf("/") + 1), "vendor": val(D, "Vendor", ""), "model": val(D, "Model", ""),
                "size": val(D, "Size", 0) || (whole ? val(whole.B, "Size", 0) : 0), "bus": bus,
                "kind": optical ? "optical" : (bus === "sdio" || media.indexOf("flash_sd") === 0 || media.indexOf("flash_m") === 0) ? "card" : "usb",
                "device": whole ? dev(whole) : "", "canPowerOff": val(D, "CanPowerOff", false), "optical": optical,
                "sortKey": val(D, "SortKey", ""), "volumes": vols
            });
        }
        drives.sort((a, b) => a.sortKey.localeCompare(b.sortKey));
        liveRaw = Object.assign({}, liveRaw, { "udisks": true, "disks": disks, "drives": drives });
        if (!livePrimed) { livePrimed = true; if (!fake) primed = true; }
        refreshUsage();
    }

    Process {
        id: udisks
        property bool again: false
        command: ["busctl", "--system", "--json=short", "call", "org.freedesktop.UDisks2", "/org/freedesktop/UDisks2",
                  "org.freedesktop.DBus.ObjectManager", "GetManagedObjects"]
        stdout: StdioCollector { onStreamFinished: root.readUdisks(text) }
        onRunningChanged: if (!running && again) { again = false; running = true; }
    }
    Timer {
        id: kick
        interval: 300
        onTriggered: { if (udisks.running) udisks.again = true; else udisks.running = true; }
    }
    // Any change UDisks2 reports (a drive, a mount, a lock) → read again.
    // stdbuf: udisksctl buffers its output when it is not a terminal.
    Process {
        id: monitor
        running: true
        command: ["stdbuf", "-oL", "udisksctl", "monitor"]
        stdout: SplitParser { onRead: _ => kick.restart() }
        onExited: retry.start()
    }
    Timer { id: retry; interval: 10000; onTriggered: monitor.running = true }

    // Filesystems: local ones, without the virtual kinds; with whether they
    // sit on an encrypted device.
    Process {
        id: usage
        command: ["sh", "-c", [
            'timeout 5 df -l -B1 --output=source,fstype,size,used,avail,target -x tmpfs -x devtmpfs -x efivarfs -x squashfs -x overlay -x ramfs -x nsfs -x zram 2>/dev/null |',
            'tail -n +2 | while read -r src fs size used avail target; do',
            '  enc=0',
            '  case $src in /dev/*) lsblk -nso TYPE -- "$src" 2>/dev/null | grep -qx crypt && enc=1 ;; esac',
            '  printf "%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\n" "$src" "$fs" "$size" "$used" "$avail" "$enc" "$target"',
            'done'].join("\n")]
        stdout: StdioCollector {
            onStreamFinished: {
                const u = {};
                for (const line of text.split("\n")) {
                    const f = line.split("\t");
                    if (f.length < 7 || !(Number(f[2]) > 0)) continue;
                    u[f.slice(6).join("\t")] = { "source": f[0], "fstype": f[1], "size": Number(f[2]), "used": Number(f[3]), "free": Number(f[4]), "encrypted": f[5] === "1" };
                }
                const r = Object.assign({}, root.liveRaw, { "usageRead": true });
                if (Object.keys(u).length) r.usage = u;
                root.liveRaw = r;
            }
        }
    }
    Process {
        id: trashProbe
        command: ["sh", "-c", [
            'd=${XDG_DATA_HOME:-$HOME/.local/share}/Trash/files',
            '[ -d "$d" ] || { echo "0 0"; exit 0; }',
            'n=$(find "$d" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l)',
            's=0; [ "$n" -gt 0 ] && s=$(nice -n 10 timeout 20 du -sb -- "$d" 2>/dev/null | cut -f1)',
            'echo "$n ${s:-0}"'].join("\n")]
        stdout: StdioCollector {
            onStreamFinished: {
                const f = text.trim().split(/\s+/);
                if (f.length >= 2) root.setLive("trash", { "known": true, "items": Number(f[0]) || 0, "size": Number(f[1]) || 0 });
            }
        }
    }
    Process {
        id: cleanupProbe
        command: ["sh", "-c", [
            'systemctl show nix-gc.timer --timestamp=unix -p ActiveState -p NextElapseUSecRealtime 2>/dev/null',
            'printf "opt%s\\n" "$(systemctl show nix-optimise.timer -p ActiveState 2>/dev/null)"',
            'printf "gens=%s\\n" "$(ls -d /nix/var/nix/profiles/system-*-link 2>/dev/null | wc -l)"'].join("\n")]
        stdout: StdioCollector {
            onStreamFinished: {
                const c = { "known": true, "gc": false, "next": 0, "optimise": false, "generations": 0 };
                for (const line of text.split("\n")) {
                    const [k, v] = [line.slice(0, line.indexOf("=")), line.slice(line.indexOf("=") + 1)];
                    if (k === "ActiveState") c.gc = v === "active";
                    else if (k === "NextElapseUSecRealtime" && v.charAt(0) === "@") c.next = Number(v.slice(1)) * 1000;
                    else if (k === "optActiveState") c.optimise = v === "active";
                    else if (k === "gens") c.generations = Number(v) || 0;
                }
                root.setLive("cleanup", c);
            }
        }
    }
    // While a page watches: usage every 20 s.
    Timer { interval: 20000; repeat: true; running: root.watchers > 0 && !root.fake; onTriggered: root.refreshUsage() }
    Process {
        id: writeAct
        command: ["sh", "-c", 'umask 077; mkdir -p "${1%/*}" && printf "%s\\n" "$2" > "$1.new" && mv -f "$1.new" "$1"', "sh", root.actPath, root.actScript]
    }
    Component.onCompleted: { writeAct.running = true; kick.restart(); refreshUsage(); }

    // ------------------------------------------------------------ fixtures

    function patch(fn) { const r = JSON.parse(JSON.stringify(fxRaw)); fn(r); fxRaw = r; }
    // A short queue of delayed fixture steps (a mount takes a moment).
    property var queue: []
    function later(ms, fn) { queue = queue.concat([{ "at": Date.now() + ms, "fn": fn }]); }
    Timer {
        interval: 100; repeat: true; running: root.queue.length > 0
        onTriggered: {
            const now = Date.now(), due = root.queue.filter(q => q.at <= now);
            root.queue = root.queue.filter(q => q.at > now);
            for (const q of due) q.fn();
        }
    }

    function simulate(kind, id, ops) {
        const d = (fxRaw.drives || []).find(x => x.id === id);
        if (!d) { later(300, () => root.done(kind, id, "")); return; }
        if (kind === "eject") {
            const first = (d.volumes.find(v => v.mount) || d.volumes[0] || {}).device || d.device;
            if (d.inUse) {
                later(1400, () => root.done(kind, id, "1\nError unmounting " + first + ": GDBus.Error:org.freedesktop.UDisks2.Error.DeviceBusy: Error unmounting " + first + ": target is busy"));
                return;
            }
            later(1400, () => {
                root.patch(r => {
                    const x = r.drives.find(y => y.id === id);
                    if (!x) return;
                    for (const v of x.volumes) { if (v.mount) delete r.usage[v.mount]; v.mount = ""; if (v.encrypted) { v.locked = true; v.fstype = ""; } }
                    if (x.canPowerOff) r.drives = r.drives.filter(y => y.id !== id);
                });
                root.done(kind, id, "0\n");
            });
            return;
        }
        const devs = ops.filter(o => o[0] === "mount" || o[0] === "unmount").map(o => o[1]);
        later(kind === "unmount" ? 500 : 900, () => {
            root.patch(r => {
                const x = r.drives.find(y => y.id === id);
                if (!x) return;
                for (const v of x.volumes) {
                    if (devs.indexOf(v.mountDevice || v.device) < 0) continue;
                    if (kind === "unmount") { delete r.usage[v.mount]; v.mount = ""; }
                    else if (!v.mount && !v.locked) {
                        v.mount = "/run/media/mariano/" + (v.label || "disk");
                        r.usage[v.mount] = root.fxUsage(v);
                    }
                }
            });
            root.done(kind, id, "0\n");
        });
    }
    function fxUsage(v) {
        const size = Math.round(v.size * 0.985);
        const used = Math.round(size * (v.fill === undefined ? 0.3 : v.fill));
        return { "source": v.mountDevice || v.device, "fstype": v.fstype, "size": size, "used": used, "free": size - used, "encrypted": !!v.encrypted };
    }

    function setFixture(name) {
        primed = false;
        queue = [];
        ejectState = ({});
        const fx = name ? fixtures(name) : null;
        busy = fx ? (fx.state.busy || {}) : ({});
        errors = fx ? (fx.state.errors || {}) : ({});
        parked = fx ? (fx.state.parked || {}) : ({});
        if (fx) delete fx.state;
        fixture = name;
        fxRaw = fx || ({});
        primed = name ? true : livePrimed;
        if (!name) { refresh(); refreshTrash(); refreshCleanup(); }
    }
    // A drive arrives (fixtures only; a live machine switches to the empty one).
    property int plugged: 0
    function plug(kind) {
        if (!fake) setFixture("empty");
        const n = ++plugged;
        const letter = String.fromCharCode(98 + ((fxRaw.drives || []).length + n) % 24);
        const d = preset(kind || "usb", "plug" + n, "/dev/sd" + letter);
        patch(r => r.drives.push(d));
    }
    // The newest drive is pulled out without ejecting.
    function unplug() {
        const list = fxRaw.drives || [];
        if (!list.length) return;
        const d = list[list.length - 1];
        patch(r => {
            r.drives = r.drives.filter(x => x.id !== d.id);
            for (const v of d.volumes) if (v.mount) delete r.usage[v.mount];
        });
    }

    function vol(dev, label, fstype, size, extra) {
        return Object.assign({ "device": dev, "mountDevice": dev, "label": label, "fstype": fstype, "size": size, "mount": "",
                               "encrypted": false, "locked": false, "auto": true, "number": 1, "fill": 0.35 }, extra || {});
    }
    function drv(id, vendor, model, size, kind, dev, vols, extra) {
        return Object.assign({ "id": id, "vendor": vendor, "model": model, "size": size, "bus": kind === "card" ? "sdio" : "usb", "kind": kind,
                               "device": dev, "canPowerOff": kind !== "card", "optical": false, "sortKey": id, "volumes": vols }, extra || {});
    }
    function preset(kind, id, dev) {
        const p1 = dev + "1";
        if (kind === "card") return drv(id, "", "SD64G", 63864569856, "card", "/dev/mmcblk0", [vol("/dev/mmcblk0p1", "EOS_DIGITAL", "vfat", 63863521280, { "fill": 0.62 })]);
        if (kind === "long") return drv(id, "Samsung", "Portable SSD T7 Shield with the long model name the USB bridge reports to UDisks2", 2000398934016, "usb", dev,
                                        [vol(p1, "Photos from the trip to Patagonia with the whole family, summer 2025–26, originals and RAW", "exfat", 2000397885440, { "fill": 0.81 })]);
        if (kind === "locked") return drv(id, "WD", "My Passport 25E2", 4000752599040, "usb", dev, [vol(p1, "", "", 4000751550464, { "encrypted": true, "locked": true })]);
        if (kind === "multi") return drv(id, "Kingston", "DataTraveler Max", 256641603584, "usb", dev, [
            vol(p1, "Ventoy", "exfat", 256607001600, { "fill": 0.68 }),
            vol(dev + "2", "VTOYEFI", "vfat", 33554432, { "number": 2, "auto": false, "fill": 0.9 })]);
        if (kind === "busy") return drv(id, "SanDisk", "Extreme Pro", 128035676160, "usb", dev, [vol(p1, "WORK", "exfat", 128034627584, { "fill": 0.44 })], { "inUse": true });
        return drv(id, "SanDisk", "Ultra", 31914983424, "usb", dev, [vol(p1, "SANDISK", "exfat", 31913934848, { "fill": 0.38 })]);
    }
    function fixtures(name) {
        const micron = { "model": "Micron MTFDKBA1T0TGD-2BK15ABLT", "size": 1024209543168, "bus": "NVMe" };
        const fs = (source, fstype, size, fill, encrypted) => {
            const used = Math.round(size * fill);
            return { "source": source, "fstype": fstype, "size": size, "used": used, "free": size - used, "encrypted": !!encrypted };
        };
        const root_ = { "source": "/dev/mapper/nixos-root", "fstype": "ext4", "size": 938263769088, "used": 162410471424, "free": 728116666368, "encrypted": true };
        const boot = { "source": "/dev/nvme0n1p1", "fstype": "vfat", "size": 1071628288, "used": 42373120, "free": 1029255168, "encrypted": false };
        const mounted = (v, path) => Object.assign(v, { "mount": path });
        // Usage entries for the mounted removable volumes.
        const withUsage = (raw) => {
            for (const d of raw.drives) for (const v of d.volumes) if (v.mount) raw.usage[v.mount] = fxUsage(v);
            return raw;
        };
        const nextMonday = (() => { const t = new Date(); t.setHours(0, 0, 0, 0); t.setDate(t.getDate() + ((8 - t.getDay()) % 7 || 7)); return t.getTime(); })();

        if (name === "empty")
            return { "udisks": true, "disks": [micron], "drives": [], "usage": { "/": root_, "/boot": boot },
                     "trash": { "known": true, "items": 0, "size": 0 },
                     "cleanup": { "known": true, "gc": false, "next": 0, "optimise": false, "generations": 1 }, "state": {} };
        if (name === "stress") {
            const long = "Photos from the trip to Patagonia with the whole family, summer 2025–26, originals and RAW";
            return withUsage({
                "udisks": true,
                "disks": [{ "model": "Samsung SSD 990 PRO with Heatsink 4TB and the long model string its firmware reports", "size": 4000787030016, "bus": "NVMe" },
                          { "model": "WDC WD40EFRX-68N32N0", "size": 4000787030016, "bus": "HDD" }],
                "drives": [
                    drv("t7", "Samsung", "Portable SSD T7 Shield", 2000398934016, "usb", "/dev/sdb",
                        [mounted(vol("/dev/sdb1", long, "exfat", 2000397885440, { "fill": 0.996 }), "/run/media/mariano/" + long)]),
                    drv("kingston", "Kingston", "DataTraveler Max", 256641603584, "usb", "/dev/sdc", [
                        mounted(vol("/dev/sdc1", "Ventoy", "exfat", 255400000000, { "fill": 0.68 }), "/run/media/mariano/Ventoy"),
                        vol("/dev/sdc2", "VTOYEFI", "vfat", 33554432, { "number": 2, "auto": false }),
                        mounted(vol("/dev/sdc3", "nixos-minimal-25.11pre-x86_64-linux", "iso9660", 1207959552, { "number": 3, "fill": 1 }), "/run/media/mariano/nixos-minimal-25.11pre-x86_64-linux")]),
                    drv("passport", "WD", "My Passport 25E2", 4000752599040, "usb", "/dev/sdd", [vol("/dev/sdd1", "", "", 4000751550464, { "encrypted": true, "locked": true })]),
                    drv("lexar", "Lexar", "JumpDrive S47", 64023257088, "usb", "/dev/sde", [mounted(vol("/dev/sde1", "LEXAR", "vfat", 64022208512, { "fill": 0.2 }), "/run/media/mariano/LEXAR")]),
                    drv("extreme", "SanDisk", "Extreme Pro", 128035676160, "usb", "/dev/sdf", [mounted(vol("/dev/sdf1", "WORK", "exfat", 128034627584, { "fill": 0.44 }), "/run/media/mariano/WORK")], { "inUse": true }),
                    drv("card", "", "SD128", 127865454592, "card", "/dev/mmcblk0", [vol("/dev/mmcblk0p1", "EOS_DIGITAL", "vfat", 127864406016)]),
                    drv("generic", "Generic", "Mass Storage Device", 8053063680, "usb", "/dev/sdg", []),
                    drv("jmicron", "JMicron", "Generic USB 3.2 Gen 2x2 NVMe Enclosure With A Model Name Long Enough To Overflow", 1000204886016, "usb", "/dev/sdh",
                        [vol("/dev/sdh1", "", "ntfs", 1000203837440)]),
                    drv("verbatim", "Verbatim", "Store n Go", 16008609792, "usb", "/dev/sdi", [mounted(vol("/dev/sdi1", "VERBATIM", "vfat", 16007561216, { "fill": 0.12 }), "/run/media/mariano/VERBATIM")])
                ],
                "usage": {
                    "/": fs("/dev/mapper/nixos-root", "ext4", 938263769088, 0.993, true),
                    "/home": fs("/dev/mapper/home", "btrfs", 3840000000000, 0.962, true),
                    "/nix": fs("/dev/mapper/nix", "xfs", 512000000000, 0.91, true),
                    "/mnt/archive-of-everything-worth-keeping-including-the-old-laptop-backups-2019-2026": fs("/dev/sda1", "ext4", 4000785960960, 0.55, false),
                    "/boot": fs("/dev/nvme0n1p1", "vfat", 1071628288, 0.985, false)
                },
                "trash": { "known": true, "items": 12847, "size": 48312000000 },
                "cleanup": { "known": true, "gc": true, "next": nextMonday, "optimise": false, "generations": 143 },
                "state": { "busy": { "lexar": "eject" }, "errors": { "extreme": explain("eject", "busy") }, "parked": { "card": true } }
            });
        }
        // normal
        return withUsage({
            "udisks": true, "disks": [micron],
            "drives": [
                drv("sandisk", "SanDisk", "Ultra", 31914983424, "usb", "/dev/sdb", [mounted(vol("/dev/sdb1", "SANDISK", "exfat", 31913934848, { "fill": 0.38 }), "/run/media/mariano/SANDISK")]),
                drv("card", "", "SD64G", 63864569856, "card", "/dev/mmcblk0", [vol("/dev/mmcblk0p1", "EOS_DIGITAL", "vfat", 63863521280, { "fill": 0.62 })])
            ],
            "usage": { "/": root_, "/boot": boot },
            "trash": { "known": true, "items": 42, "size": 1340000000 },
            "cleanup": { "known": true, "gc": true, "next": nextMonday, "optimise": true, "generations": 6 },
            "state": {}
        });
    }

    // ------------------------------------------------------------------ IPC

    function pick(id) { return id ? drive(id) : (drives.length ? drives[drives.length - 1] : null); }
    IpcHandler {
        target: "drives"
        function fixture(name: string): void { root.setFixture(name); }
        function plug(kind: string): void { root.plug(kind); }
        function unplug(): void { root.unplug(); }
        // The newest drive when id is "".
        function eject(id: string): void { const d = root.pick(id); if (d) root.eject(d.id); }
        function open(id: string): void { const d = root.pick(id); if (d) root.open(d.id, ""); }
        function mount(id: string): void { const d = root.pick(id); if (d) root.mount(d.id, ""); }
        function unmount(id: string): void { const d = root.pick(id); if (d) root.unmount(d.id, ""); }
        function emptytrash(): void { root.askEmptyTrash(); }
        function refresh(): void { root.refresh(); root.refreshTrash(); root.refreshCleanup(); }
        function status(): string {
            return JSON.stringify({
                "fixture": root.fixture, "available": root.available,
                "volumes": root.volumes.map(v => v.mount + ": " + root.bytes(v.free) + " free of " + root.bytes(v.size)),
                "drives": root.drives.map(d => ({ "id": d.id, "title": root.title(d), "label": d.label, "device": d.device, "busy": root.busy[d.id] || "",
                                                  "error": root.errors[d.id] || "", "parked": d.parked, "mounts": d.volumes.map(v => v.mount).filter(m => m) })),
                "trash": root.trash, "cleanup": root.cleanup, "emptying": root.emptying
            }, null, 1);
        }
    }
}
