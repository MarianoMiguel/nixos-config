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
from Bonhart is still awaiting authorization on the Mac. Reachability is not a
completed administration test.

For the iPhone, use an SSH app such as Blink, generate a separate Ed25519 key
**on the phone**, and add only its public key to
`users.users.mariano.openssh.authorizedKeys.keys` in `modules/nixos/users.nix`.
Configure host `bonhart-3.taile97d70.ts.net`, port `22`, user `mariano`, and the
phone's key. Bonhart's verified Ed25519 host-key fingerprint is
`SHA256:wRqmKZpUVNsjKwcUh+AL5n0HFO4BgZ1EW4RsGNgFFho`.
Keep the private key on the phone. Verify `ssh`, `sudo -v`, and reconnecting to
the same `tmux` session while the phone uses cellular data. Save the Comet's
independent Tailscale address in Safari once it is connected; that address has
not yet been established here.

Reference: [Blink host configuration](https://docs.blink.sh/basics/hosts).

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

The key is a **USB-C YubiKey 5C**, and the first forwarding trial will use the
MacBook as the USB server, Bonhart as the USB client:

```text
YubiKey plugged into Mac -> VirtualHere Mac server -> SSH over Tailscale
                        -> VirtualHere Linux client -> Bonhart browser
```

Touch still happens on the physical key beside the Mac. This is a compatibility
trial, not a verified WebAuthn path yet. Ordinary SSH agent forwarding is not
part of this browser-authentication path. No working iPhone USB-export path has
been established, so phone-only administration must not depend on that capability.

VirtualHere currently supplies a universal Mac server and a Linux client. This
flake packages the GUI and console client at version 6.0.3, with SHA-256-pinned
downloads. Build and command-line startup have been checked on Bonhart:

```sh
cd ~/Development/personal/nixos-config
nix run 'path:.#virtualhere-client' -- -e
```

`-e` disables automatic server discovery. No USB device is automatically claimed,
no firewall port is opened, and no background client service is installed by this
package. Bonhart's 6.18.50 kernel includes `vhci_hcd`; loading it requires admin
access. The forwarded FIDO HID interface must also receive the correct udev
permissions before a non-root browser can use it. These runtime steps remain
part of the physical-key trial.

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

**Licensing and network binding:** the server's graphical trial allows one
device, but the console client daemon needs a purchased server license. The
vendor also lists `NetworkInterface` (used to bind the server to loopback) as a
licensed setting. A tunnel alone does not protect a server listening on all Mac
interfaces. Before a trial, verify firewall isolation on the Mac; for the licensed
setup, set and verify `NetworkInterface=127.0.0.1`. Do not assume an unlicensed
server honors that option. No license has been purchased or unattended service
enabled by this configuration.

The acceptance test must include a real security-key login in Bonhart's browser,
a physical touch on the Mac, a disconnected/reconnected tunnel, a disconnect
during a prompt, and a second test through an internet connection outside the
home LAN. Confirm the key becomes usable locally again after release. Until
those pass, the remote-browser requirement remains open.

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
