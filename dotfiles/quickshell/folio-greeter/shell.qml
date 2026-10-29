//@ pragma Env QSG_RENDER_LOOP=threaded
//@ pragma Env QT_WAYLAND_DISABLE_WINDOWDECORATION=1
//@ pragma UseQApplication
//@ pragma AppId folio-greeter

import QtQuick
import Quickshell
// Folio's own Common, Widgets, Services and shaders: symlinks here, copies in
// the package (modules/nixos/folio-greeter.nix). Quickshell registers a qs.*
// folder only when this file imports it.
import qs.Common
import qs.Services
import qs.Widgets

// Folio's login screen, run by greetd inside a bare niri
// (modules/nixos/folio-greeter.nix). The greeter is one module,
// Modules/Greeter; in scripts/folio-harness it talks to a pretend greetd
// (fixtures) instead of the real socket.
ShellRoot {
    id: shell

    // Installed, it never hot-reloads (a reload mid-login would drop the
    // conversation); the harness keeps live reload for development.
    Component.onCompleted: Quickshell.watchFiles = !!(Quickshell.env("FOLIO_HARNESS") || Quickshell.env("FOLIO_DEV"))

    LazyLoader {
        active: true
        source: Qt.resolvedUrl("Modules/Greeter/Greeter.qml")
    }
}
