# Bonhart remote workstation

Audited 2026-10-15. This is the operating and recovery plan for leaving Bonhart
powered on for several weeks. A successful system build alone does not establish
that the machine is safe to leave unattended.

## Access from the MacBook

Use Tailscale plus ordinary OpenSSH for administration and file transfer. Use
the Comet Pro on its **own** tailnet connection for the screen, keyboard, firmware
and encrypted-disk prompt when Linux is unavailable. Neither an AI subscription
nor a working Linux desktop should be required to reach the Comet.

Current Linux address: `100.71.230.32`, MagicDNS
`bonhart-3.taile97d70.ts.net`. There are older Bonhart entries in this tailnet;
do not accidentally connect to `bonhart` or `bonhart-1`.

Add to the Mac's `~/.ssh/config` (choose the private key corresponding to the
MacBook public key already in `modules/nixos/users.nix`):

```sshconfig
Host bonhart-agent
  HostName bonhart-3.taile97d70.ts.net
  User mariano
  IdentityFile ~/.ssh/id_ed25519
  IdentitiesOnly yes
  ForwardAgent no
  ServerAliveInterval 30
  ServerAliveCountMax 3
```

Verify the SSH host-key fingerprint against Bonhart's console on first connection.
Run `ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub` on Bonhart to obtain it.
Then, from the Mac, test `ssh bonhart-agent` and `sudo -v`. Sudo deliberately uses
the **administrator/root password**, not Mariano's login password. The SSH
firewall remains closed on ordinary network interfaces and reachable through
the trusted Tailscale interface; root SSH login is disabled.

`tmux new -As admin` keeps a terminal session alive across a lost connection.
It does not preserve a running process through a reboot. Keep a phone SSH client
configured as a second controller. Test both controllers on cellular/hotspot,
not only on the same Wi-Fi.

The travel controllers are an Apple Silicon M5 Max MacBook Pro and an iPhone.
On 2026-10-15 the Mac at `100.115.44.59` answered a Tailscale ping and offered
OpenSSH; its SSH host key matched Bonhart's existing known-hosts entry. Login
from Bonhart to the Mac is verified as `mariano`. The Mac now has the
`bonhart-agent` SSH alias, with Bonhart's directly verified host key in
`~/.ssh/bonhart_known_hosts`; the previous SSH config was saved as
`~/.ssh/config.before-bonhart`. Bonhart accepts the Mac's existing SSH key, but
the encrypted private key still needs an interactive unlock on the Mac before
the reverse login can be verified. No passphrase was copied or removed.

For the iPhone, use an SSH app such as Blink, generate a separate Ed25519 key
**on the phone**, and add only its public key to
`users.users.mariano.openssh.authorizedKeys.keys` in `modules/nixos/users.nix`.
Configure host `bonhart-3.taile97d70.ts.net`, port `22`, user `mariano`, and the
phone's key. Bonhart's verified Ed25519 host-key fingerprint is
`SHA256:wRqmKZpUVNsjKwcUh+AL5n0HFO4BgZ1EW4RsGNgFFho`.
Keep the private key on the phone. Verify `ssh`, `sudo -v`, and reconnecting to
the same `tmux` session while the phone uses cellular data. Save the Comet's
independent Tailscale address, `https://glkvm.taile97d70.ts.net`, in Safari.

Reference: [Blink host configuration](https://docs.blink.sh/basics/hosts).

### Comet Pro's independent address

`bonhart-3.taile97d70.ts.net` belongs to the Linux host. Its existing web endpoint
serves Overfly; it is not the Comet. The Comet must join the tailnet separately
so its console remains reachable when Linux is offline.

The Comet is enrolled in the tailnet as `glkvm.taile97d70.ts.net`, IP
`100.86.90.3`. Its HTTP endpoint responds and redirects to HTTPS. Open
`https://glkvm.taile97d70.ts.net` for its console. Its LAN address is
`192.168.68.60` (`glkvm.local`). Remote video/keyboard and preboot disk-unlock
access still need end-to-end verification. Keep the Comet powered independently
of Bonhart.

Reference: [Comet Pro Tailscale setup](https://docs.gl-inet.com/kvm/en/user_guide/gl-rm10/quick_setup_guide/#tailscale).

For files, use SFTP or `rsync` over the same SSH alias. Keep source repositories
in Git. For a one-off transfer, `scp HANDOFF.md bonhart-agent:~/Handoff/` works
after `ssh bonhart-agent 'mkdir -p ~/Handoff'`. Do not mirror live agent SQLite
databases, OAuth caches or entire home directories between machines.

## Work in progress and chat history

**Codex:** add the SSH host in the Mac app's Settings > Connections and save the
matching Git repository as a project on each host. Native chat handoff moves
the chat and Git work to a worktree on the destination. It interrupts an active
turn. The matching saved project is required. This is a supported same-account
workflow, not a promise to merge histories between separate subscriptions.

**Claude Code:** run the session on Bonhart and attach from Claude Remote Control
or from SSH/tmux. The files and local session history then stay on Bonhart. For
an existing session, enable `/remote-control` within it. A server can also be
started in a repository using the commands below. Reconnect with the same Claude
account; remote access does not grant access to the other subscription's chats.

For transferring work between products/accounts, use a Git branch plus a short
`HANDOFF.md`: objective, repository and branch/commit, uncommitted files, decisions,
commands/tests already run, current blocker and the exact next action. Export a
transcript where useful. A summary is portable context, not a lossless session
import. Keep private handoffs out of public repositories.

References: [Codex remote connections and handoff](https://learn.chatgpt.com/docs/remote-connections),
[Claude Remote Control](https://code.claude.com/docs/en/remote-control).

## Four subscription profiles

`agent-account` uses the applications' supported configuration-directory
isolation. It never rotates credentials underneath a running desktop app. The
existing `office` profiles use their original directories, including Claude's
default `~/.claude.json` location. Additional profiles live in private directories
under `~/.local/share/agent-accounts`. Credentials never go into this repository
or the Nix store. Inherited API tokens are removed from launched processes so a
subscription selection does not silently use API billing.

| Command prefix | Expected account |
| --- | --- |
| `agent-account codex office` | office@marianomiguel.com |
| `agent-account codex personal` | marianojmig@gmail.com |
| `agent-account claude office` | office@marianomiguel.com |
| `agent-account claude monarch` | mariano.miguel@monarchmd.com |

```sh
agent-account prepare
agent-account list
agent-account login codex personal
agent-account login claude monarch

# Interactive work; change directory to the intended repository first.
agent-account codex personal
agent-account claude monarch

# Reopen work within the same account profile.
agent-account codex office resume
agent-account claude office --resume

# In a tmux session, in a Git repository; accept the first-run remote prompt.
agent-account claude office remote-control --spawn worktree --name 'Bonhart office'
agent-account claude monarch remote-control --spawn worktree --name 'Bonhart Monarch'
```

Login is interactive only when needed. Codex device login prints a code to enter
in the browser on the Mac or phone; the key can stay with you. If device login is
disabled, open a Mac SSH tunnel `ssh -L 1455:localhost:1455 bonhart-agent`, then run
`agent-account codex personal login` inside that connection and finish the
provided browser URL on the Mac. Claude supports its browser login and manual
callback flow. Do not send passwords, tokens or callback URLs in chat.

An identity match is not proof that a token is still valid. Normal agent use
refreshes supported logins; expired/revoked sessions need reauthentication.
Before leaving, run a small real request under each profile and test reconnect.

The CLI profiles have independent histories, MCP grants and settings. They do
not switch the already-running Codex/Claude desktop app's account, nor make
Remote Control sessions visible across accounts. Use the matching account on
your controller. For GUI account changes, use the app's normal sign-out/sign-in
over the Comet; retain SSH as the independent route because sign-out may disable
agent remote access. This installed Codex Linux desktop is a community package
with remote-control patches, so verify its pairing flow on this exact build.

To start with one subscription and finish with another, stop the first agent,
keep the same checkout/worktree, then launch the second profile in that exact
directory with a handoff summary. The second agent sees the current files,
including uncommitted changes, but does not automatically inherit the previous
conversation. `resume` only searches the selected profile's history. The wrapper
does not currently implement cross-profile transcript migration. Avoid two
agents editing the same working tree concurrently.

References: [Codex auth and device login](https://learn.chatgpt.com/docs/auth),
[Codex state directory](https://learn.chatgpt.com/docs/config-file/env-vars),
[Claude multiple accounts](https://code.claude.com/docs/en/authentication).

## Superhuman Mail and Granola

Verified in this Codex desktop connection on 2026-10-15:

- Superhuman: office@marianomiguel.com (default), mariano.miguel@monarchmd.com,
  mariano.miguel@feelslike.studio, mariano@weareweirdo.com, marianojmig@gmail.com.
- Granola: office@marianomiguel.com, workspace Mariano, personal and public note
  access. This provides access to saved notes; it does not install a Linux meeting
  recorder.
- Claude's existing office account: its cloud Granola connector reports connected.

These are connection-specific results. They do not establish that the other
Codex or Claude subscription has the same authorizations.

Official endpoints:

- `https://mcp.mail.superhuman.com/mcp`
- `https://mcp.granola.ai/mcp`

The additional Codex profile is seeded with both endpoints. For Claude profiles,
register only missing connectors (do not duplicate an inherited cloud connector):

```sh
agent-account claude monarch mcp add --scope user --transport http superhuman-mail https://mcp.mail.superhuman.com/mcp
agent-account claude monarch mcp add --scope user --transport http granola https://mcp.granola.ai/mcp
agent-account claude monarch mcp login --no-browser superhuman-mail
agent-account claude monarch mcp login --no-browser granola
```

During this audit both endpoints were registered in Monarch's profile, and
Superhuman was registered in Claude office. Authentication remains separate.
`mcp login --no-browser` is useful over SSH: finish on the Mac, then paste the
redirect into that terminal. In the Codex personal profile use
`agent-account codex personal mcp login superhuman-mail` and the equivalent for
`granola`; remote OAuth callback forwarding may be needed. The existing Codex
desktop plugins are already authenticated and need no duplicate MCP entries.

In each newly authorized Superhuman connection, ask to add each additional inbox,
finish its account-link URL, then verify with `list_accounts`. Confirm the five
addresses above. Connector access can vary between accounts even on the same host.

References: [Superhuman setup and multiple inboxes](https://help.superhuman.com/hc/en-us/articles/47980509830157-Set-Up-the-Superhuman-Mail-MCP),
[Granola MCP](https://docs.granola.ai/help-center/sharing/integrations/mcp).

## YubiKey while traveling

- **SSH to Bonhart:** a FIDO-backed SSH key can stay plugged into the Mac. Signing
  happens there, so you touch the key with you. Register its public key on Bonhart
  and test the Mac's OpenSSH/FIDO support before depending on it. Keep the existing
  SSH key until both paths have passed a real login test.
- **OAuth/device login for an agent:** open the authorization on the Mac or phone
  and use the YubiKey there. Bonhart receives the completed grant. This is the
  preferred approach wherever the application supports it.
- **A website inside Bonhart's browser:** SSH and KVM keyboard forwarding do not
  forward WebAuthn. A remote click cannot satisfy a physical key touch. A phone
  passkey QR flow commonly requires Bluetooth proximity to that browser's host,
  so it is not an across-the-internet substitute.
- **TOTP, if enabled for that service:** read the code with Yubico Authenticator
  on your own compatible device and enter it remotely. This is a different
  authentication method from WebAuthn; service policy determines availability.
- **USB redirection:** USB-over-IP software is a possible experiment for a key
  attached to the Mac. NixOS/kernel, macOS drivers, key interfaces and browser
  compatibility must be tested. Do not make it the only recovery method or expose
  its port publicly. Comet virtual keyboard/storage support alone is not evidence
  of arbitrary USB/FIDO forwarding.

### Current path: open-source FIDO bridge

The **USB-C YubiKey 5C** can now authenticate in Bonhart's Chrome while remaining
plugged into the Mac. The bridge carries only FIDO HID reports through an
authenticated SSH session over Tailscale:

```text
Bonhart browser -> virtual FIDO device -> SSH -> Mac HID API -> physical YubiKey
```

On Bonhart:

```sh
remote-yubikey list        # Read the compatible keys currently attached to the Mac
remote-yubikey start       # Connect the 5C (1050:0407); administrator dialog on Bonhart
remote-yubikey status      # Distinguishes waiting for authentication from a connected key
remote-yubikey stop        # Remove the virtual key and release the Mac connection

# To select the other reviewed FIDO key instead:
remote-yubikey stop
remote-yubikey start 0402
```

Keep the Mac awake, connected to Tailscale, and the selected key plugged in.
Start the bridge before the website's security-key prompt, and touch the key
beside the Mac when requested. Enter a FIDO PIN into the browser's own prompt if
required. The bridge does not save PINs or credentials. Stop it after use.
After a key/network disconnect, run `start` again and retry the website prompt;
the bridge deliberately does not reconnect or claim a key automatically.

The Mac helper is installed under
`~/Library/Application Support/Bonhart/fido-bridge`. To reproduce the installation
on this Apple Silicon Mac, copy `scripts/fido-bridge` from this checkout to the
Mac and run its `setup-mac.sh`. It uses Homebrew Python 3.14 and `uv`, a private
virtual environment, and hash-checked dependencies in `requirements.lock`.
It opens no TCP port and needs no administrator access or background service.
Bonhart initiates SSH to `mariano@100.115.44.59` using its existing verified host
key and SSH credentials. The helper's absolute path is part of the reviewed
launcher; update it if the Mac username/address changes.

On Linux, `pkexec` is used only to open `/dev/uhid`; the process permanently drops
root and supplementary groups before launching SSH or processing network data.
The descriptor is fixed to the FIDO usage page. Existing systemd udev rules grant
the active user access to the resulting `/dev/hidraw*` node. No broad device
permission, passwordless policy, listening port, or boot-time bridge is enabled.
`uhid` is loaded at boot, and `remote-yubikey` is included in the system packages.

The Mac relay validates report sizes, assembles bounded CTAP messages, separates
its channel IDs from other Mac HID clients, and refuses key reset, PIN changes,
credential-management and vendor commands. It allows browser registration,
authentication, capability queries and PIN authentication. PIV, OpenPGP and OTP
interfaces are not forwarded. Only one bridge can use each selected key at once;
avoid authenticating locally on the Mac with that same key during a remote prompt.

Verification on 2026-10-15:

- Both physical keys passed CTAPHID initialization, CTAP2 GetInfo and PING through
  the SSH relay as the ordinary Mac user.
- The 5C appeared on Bonhart as `Bonhart Remote YubiKey`; libfido2 opened it and
  read its capabilities through the normal Linux FIDO interface. Its device ACL
  granted `mariano` access, and the forwarding process ran as `mariano`, not root.
- Bonhart's real Chrome passed registration and a subsequent authentication with
  physical touches on the Mac. The local test server verified the assertion
  signature, challenge, origin and user presence. No external account was used;
  the test requested a non-discoverable credential and kept public data in memory.
- Terminating the bridge's SSH transport removed the virtual device. The physical
  key then answered GetInfo locally on the Mac. Starting the installed command
  again recreated the device, and GetInfo and PING passed through that connection.
- Thirteen unit tests cover message fragmentation, size/channel validation,
  blocked administrative commands, PIN-operation restrictions and the UHID ABI,
  including the zero report-ID prefix observed on this kernel.
- The Nix package and full Bonhart system build passed. Activation completed, and
  `/run/current-system/sw/bin/remote-yubikey` is installed.

For another browser test, run `scripts/fido-bridge/browser-test.py` with a Python
environment containing `fido2`, then open `http://localhost:8790` **in Bonhart's
Chrome**, keep the tab focused, and use its two buttons. Stop the test server when
finished; its state is ephemeral. A second test from an outside network and
long-duration use remain part of the departure checklist. The second key has
passed transport checks but has not yet passed this full browser test.

### iPhone scope

The current bridge requires the key to be plugged into the Mac. An iPhone can
control Bonhart through agent remote access or GLKVM while that bridge is running,
but plugging the key into the phone or tapping it over NFC does not forward it
to Bonhart. There is no iPhone helper in this configuration.

For a login completed directly in iPhone Safari, Yubico documents USB-C support
for the 5C on compatible USB-C iPhones, and USB-C/NFC support for the **5C NFC**.
The plain 5C has no NFC. This local phone authentication can complete an agent's
OAuth/device-login flow where supported; it does not answer an arbitrary WebAuthn
prompt in Bonhart's browser.

A dedicated NFC companion app is a possible future extension: Yubico's iOS SDK
exposes NFC FIDO operations. It would require an authenticated transport, changes
to the Bonhart bridge and physical-device testing. SDK access to USB-C differs
from Safari's native WebAuthn support, so neither phone transport is established
by the working Mac implementation.

References: [Yubico iOS compatibility](https://developers.yubico.com/WebAuthn/Supporting_FIDO2_Security_Keys_on_iOS_or_iPadOS/Security_Key_Compatibility.html),
[YubiKit iOS connection interfaces](https://github.com/Yubico/yubikit-ios#enable-tksmartcard-support),
[YubiKit NFC integration](https://github.com/Yubico/yubikit-ios/blob/main/docs/NFC-Notes.md).

### Historical VirtualHere trial (license blocked)

The earlier full-USB forwarding trial used this path:

```text
YubiKey plugged into Mac -> VirtualHere Mac server -> SSH over Tailscale
                        -> VirtualHere Linux client -> Bonhart browser
```

The VirtualHere path never completed a browser login. Ordinary SSH agent
forwarding is not part of either browser-authentication path. No working iPhone
USB-export path has been established, so phone-only administration must not depend
on that capability.

VirtualHere currently supplies a universal Mac server and a Linux client. This
flake packages the GUI and console client at version 6.0.3, with SHA-256-pinned
downloads. Build and command-line startup have been checked on Bonhart:

```sh
cd ~/Development/personal/nixos-config
nix run 'path:.#virtualhere-client' -- -e
```

The GUI launcher requests normal administrator authentication, because the Linux
client cannot attach USB/IP devices as an ordinary user. `-e` disables automatic
server discovery. No USB device is automatically claimed,
no firewall port is opened, and no background client service is installed by this
package. Bonhart's 6.18.50 kernel includes `vhci_hcd`, and it has been loaded for
the trial. The installed systemd rules already identify FIDO HID devices and
grant active-session access (`60-fido-id.rules` and `70-uaccess.rules`). Verify
the resulting device ACL when a key is attached; no broad HID permission rule
has been added.

The intended tunnel, initiated on the Mac after configuring its `bonhart-agent`
SSH alias, is:

```sh
ssh -N -T -o ExitOnForwardFailure=yes \
  -R 127.0.0.1:17575:127.0.0.1:7575 bonhart-agent
```

The Linux client then adds `127.0.0.1:17575` as a manually specified hub and
selects only the YubiKey. Configure the Mac server's `AllowedDevices=1050` to
limit export to Yubico devices and disable discovery with `UseAVAHI=0`.
Verify those settings against the actual Mac server before use.

**Licensing and network binding:** the vendor advertises a one-device graphical
trial, but this Mac-server/Linux-GUI-client trial refused attachment with
"you need to purchase a license for your server". Both keys were discoverable;
neither attached. The separate console daemon also requires a server license. The
vendor also lists `NetworkInterface` (used to bind the server to loopback) as a
licensed setting. A tunnel alone does not protect a server listening on all Mac
interfaces. Before a trial, verify firewall isolation on the Mac; for the licensed
setup, set and verify `NetworkInterface=127.0.0.1`. Do not assume an unlicensed
server honors that option. No license has been purchased or unattended service
enabled by this configuration.

Trial progress on 2026-10-15:

- Mac server 4.8.8 installed at `~/Applications/VirtualHereServerUniversal.app`.
  Apple's signature and notarization assessments passed. The Mac runs macOS
  27.0.1 on arm64.
- macOS sees two Yubico devices: `1050:0407` (OTP/FIDO/CCID) and `1050:0402`
  (FIDO). No key's interfaces, PIN, or stored credentials were changed.
- The Mac administrator blocked incoming connections to the server application
  with the macOS application firewall. Data connections from both Bonhart's LAN
  and Tailscale addresses were reset, while Mac localhost remained reachable.
- The Mac GUI's administrator relaunch dropped the custom `-c`/`-r` arguments:
  its initial process used the restricted config, but the elevated process
  listened on a wildcard address. The firewall remains essential for this
  trial. Do not describe this runtime server as loopback-bound or as having
  retained the device allowlist. Fix and recheck startup before making it
  persistent.
- A temporary Bonhart user unit, `bonhart-yubikey-tunnel`, initiated SSH **from
  Bonhart to the Mac** and maps local `127.0.0.1:17575` to Mac `127.0.0.1:7575`.
  This trial direction uses the verified SSH login and does not need the Mac's
  encrypted SSH key unlocked. The unit has now been stopped.
- Administrator authentication succeeded, and the root Linux GUI client
  discovered both keys through that tunnel. Attempts to attach each key failed;
  the user reported the server-license error. Neither `lsusb` nor `fido2-token`
  detected an imported key. This establishes a licensing blocker, not a hardware
  compatibility result.
- All local device-use requests were stopped, the Linux client exited through
  its API, and the tunnel was stopped. The Mac server remains running behind its
  blocking application-firewall rule; it has no active forwarding connection.
  No unattended USB service has been enabled.

### Open-source alternative assessment

The Mac implementation [usbipd-mac](https://github.com/beriberikix/usbipd-mac)
explicitly excludes HID devices held by Apple's drivers. Its maintainer reports
that the needed DriverKit entitlement was denied. The other candidate,
[usbipd-python](https://github.com/abrinkman/usbipd-python), also documents
macOS HID ownership limitations. Neither is a verified replacement for this
YubiKey path.

A software alternative is to forward **FIDO/CTAP only** over SSH,
with a virtual FIDO HID device on Bonhart and the physical key accessed through
macOS's HID API. [Qubes' CTAP proxy](https://github.com/QubesOS/qubes-app-u2f)
provides prior art, but depends on Qubes RPC and is not a drop-in Mac/NixOS tool.
[Yubico's python-fido2](https://github.com/Yubico/python-fido2) provides a
maintained, open-source Mac backend. The bridge described above implements that
approach with an original small relay and Yubico's HID backend; it does not depend
on Qubes or copy Qubes' implementation.

On the actual Mac, `python-fido2==2.0.0` was run through an isolated `uv`
environment with Homebrew Python 3.14. It opened both `1050:0407` and `1050:0402`
as the normal `mariano` user over SSH, completed CTAPHID initialization, and
successfully read CTAP2 GetInfo. No root prompt, PIN entry, credential enrollment,
or key reset was involved. This verifies the Mac-side access needed by the
bridge. Subsequent end-to-end results are recorded above.

An alternative requiring additional travel hardware is a Linux USB/IP server
with the key physically attached to it, tunneled over SSH/Tailscale; that also
needs a real browser test before it can be relied upon.

The departure acceptance test includes a real security-key login in Bonhart's
browser, a physical touch on the Mac, a disconnected/reconnected tunnel, a
disconnect during a prompt, and a second test through an internet connection
outside the home LAN. Confirm the key becomes usable locally again after release.
Do not equate the successful local browser test with completing every recovery
and outside-network test.

Keep a separately enrolled backup key and service recovery codes accessible while
traveling. No key-touch requirement is disabled by this configuration.

References: [Yubico FIDO SSH](https://developers.yubico.com/SSH/Securing_SSH_with_FIDO2.html),
[FIDO cross-device proximity](https://fidoalliance.org/passkeys/),
[VirtualHere Mac server](https://www.virtualhere.com/osx_server_software),
[VirtualHere Linux client](https://www.virtualhere.com/usb_client_software),
[Console license requirement](https://www.virtualhere.com/linux_console),
[Server restrictions and configuration](https://www.virtualhere.com/configuration_faq).

## Departure gate and recovery

Known audit findings:

- Tailscale was disconnected despite `tailscaled` being active. Reconnected with
  `tailscale up`; it now reports Running/Online. The current node key expires
  2027-02-27. Review key expiry for **both** Bonhart and the Comet. An initial ping
  to the Mac timed out; a later ping to `100.115.44.59` succeeded. SSH login and
  an outside-network recovery test are still pending.
- `sshd` runs at boot and the MacBook's public key is configured. User lingering
  is enabled. This is not a completed Mac-to-Bonhart login test.
- This change makes AC lid-close ignore the lid in logind and GNOME. DMS already
  has AC idle sleep disabled. On battery, idle hibernation after 15 minutes and
  lid-close hibernation remain as outage safeguards. Verify actual AC detection.
- Root and swap are LUKS encrypted. After a cold boot or relevant recovery path,
  the Comet must display the boot/disk-unlock prompt and send keyboard input.
  Tailscale on Linux only becomes available after the disk is unlocked.
- Backups are scheduled but skipped: the system journal specifically reports the
  missing `/var/lib/restic/password`. The root-only destination configuration has
  not been verified. Confirm an encrypted off-machine target, finish its credentials,
  run a snapshot and restore a test file before departure. Git alone does not back
  up local chats, untracked work or agent credentials.

Complete these real tests while someone is still physically present:

1. Mac and phone on an outside network: SSH, sudo and Comet screen/keyboard.
2. Comet independently powered and independently networked from Bonhart; verify
   access does not depend on Bonhart acting as an exit node or subnet router.
3. Controlled cold boot: firmware menu, LUKS unlock, login, Tailscale reconnection,
   agent relaunch and resume. Verify the external HDMI image exists before Linux,
   including with the lid in the position in which it will be left.
4. Hardware hard-power control. For this laptop a tested button actuator may be
   needed. Cutting AC with a smart plug will not reset a battery-powered frozen
   laptop. The Comet's optional Fingerbot/ATX accessories are separate capabilities.
5. Router/ONT and Comet power recovery; use a UPS and test a backup internet path
   if extended outages must be tolerated. No software can recover a dead ISP,
   dead power supply or disconnected cable without an independent path.
6. All four agent profiles: real request, remote reconnect, account identity,
   connector inbox list and Granola account info. Confirm the existing office
   profiles still work after using the other profiles.
7. Successful encrypted off-machine backup and a restore of one file.

Routine recovery over SSH:

```sh
tailscale status
systemctl --failed
systemctl --user --failed
tmux ls
journalctl -b -p err --no-pager
systemctl --user restart dms.service
sudo systemctl restart sshd
```

Do not stop/re-authenticate the only VPN route or reboot until Comet access is
tested. If Linux is inaccessible, use the Comet, unlock the disk and log in; after
a bad NixOS change choose the previous boot generation. If Linux is accessible,
`sudo nixos-rebuild switch --rollback` restores the previous system generation.
Do not run simultaneous builds or reboot during active agent work without first
recording a handoff.

References: [Comet Pro console and power accessories](https://docs.gl-inet.com/kvm/en/user_guide/gl-rm10/console_guide/),
[Tailscale unattended Linux behavior](https://tailscale.com/docs/how-to/run-unattended),
[Tailscale key expiry](https://tailscale.com/docs/features/access-control/key-expiry).
