.pragma library

// Test content for the sidebar (IPC: sidebar fixture normal|stress|empty).
// Plain data shaped like Feed's live values; times are relative to `now` so
// "in 18m" and "2 min" read the same whenever a test runs.

function hm(ms) {
    const d = new Date(ms);
    return String(d.getHours()).padStart(2, "0") + ":" + String(d.getMinutes()).padStart(2, "0");
}
function ymd(ms) {
    const d = new Date(ms);
    return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0");
}
function event(now, minutesFromNow, length, title, location) {
    const at = now + minutesFromNow * 60000;
    return { "date": ymd(at), "start": hm(at), "end": hm(at + length * 60000), "allDay": false, "title": title, "location": location || "", "at": at };
}
// A day this month at 10:00, for calendar dots.
function onDay(now, day, title) {
    const d = new Date(now);
    const at = new Date(d.getFullYear(), d.getMonth(), day, 10, 0).getTime();
    return { "date": ymd(at), "start": "10:00", "end": "11:00", "allDay": false, "title": title, "location": "", "at": at };
}
function note(id, summary, body, ago, actions) {
    return { "id": id, "summary": summary, "body": body, "ago": ago, "image": "", "icon": "", "actions": (actions || []).map(a => ({ "text": a })), "hasDefault": false };
}
function group(app, count, items) {
    return { "app": app, "icon": "", "count": count, "items": items };
}
function nextWeekday(now, day, hour) {
    const d = new Date(now);
    d.setDate(d.getDate() + ((day - d.getDay() + 7) % 7 || 7));
    d.setHours(hour, 0, 0, 0);
    return d.getTime();
}

function make(name, now, place) {
    const town = (place && place[0]) || "Campana";
    const today = new Date(now).getDate();
    const days = new Date(new Date(now).getFullYear(), new Date(now).getMonth() + 1, 0).getDate();
    const later = d => Math.min(days, today + d);

    if (name === "stress") {
        const long = "Quarterly planning with product, design, engineering and the extended leadership team (mandatory, cameras on)";
        const events = [event(now, -5, 510, long, "Sala Grande del tercer piso, edificio norte · 14 guests")];
        for (let i = 1; i <= 10; i++) events.push(event(now, 20 + i * 25, 20, "Back-to-back sync " + i + " about the migration of the billing service", ""));
        [3, 12, later(2), later(5)].forEach(d => events.push(onDay(now, d, "Busy")));
        return {
            "weather": "San Carlos de Bariloche · −4° · snow showers",
            "wifi": { "on": true, "ssid": "Starbucks Guest WiFi 5GHz — Captive portal sign-in required", "signal": 31, "wired": false, "networks": [
                { "ssid": "Starbucks Guest WiFi 5GHz — Captive portal sign-in required", "signal": 31, "secure": false, "active": true },
                { "ssid": "Fibertel WiFi843 2.4GHz Departamento 4B Torre Norte Edificio Las Acacias", "signal": 74, "secure": true, "active": false },
                { "ssid": "DIRECT-7F-HP OfficeJet Pro 9025e Printer", "signal": 60, "secure": true, "active": false },
                { "ssid": "Personal-Wifi-3F2", "signal": 48, "secure": true, "active": false },
                { "ssid": "Claro_5G_ABC123", "signal": 40, "secure": true, "active": false },
                { "ssid": "Telecentro-9b21", "signal": 33, "secure": true, "active": false },
                { "ssid": "iPhone de Lucía", "signal": 28, "secure": true, "active": false },
                { "ssid": "Movistar Fibra Óptica 600 Mbps Simétrico", "signal": 21, "secure": true, "active": false },
                { "ssid": "Free public WiFi", "signal": 12, "secure": false, "active": false },
                { "ssid": "eduroam", "signal": 9, "secure": true, "active": false }] },
            "bt": { "available": true, "on": true, "summary": "3 devices", "devices": [
                { "name": "Sony WH-1000XM5 Wireless Noise Cancelling Headphones", "connected": true, "battery": 0.12, "busy": false },
                { "name": "Logitech MX Master 3S for Business (Bolt receiver)", "connected": true, "battery": 0.55, "busy": false },
                { "name": "Keychron K3 Ultra-slim Wireless Mechanical Keyboard", "connected": true, "battery": -1, "busy": false },
                { "name": "AirPods Pro de Lucía Fernández", "connected": false, "battery": -1, "busy": true },
                { "name": "JBL Flip 6", "connected": false, "battery": -1, "busy": false },
                { "name": "Pixel Watch 2", "connected": false, "battery": -1, "busy": false }] },
            "focus": { "active": true, "ends": now + (24 * 60 + 12) * 1000, "duration": 1500 },
            "vpn": { "available": true, "on": true, "summary": "214 peers", "canToggle": true, "busy": false },
            "awake": true,
            "night": { "available": true, "on": true },
            "volume": 1, "muted": false, "brightness": 0.02,
            "outputs": [
                { "name": "Sony WH-1000XM5 Wireless Noise Cancelling Headphones (A2DP Sink, codec LDAC)", "current": true },
                { "name": "Built-in Audio Analog Stereo", "current": false },
                { "name": "HDMI / DisplayPort 3 Output — LG Electronics 27UK850 Ultra HD 4K Monitor", "current": false }],
            "device": "Sony WH-1000XM5 Wireless Noise Cancelling Headphones", "deviceBt": true,
            "media": { "active": true, "playing": true, "art": "",
                "title": "Adiós Nonino (Live at the Teatro Colón, Buenos Aires — 40th Anniversary Remaster, Extended Version)",
                "artist": "Astor Piazzolla y su Quinteto Nuevo Tango with the Orquesta Filarmónica de Buenos Aires",
                "length": 5999, "position": 5940, "canSeek": true, "resume": null },
            "cities": [["Campana", "America/Argentina/Buenos_Aires"], ["Santa Cruz de la Sierra", "America/La_Paz"], ["Llanfairpwllgwyngyll", "Europe/London"], ["Kathmandu", "Asia/Kathmandu"], ["Chatham Islands", "Pacific/Chatham"]],
            "calendar": { "connected": true, "events": events },
            "quota": [
                { "name": "Claude", "window": "5 h", "used": 1, "resetsAt": now + 95 * 60000 },
                { "name": "Claude", "window": "week", "used": 0.97, "resetsAt": nextWeekday(now, 1, 9) },
                { "name": "Fable", "window": "week", "used": 1.04, "resetsAt": nextWeekday(now, 1, 9) },
                { "name": "Codex", "window": "5 h", "used": 0.61, "resetsAt": now + 40 * 60000 }],
            "groups": [
                group("Slack — #infra-alerts-production-eu-west-1-critical", 134, [
                    note("s1", "[FIRING:3] KubePodCrashLooping production/payments-api", "KubePodCrashLooping production/payments-api-7d9f8b6c5d-x2k9q container payments-api is restarting 14 times in the last 10 minutes; see runbook https://runbooks.internal.example/payments-api/crashloop", "now", ["Open runbook", "Acknowledge", "Silence for one hour"]),
                    note("s2", "[RESOLVED] HighMemoryUsage production/search-indexer", "Memory usage back under 80% on all 12 replicas of search-indexer in eu-west-1.", "3 min"),
                    note("s3", "[FIRING:1] CertificateExpiringSoon", "TLS certificate for api.example.com expires in 6 days.", "11 min")]),
                group("Signal", 12, [
                    note("l1", "Lucía Fernández de la Torre y Mendizábal", "Mirá, te mando el audio de nuevo porque el anterior se cortó justo cuando te contaba lo del departamento de Palermo y la reunión del jueves con la inmobiliaria", "4 min", ["Reply", "Mark as read"]),
                    note("l2", "Lucía Fernández de la Torre y Mendizábal", "¿Lo escuchaste?", "6 min")]),
                group("Calendar", 3, [note("c1", "Quarterly planning starts now", "Quarterly planning with product, design, engineering and the extended leadership team starts now in Sala Grande del tercer piso, edificio norte", "9 min", ["Join", "Snooze"])]),
                group("GitHub", 27, [note("g1", "Review requested on #4821", "folio: sidebar module, weather, quota and calendar services, fixtures for every card", "1 h")]),
                group("Thunderbird", 8, [note("m1", "Re: Re: Fwd: Invoice", "Adjunto la factura corregida.", "2 h")]),
                group("Software Updates", 1, [note("u1", "nixos-unstable", "412 packages can be updated.", "3 h")]),
                group("Tailscale", 2, [note("t1", "Exit node offline", "balerion has not been seen for 2 days.", "5 h")])],
            "since": "",
            "battery": { "present": true, "percent": 6, "label": "Battery low · 14 m left", "low": true, "charging": false }
        };
    }
    if (name === "empty") {
        return {
            "weather": town,
            "wifi": { "on": true, "ssid": "", "signal": 0, "wired": false, "networks": [] },
            "bt": { "available": true, "on": true, "summary": "On", "devices": [] },
            "focus": { "active": false, "ends": 0, "duration": 1500 },
            "vpn": { "available": true, "on": false, "summary": "Off", "canToggle": true, "busy": false },
            "awake": false,
            "night": { "available": false, "on": false },
            "volume": 0, "muted": true, "brightness": 1,
            "outputs": [{ "name": "Built-in Audio Analog Stereo", "current": true }],
            "device": "Built-in Audio Analog Stereo", "deviceBt": false,
            "media": { "active": false, "playing": false, "art": "", "title": "", "artist": "", "length": 0, "position": 0, "canSeek": false,
                "resume": { "title": "Libertango", "artist": "Astor Piazzolla" } },
            "cities": [["Campana", "America/Argentina/Buenos_Aires"]],
            "calendar": { "connected": true, "events": [] },
            "quota": [
                { "name": "Claude", "window": "5 h", "used": 0, "resetsAt": 0 },
                { "name": "Codex", "window": "5 h", "used": 0, "resetsAt": 0 }],
            "groups": [],
            "since": "14:02",
            "battery": { "present": true, "percent": 100, "label": "Charged", "low": false, "charging": false }
        };
    }
    // normal
    return {
        "weather": town + " · 19° · clear",
        "wifi": { "on": true, "ssid": "Bonhart 5G", "signal": 82, "wired": false, "networks": [
            { "ssid": "Bonhart 5G", "signal": 82, "secure": true, "active": true },
            { "ssid": "Bonhart", "signal": 64, "secure": true, "active": false },
            { "ssid": "Fibertel WiFi843 2.4GHz", "signal": 41, "secure": true, "active": false },
            { "ssid": "Café Martínez", "signal": 22, "secure": false, "active": false }] },
        "bt": { "available": true, "on": true, "summary": "AirPods Pro", "devices": [
            { "name": "AirPods Pro", "connected": true, "battery": 0.8, "busy": false },
            { "name": "MX Master 3S", "connected": false, "battery": -1, "busy": false }] },
        "focus": { "active": false, "ends": 0, "duration": 1500 },
        "vpn": { "available": true, "on": false, "summary": "Off", "canToggle": true, "busy": false },
        "awake": false,
        "night": { "available": false, "on": false },
        "volume": 0.64, "muted": false, "brightness": 0.78,
        "outputs": [
            { "name": "AirPods Pro", "current": true },
            { "name": "Built-in Audio Analog Stereo", "current": false }],
        "device": "AirPods Pro", "deviceBt": true,
        "media": { "active": true, "playing": true, "art": "", "title": "Libertango", "artist": "Astor Piazzolla",
            "length": 233, "position": 82, "canSeek": true, "resume": null },
        "cities": [["Campana", "America/Argentina/Buenos_Aires"], ["New York", "America/New_York"], ["Los Angeles", "America/Los_Angeles"], ["Sydney", "Australia/Sydney"]],
        "calendar": { "connected": true, "events": [
            event(now, -180, 30, "Standup", ""),
            event(now, 18, 45, "Workshop review", "with Lucía"),
            event(now, 120, 30, "Call with the bank", ""),
            onDay(now, 3, "Dentist"), onDay(now, 12, "Lucía's birthday"), onDay(now, later(2), "Ship the sidebar"), onDay(now, later(5), "Asado")] },
        "quota": [
            { "name": "Claude", "window": "5 h", "used": 0.42, "resetsAt": now + 130 * 60000 },
            { "name": "Claude", "window": "week", "used": 0.68, "resetsAt": nextWeekday(now, 1, 9) },
            { "name": "Codex", "window": "5 h", "used": 0.18, "resetsAt": now + 55 * 60000 }],
        "groups": [group("Signal", 2, [
            note("n1", "Lucía", "¿Mate a las cinco? Llevo facturas.", "2 min", ["Reply"]),
            note("n2", "Lucía", "¿Estás en casa?", "9 min")])],
        "since": "",
        "battery": { "present": true, "percent": 84, "label": "3 h 20 m left", "low": false, "charging": false }
    };
}
