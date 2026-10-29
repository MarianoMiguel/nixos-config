pragma Singleton
import QtQuick
import Quickshell

// The keyboard in Folio's own surfaces. `keyboard` turns true when a key
// moves or presses something in a Folio surface and false again when the
// pointer moves over one (PointerWatch), so focus rings (FocusRing) show for
// the keyboard only. Keys only ever reach a surface while it holds keyboard
// focus, so nothing here takes keys from apps.
//
// A focusable control sets activeFocusOnTab, draws a FocusRing and hands its
// key presses here first:
//   Keys.onPressed: event => KeyNav.press(event, () => root.clicked())
// Surfaces that move focus with the arrows (the sidebar) use step() and
// vertical() over focusables(scope).
Singleton {
    id: root

    property bool keyboard: false
    function key() { if (!keyboard) keyboard = true; }
    function pointer() { if (keyboard) keyboard = false; }

    function plain(e) { return !(e.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)); }
    // Space, Return and Enter press the focused control.
    function activates(e) { return plain(e) && (e.key === Qt.Key_Space || e.key === Qt.Key_Return || e.key === Qt.Key_Enter); }
    // Shift+F10 or the Menu key open the focused item's menu.
    function opensMenu(e) { return e.key === Qt.Key_Menu || (e.key === Qt.Key_F10 && (e.modifiers & Qt.ShiftModifier)); }

    // For a control's Keys.onPressed: notes the keyboard, and Space or Enter
    // runs `act` (once: a held key does not repeat it). Every other key goes
    // on, so Tab still moves focus and the window still sees Escape.
    function press(e, act) {
        key();
        if (act && activates(e)) {
            if (!e.isAutoRepeat) act();
            e.accepted = true;
        }
    }

    // The focusable items under `scope` in reading order: the item tree, the
    // order Tab follows. Hidden and disabled branches are skipped.
    function focusables(scope) {
        const out = [];
        const walk = it => {
            if (!it || !it.visible || !it.enabled) return;
            if (it !== scope && it.activeFocusOnTab) out.push(it);
            const kids = it.children;
            for (let i = 0; i < kids.length; i++) walk(kids[i]);
        };
        walk(scope);
        return out;
    }
    function rect(it, scope) {
        const p = it.mapToItem(scope, 0, 0);
        return { "x": p.x, "y": p.y, "w": it.width, "h": it.height };
    }
    // The next (dir 1) or previous (dir -1) focusable in reading order; the
    // first or last when nothing under scope has focus; null past the ends.
    function step(scope, from, dir) {
        const all = focusables(scope);
        if (!all.length) return null;
        const i = from ? all.indexOf(from) : -1;
        if (i < 0) return dir > 0 ? all[0] : all[all.length - 1];
        return all[i + dir] || null;
    }
    // The nearest focusable below (dir 1) or above (dir -1): the closest row
    // that starts past this item's edge, then the closest in it across.
    function vertical(scope, from, dir) {
        const all = focusables(scope);
        if (!from || all.indexOf(from) < 0) return null;
        const r = rect(from, scope);
        const gap = c => dir > 0 ? c.y - (r.y + r.h) : r.y - (c.y + c.h);
        const cands = all.filter(i => i !== from).map(i => ({ "i": i, "r": rect(i, scope) })).filter(c => gap(c.r) > -6);
        if (!cands.length) return null;
        const near = Math.min.apply(null, cands.map(c => gap(c.r)));
        const cx = r.x + r.w / 2;
        const row = cands.filter(c => gap(c.r) <= near + 10);
        row.sort((a, b) => Math.abs(a.r.x + a.r.w / 2 - cx) - Math.abs(b.r.x + b.r.w / 2 - cx));
        return row[0].i;
    }
    // The contentY that brings `item` into view inside `flick`, with a margin;
    // the current one when it is already in view.
    function scrollFor(flick, item, margin) {
        const m = margin === undefined ? 16 : margin;
        const p = item.mapToItem(flick.contentItem, 0, 0);
        let y = flick.contentY;
        if (p.y - m < y) y = p.y - m;
        else if (p.y + item.height + m > y + flick.height) y = Math.min(p.y - m, p.y + item.height + m - flick.height);
        return Math.max(0, Math.min(y, flick.contentHeight - flick.height));
    }
    // Whether `item` sits inside `scope`.
    function inside(item, scope) {
        for (let it = item; it; it = it.parent) if (it === scope) return true;
        return false;
    }
}
