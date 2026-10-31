pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common

// This computer and the software it runs, for Settings › About: read once
// per visit with one probe (hostnamectl, DMI and udev's memory table,
// /proc, lspci, df, nixos-version, the system profile's generation, niri,
// Quickshell, mariano-shell). Read only; copy() puts a plain-text summary
// on the clipboard through Sys.run (recorded in the harness).
//
// IPC `about`: fixture normal|stress|empty ("" for live), refresh, copy,
// summary.
Singleton {
    id: root

    property var live: ({})
    property bool loaded: false
    property var fx: null
    property string fixture: ""
    readonly property var info: fx || live
    // The battery line: Battery's, or the fixture's own (its desktops have none).
    readonly property var battery: fx ? (fx.battery || { "present": false }) : Battery.info

    function refresh() { if (!probe.running) probe.running = true; }

    // ------------------------------------------------------------ words

    // Memory in binary units, disks in decimal ones, as macOS and GNOME do.
    function gib(bytes) {
        if (!(bytes > 0)) return "";
        const g = bytes / 1073741824;
        return (g >= 10 ? Math.round(g) : Math.round(g * 10) / 10) + " GB";
    }
    function size(bytes) {
        if (!(bytes > 0)) return "";
        const units = [[1e12, "TB"], [1e9, "GB"], [1e6, "MB"], [1e3, "KB"]];
        for (const u of units) if (bytes >= u[0]) {
            const v = bytes / u[0];
            return (v >= 100 ? Math.round(v) : v >= 10 ? Math.round(v * 10) / 10 : Math.round(v * 100) / 100) + " " + u[1];
        }
        return bytes + " B";
    }
    function uptime(ms) {
        if (!(ms > 0)) return "";
        const m = Math.floor(ms / 60000), h = Math.floor(m / 60), d = Math.floor(h / 24);
        if (d >= 2) return d + " days" + (d < 10 && h % 24 ? ", " + (h % 24) + " h" : "");
        if (h > 0) return h + " h " + (m % 60) + " m";
        return Math.max(1, m) + " m";
    }
    function date(ms) { return ms > 0 ? Qt.formatDateTime(new Date(ms), "d MMM yyyy, HH:mm") : ""; }
    function ago(ms) {
        if (!(ms > 0)) return "";
        const d = Math.floor((Date.now() - ms) / 86400000);
        return d <= 0 ? "today" : d === 1 ? "yesterday" : d + " days ago";
    }

    // "Lenovo ThinkPad P14s Gen 6 AMD".
    readonly property string model: info.vendor && info.model && info.model.indexOf(info.vendor) !== 0 ? info.vendor + " " + info.model : (info.model || info.vendor || "")
    readonly property string processor: (info.cpu || {}).name || ""
    readonly property string processorLine: {
        const c = info.cpu || {}, bits = [];
        if (c.cores > 0) bits.push(c.cores + (c.cores === 1 ? " core" : " cores"));
        if (c.threads > 0 && c.threads !== c.cores) bits.push(c.threads + " threads");
        if (c.ghz > 0) bits.push("up to " + c.ghz.toFixed(1) + " GHz");
        return bits.join(" · ");
    }
    readonly property string memory: {
        const m = info.memory || {};
        const total = m.installed > 0 ? m.installed : m.usable;
        if (!(total > 0)) return "";
        return gib(total) + (m.type ? " " + m.type : "") + (m.speed > 0 ? " · " + m.speed + " MT/s" : "");
    }
    readonly property string memoryLine: {
        const m = info.memory || {};
        if (!(m.usable > 0) || !(m.installed > 0)) return "";
        return gib(m.usable) + " usable" + (m.installed - m.usable > 1073741824 ? ", the rest reserved for graphics and firmware" : "");
    }
    readonly property string nixos: (info.nixos || {}).version ? "NixOS " + info.nixos.version + (info.nixos.codename ? " (" + info.nixos.codename + ")" : "") : ""
    readonly property string shellName: (info.folio || {}).version ? "Folio " + info.folio.version : "Folio (development)"
    readonly property string shellLine: {
        const f = info.folio || {}, s = info.shell || {};
        const from = f.version ? "" : f.revision ? "running from checkout " + f.revision : "running from a checkout";
        const pick = !s.installed ? "mariano-shell is not installed"
                   : s.choice === "dms" ? "DMS starts at the next login"
                   : s.choice ? "Starts at login (mariano-shell)" : "";
        return [from, pick].filter(x => x).join(" · ");
    }
    readonly property string diskLine: {
        const d = info.disk || {};
        return d.size > 0 ? size(d.used) + " of " + size(d.size) + " used" : "";
    }

    // The plain-text summary copy() puts on the clipboard.
    function summary() {
        const i = info, lines = [];
        const add = (k, v) => { if (v) lines.push(k + ": " + v); };
        lines.push((i.hostname || "This computer") + (model ? " — " + model : ""));
        add("Processor", processor + (processorLine ? " (" + processorLine + ")" : ""));
        add("Memory", memory + (memoryLine ? " (" + gib((i.memory || {}).usable) + " usable)" : ""));
        for (const g of (i.gpus || [])) add("Graphics", g.name + (g.vram > 0 ? " (" + gib(g.vram) + ")" : ""));
        add("Storage", diskLine ? diskLine + " on " + (i.disk.mount || "/") : "");
        if (i.firmware && i.firmware.version) add("Firmware", [i.firmware.vendor, i.firmware.version, i.firmware.date > 0 ? Qt.formatDate(new Date(i.firmware.date), "yyyy-MM-dd") : ""].filter(x => x).join(" "));
        add("OS", "Interstellar (" + (Theme.lumen ? "Lumen" : "Folio") + ") on " + (nixos || "NixOS"));
        if (i.generation && i.generation.number > 0) add("Generation", i.generation.number + (i.generation.time > 0 ? " (" + Qt.formatDateTime(new Date(i.generation.time), "yyyy-MM-dd HH:mm") + ")" : ""));
        add("Kernel", i.kernel ? "Linux " + i.kernel : "");
        add("niri", i.niri);
        add("Quickshell", (i.quickshell || {}).version ? i.quickshell.version + (i.quickshell.revision ? " (" + i.quickshell.revision + ")" : "") : "");
        add("Shell", shellName + (shellLine ? " (" + shellLine + ")" : ""));
        add("Uptime", uptime(Date.now() - (i.bootTime || 0)));
        const b = battery;
        if (b && b.present) {
            const h = Battery.health(b);
            add("Battery", b.percent + "%" + (h > 0 ? ", " + h + "% health" : "") + (b.cycles > 0 ? ", " + b.cycles + " cycles" : ""));
        }
        return lines.join("\n").replace(/ · /g, ", ");
    }
    function copy() {
        const text = summary();
        Sys.run(["wl-copy", "--", text]);
        Toasts.show("System summary copied", { "icon": "check" });
    }

    // ------------------------------------------------------------ probe

    Process {
        id: probe
        command: ["sh", "-c", `
            echo "hostnamectl=$(hostnamectl --json=short 2>/dev/null)"
            echo "hostname=$(cat /proc/sys/kernel/hostname 2>/dev/null)"
            for f in sys_vendor product_name product_version chassis_type bios_vendor bios_version bios_date; do
                echo "dmi_$f=$(cat /sys/class/dmi/id/$f 2>/dev/null)"
            done
            echo "cpu=$(sed -n 's/^model name[[:space:]]*: //p' /proc/cpuinfo | head -n1)"
            echo "threads=$(nproc 2>/dev/null)"
            echo "cores=$(lscpu -p=core,socket 2>/dev/null | grep -v '^#' | sort -u | wc -l)"
            echo "cpumax=$(cat /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq 2>/dev/null)"
            echo "memtotal=$(sed -n 's/^MemTotal: *//p' /proc/meminfo | cut -d' ' -f1)"
            udevadm info -q property /sys/devices/virtual/dmi/id 2>/dev/null | grep -E '^MEMORY_DEVICE_[0-9]+_(SIZE|TYPE|SPEED_MTS|CONFIGURED_SPEED_MTS)=' | sed 's/^/mem_/'
            lspci -mm 2>/dev/null | grep -E '"(VGA compatible controller|Display controller|3D controller)"' | sed 's/^/gpu=/'
            for c in /sys/class/drm/card[0-9]*; do [ -r "$c/device/mem_info_vram_total" ] && echo "vram=$(cat "$c/device/mem_info_vram_total")"; done
            echo "disk=$(df -B1 --output=size,used,avail,target / 2>/dev/null | tail -n1)"
            echo "nixos=$(nixos-version --json 2>/dev/null)"
            g=$(readlink /nix/var/nix/profiles/system 2>/dev/null)
            echo "generation=$g"
            [ -n "$g" ] && echo "generation_time=$(stat -c %Y "/nix/var/nix/profiles/$g" 2>/dev/null)"
            echo "kernel=$(uname -r)"
            echo "niri=$(niri --version 2>/dev/null | head -n1)"
            echo "quickshell=$(qs --version 2>/dev/null | head -n1)"
            command -v mariano-shell >/dev/null 2>&1 && echo "shell=$(mariano-shell which 2>/dev/null)"
            echo "uptime=$(cut -d' ' -f1 /proc/uptime)"
            d=$(readlink -f "$0")
            v=$(printf %s "$d" | grep -o -- '^/nix/store/[a-z0-9]*-folio-shell-[^/]*' | cut -d- -f4-)
            echo "folio_version=$v"
            [ -z "$v" ] && command -v git >/dev/null 2>&1 && echo "folio_rev=$(git -C "$d" log -1 --format='%h' 2>/dev/null)"
            true`, String(Quickshell.shellDir).replace(/^file:\/\//, "")]
        stdout: StdioCollector { onStreamFinished: root.parse(text) }
    }

    function parse(text) {
        const kv = {}, multi = { "gpu": [], "vram": [] };
        for (const line of text.split("\n")) {
            const at = line.indexOf("=");
            if (at <= 0) continue;
            const k = line.slice(0, at), v = line.slice(at + 1).trim();
            if (multi[k]) multi[k].push(v); else kv[k] = v;
        }
        let hn = {};
        try { hn = JSON.parse(kv.hostnamectl || "{}") || {}; } catch (e) {}
        let nx = {};
        try { nx = JSON.parse(kv.nixos || "{}") || {}; } catch (e) {}
        const num = s => { const n = Number(s); return isFinite(n) ? n : 0; };

        // Memory: the modules udev read from DMI, else what the kernel has.
        let installed = 0, type = "", speed = 0;
        for (const k of Object.keys(kv)) {
            const m = /^mem_MEMORY_DEVICE_\d+_(SIZE|TYPE|SPEED_MTS|CONFIGURED_SPEED_MTS)$/.exec(k);
            if (!m) continue;
            if (m[1] === "SIZE") installed += num(kv[k]);
            else if (m[1] === "TYPE" && kv[k] !== "Unknown") type = kv[k];
            else if (m[1] === "CONFIGURED_SPEED_MTS") speed = num(kv[k]) || speed;
            else if (m[1] === "SPEED_MTS" && !speed) speed = num(kv[k]);
        }

        // Graphics: lspci -mm's quoted fields; "Advanced Micro Devices, Inc.
        // [AMD/ATI]" "Strix [Radeon 880M / 890M]" reads "AMD Radeon 880M / 890M".
        const gpus = multi.gpu.map((line, i) => {
            const f = (line.match(/"[^"]*"/g) || []).map(s => s.slice(1, -1));
            const vendor = f[1] || "", device = f[2] || "";
            const br = s => (/\[([^\]]+)\]/.exec(s) || [])[1] || "";
            const name = br(device) || device;
            let short = (br(vendor) || vendor.split(/[ ,]/)[0] || "").split("/")[0];
            if (/^NVIDIA/i.test(vendor)) short = "NVIDIA";
            if (/^Intel/i.test(vendor)) short = "Intel";
            return { "name": name.toLowerCase().indexOf(short.toLowerCase()) === 0 ? name : (short + " " + name).trim(), "vram": i < multi.vram.length ? num(multi.vram[i]) : 0 };
        });

        const disk = (kv.disk || "").split(/\s+/);
        const qs = /^Quickshell\s+(\S+)(?:\s+\(revision\s+([0-9a-f]{7})[0-9a-f]*)?/.exec(kv.quickshell || "") || [];
        const gen = /system-(\d+)-link/.exec(kv.generation || "");
        const ver = nx.nixosVersion || (/^VERSION_ID=(.*)$/m.exec((hn.OperatingSystemReleaseData || []).join("\n")) || [])[1] || "";
        const code = (/^VERSION_CODENAME=(.*)$/m.exec((hn.OperatingSystemReleaseData || []).join("\n")) || [])[1] || "";
        const chassis = hn.Chassis || ({ "8": "laptop", "9": "laptop", "10": "laptop", "14": "laptop", "31": "convertible", "32": "convertible", "3": "desktop", "4": "desktop", "6": "desktop", "7": "desktop", "13": "desktop", "35": "desktop" })[kv.dmi_chassis_type] || "";

        root.live = {
            "hostname": hn.StaticHostname || hn.Hostname || kv.hostname || "",
            "prettyName": hn.PrettyHostname || "",
            "vendor": hn.HardwareVendor || (kv.dmi_sys_vendor && kv.dmi_sys_vendor !== "To Be Filled By O.E.M." ? kv.dmi_sys_vendor : ""),
            "model": hn.HardwareModel || kv.dmi_product_version || kv.dmi_product_name || "",
            "chassis": chassis,
            "cpu": { "name": (kv.cpu || "").replace(/\(R\)|\(TM\)/g, "").replace(/\s+/g, " ").trim(), "cores": num(kv.cores), "threads": num(kv.threads), "ghz": num(kv.cpumax) / 1e6 },
            "memory": { "installed": installed, "usable": num(kv.memtotal) * 1024, "type": type, "speed": speed },
            "gpus": gpus,
            "disk": { "size": num(disk[0]), "used": num(disk[1]), "avail": num(disk[2]), "mount": disk[3] || "/" },
            "firmware": { "vendor": hn.FirmwareVendor || kv.dmi_bios_vendor || "", "version": (hn.FirmwareVersion || kv.dmi_bios_version || "").replace(/\s+\)/, ")").trim(),
                          "date": hn.FirmwareDate ? hn.FirmwareDate / 1000 : 0 },
            "nixos": { "version": ver, "codename": code.charAt(0).toUpperCase() + code.slice(1), "revision": (nx.nixpkgsRevision || "").slice(0, 7) },
            "generation": { "number": gen ? num(gen[1]) : 0, "time": num(kv.generation_time) * 1000 },
            "kernel": kv.kernel || hn.KernelRelease || "",
            "niri": (kv.niri || "").replace(/^niri\s+/, ""),
            "quickshell": { "version": qs[1] || "", "revision": qs[2] || "" },
            "shell": { "installed": kv.shell !== undefined, "choice": kv.shell || "" },
            "folio": { "version": kv.folio_version || "", "revision": kv.folio_rev || "" },
            "bootTime": Date.now() - num(kv.uptime) * 1000
        };
        root.loaded = true;
    }

    // ------------------------------------------------------------ fixtures

    function fixtureData(name) {
        const now = Date.now();
        if (name === "normal") return {
            "hostname": "bonhart", "prettyName": "", "vendor": "Lenovo", "model": "ThinkPad P14s Gen 6 AMD", "chassis": "laptop",
            "cpu": { "name": "AMD Ryzen AI 9 HX PRO 370 w/ Radeon 890M", "cores": 12, "threads": 24, "ghz": 5.16 },
            "memory": { "installed": 68719476736, "usable": 58588618752, "type": "DDR5", "speed": 5600 },
            "gpus": [{ "name": "AMD Radeon 880M / 890M", "vram": 8589934592 }],
            "disk": { "size": 938263769088, "used": 162410176512, "avail": 728116961280, "mount": "/" },
            "firmware": { "vendor": "LENOVO", "version": "R2XET39W (1.19)", "date": 1773878400000 },
            "nixos": { "version": "26.05.20260910.d58a46e", "codename": "Yarara", "revision": "d58a46e" },
            "generation": { "number": 44, "time": now - 2 * 86400000 - 3 * 3600000 },
            "kernel": "6.18.50", "niri": "26.04 (Nixpkgs)",
            "quickshell": { "version": "0.3.1", "revision": "2d3b3e9" },
            "shell": { "installed": true, "choice": "folio" },
            "folio": { "version": "0.1.0", "revision": "" },
            "bootTime": now - (3 * 3600 + 5 * 60) * 1000,
            "battery": { "present": true, "percent": 64, "energyFull": 48.9, "energyDesign": 57.0, "cycles": 111 }
        };
        if (name === "stress") return {
            "hostname": "render-farm-node-with-an-absurdly-long-hostname-for-the-third-floor-lab-07",
            "prettyName": "", "vendor": "Micro-Star International Co., Ltd.",
            "model": "MS-7E06 MAG Z790 TOMAHAWK MAX WIFI DDR5 (MS-7E06) Version 1.0 Special Edition for System Integrators", "chassis": "desktop",
            "cpu": { "name": "13th Gen Intel Core i9-13900KS Processor with an Engineering Sample Microcode Revision Label", "cores": 24, "threads": 32, "ghz": 6.0 },
            "memory": { "installed": 206158430208, "usable": 202937204736, "type": "DDR5", "speed": 6400 },
            "gpus": [{ "name": "NVIDIA GeForce RTX 4090 Founders Edition (AD102 Ada Lovelace, 24 GB GDDR6X, Max-Q disabled)", "vram": 25769803776 },
                     { "name": "Intel Raptor Lake-S GT1 UHD Graphics 770", "vram": 0 }],
            "disk": { "size": 1999844147200, "used": 1979845705728, "avail": 19998441472, "mount": "/" },
            "firmware": { "vendor": "American Megatrends International, LLC.", "version": "A.G0 (BETA, do not ship) build 2026-07-31 rev 99", "date": 1785456000000 },
            "nixos": { "version": "26.11pre912345.0123abc-dirty-local-overlay-with-patches", "codename": "Zebrafinch-Unreleased-Development-Branch", "revision": "0123abc" },
            "generation": { "number": 1287, "time": now - 412 * 86400000 },
            "kernel": "6.19.0-rc7-next-20261028-custom-preempt-rt-debug-kasan-lockdep",
            "niri": "26.10-unstable-2026-10-27 (a1b2c3d4e5f6, built from a local checkout with patches)",
            "quickshell": { "version": "0.3.1-unstable-2026-10-28-with-a-long-suffix", "revision": "2d3b3e9" },
            "shell": { "installed": true, "choice": "dms" },
            "folio": { "version": "", "revision": "4f2c1a9" },
            "bootTime": now - 412 * 86400000 - 7 * 3600000
        };
        if (name === "empty") return {
            "hostname": "", "prettyName": "", "vendor": "", "model": "", "chassis": "desktop",
            "cpu": {}, "memory": {}, "gpus": [], "disk": {}, "firmware": {}, "nixos": {}, "generation": {},
            "kernel": "", "niri": "", "quickshell": {}, "shell": { "installed": false, "choice": "" }, "folio": {}, "bootTime": 0
        };
        return null;
    }
    function setFixture(name) {
        fx = fixtureData(name);
        fixture = fx ? name : "";
        if (!fx && !loaded) refresh();
    }

    IpcHandler {
        target: "about"
        function fixture(name: string): void { root.setFixture(name); }
        function refresh(): void { root.refresh(); }
        function copy(): void { root.copy(); }
        function summary(): string { return root.summary(); }
    }
}
