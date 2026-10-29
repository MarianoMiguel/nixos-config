pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// The fingerprint reader as the lock and polkit can use it: prints enrolled
// for this user (fprintd-list) and pam_fprintd in the system's PAM stacks.
// The lock authenticates fingerprints in a context of their own: the
// system's folio-fprint service when there is one, else a fingerprint-only
// service written to the runtime directory from the system's own module.
// The harness never probes; fixtures pin `forced`.
Singleton {
    id: root

    readonly property bool harness: (Quickshell.env("FOLIO_HARNESS") || "") !== ""
    property var forced: null               // true / false pins it (fixtures)
    property bool enrolled: false
    property bool inLogin: false            // pam_fprintd in login or swaylock
    property bool inPolkit: false           // pam_fprintd in polkit-1
    property string config: ""              // PAM service for the lock's context
    property string configDirectory: ""

    readonly property bool lockReady: forced !== null ? forced : enrolled && inLogin && config !== ""
    readonly property bool polkitReady: forced !== null ? forced : enrolled && inPolkit

    readonly property string runtimeDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/folio/pam"

    function probe() { if (!harness) probeProc.running = true; }

    Process {
        id: probeProc
        environment: ({ "FOLIO_PAM_DIR": root.runtimeDir })
        command: ["sh", "-c", `
            mod() { grep -v '^[[:space:]]*#' "$1" 2>/dev/null | grep -o '[^[:space:]]*pam_fprintd\\.so' | head -1; }
            m=$(mod /etc/pam.d/login); [ -n "$m" ] || m=$(mod /etc/pam.d/swaylock)
            [ -n "$m" ] && echo "login:$m"
            [ -n "$(mod /etc/pam.d/polkit-1)" ] && echo "polkit:1"
            if [ -e /etc/pam.d/folio-fprint ]; then echo "config:/etc/pam.d:folio-fprint"
            elif [ -n "$m" ]; then
                u=$(grep -o '[^[:space:]]*pam_unix\\.so' /etc/pam.d/login | head -1)
                umask 077; mkdir -p "$FOLIO_PAM_DIR"
                printf 'auth required %s max-tries=3 timeout=600\\naccount required %s\\n' "$m" "\${u%pam_unix.so}pam_permit.so" > "$FOLIO_PAM_DIR/fingerprint"
                echo "config:$FOLIO_PAM_DIR:fingerprint"
            fi
            command -v fprintd-list >/dev/null && fprintd-list "$USER" 2>/dev/null | grep -qiE '^[[:space:]]*-[[:space:]]*#|finger:' && echo "enrolled:1"
            true`]
        stdout: StdioCollector {
            onStreamFinished: {
                let login = false, polkit = false, enrolled = false, config = "", dir = "";
                for (const line of text.split("\n")) {
                    if (line.startsWith("login:")) login = true;
                    else if (line.startsWith("polkit:")) polkit = true;
                    else if (line.startsWith("enrolled:")) enrolled = true;
                    else if (line.startsWith("config:")) { const f = line.split(":"); dir = f[1]; config = f[2]; }
                }
                root.inLogin = login; root.inPolkit = polkit; root.enrolled = enrolled;
                root.config = config; root.configDirectory = dir;
            }
        }
    }
    Component.onCompleted: probe()
}
