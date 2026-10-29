// Sunrise and sunset for a place and day (NOAA's approximation), in local
// Date objects. Used by Appearance's "Sunset" mode and Night light.
.pragma library

function times(date, lat, lon) {
    const rad = Math.PI / 180;
    const start = new Date(Date.UTC(date.getFullYear(), 0, 1));
    const day = Math.floor((Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()) - start) / 86400000) + 1;
    const g = 2 * Math.PI / 365 * (day - 1);
    const eq = 229.18 * (0.000075 + 0.001868 * Math.cos(g) - 0.032077 * Math.sin(g) - 0.014615 * Math.cos(2 * g) - 0.040849 * Math.sin(2 * g));
    const decl = 0.006918 - 0.399912 * Math.cos(g) + 0.070257 * Math.sin(g) - 0.006758 * Math.cos(2 * g) + 0.000907 * Math.sin(2 * g) - 0.002697 * Math.cos(3 * g) + 0.00148 * Math.sin(3 * g);
    const cosHa = Math.cos(90.833 * rad) / (Math.cos(lat * rad) * Math.cos(decl)) - Math.tan(lat * rad) * Math.tan(decl);
    if (cosHa > 1 || cosHa < -1) return null;            // polar day or night
    const ha = Math.acos(cosHa) / rad;
    const midnight = Date.UTC(date.getFullYear(), date.getMonth(), date.getDate());
    return {
        sunrise: new Date(midnight + (720 - 4 * (lon + ha) - eq) * 60000),
        sunset: new Date(midnight + (720 - 4 * (lon - ha) - eq) * 60000)
    };
}

function isNight(now, lat, lon) {
    const t = times(now, lat, lon);
    if (!t) return false;
    return now < t.sunrise || now >= t.sunset;
}
