{ config, lib, pkgs, ... }:

let
  cfg = config.services.claudeTriage;

  # The Claude Code CLI self-updates into ~/.local/share/claude, so it is
  # deliberately NOT a nixpkgs input. Referencing the stable ~/.local/bin
  # symlink keeps the unit working across CLI upgrades without a rebuild.
  claudeBin = "$HOME/.local/bin/claude";

  # Read-only tool surface. In --print mode Claude Code cannot prompt for
  # permission, so anything omitted here is denied automatically -- that denial
  # is the actual safety boundary, and the disallow list below is belt-and-braces.
  allowedTools = [
    "Read"
    "Grep"
    "Glob"
    "Bash(journalctl:*)"
    "Bash(systemctl:*)"
    "Bash(coredumpctl:*)"
    "Bash(cat:*)"
    "Bash(ls:*)"
    "Bash(head:*)"
    "Bash(tail:*)"
    "Bash(stat:*)"
    "Bash(nixos-version:*)"
    "Bash(git log:*)"
    "Bash(git diff:*)"
    "Bash(git show:*)"
    "Bash(git status:*)"
  ];

  # WebSearch/WebFetch are withheld on purpose: triage input is raw system logs,
  # and those tools would ship them to a third party. Add them consciously if a
  # class of failure genuinely needs upstream context.
  disallowedTools = [ "Write" "Edit" "NotebookEdit" "WebSearch" "WebFetch" ];

  quoteList = xs: lib.concatMapStringsSep " " lib.escapeShellArg xs;

  triage = pkgs.writeShellApplication {
    name = "claude-triage";
    runtimeInputs = with pkgs; [
      systemd
      coreutils
      gnused
      gnugrep
      jq
      libnotify
      git
    ];
    text = ''
      # claude-triage --kind unit|coredump --id <identifier> [--json <line>]
      #
      # Collects evidence about a failure, hands it to Claude Code in read-only
      # headless mode, and writes the resulting report to disk. It never applies
      # a change: the output is a diagnosis plus a proposed patch for review.

      KIND=""
      ID=""
      JSON=""

      while [ "$#" -gt 0 ]; do
        case "$1" in
          --kind) KIND="$2"; shift 2 ;;
          --id)   ID="$2";   shift 2 ;;
          --json) JSON="$2"; shift 2 ;;
          *) echo "claude-triage: unknown argument: $1" >&2; exit 2 ;;
        esac
      done

      [ -n "$KIND" ] && [ -n "$ID" ] || {
        echo "usage: claude-triage --kind unit|coredump --id <identifier>" >&2
        exit 2
      }

      STATE="''${XDG_STATE_HOME:-$HOME/.local/state}/claude-triage"
      COOLDOWN=${toString cfg.cooldownSec}
      mkdir -p "$STATE"

      SLUG="$(printf '%s' "$KIND-$ID" | tr -c 'A-Za-z0-9._@-' '_')"

      # Rate limit in the script as well as the unit. StartLimitBurst bounds
      # restarts of one instance; this bounds re-triage of the same subject even
      # if systemd resets its counters (e.g. after a daemon-reload).
      MARKER="$STATE/.last-$SLUG"
      NOW="$(date +%s)"
      if [ -f "$MARKER" ]; then
        LAST="$(cat "$MARKER" 2>/dev/null || echo 0)"
        AGE=$(( NOW - LAST ))
        if [ "$AGE" -lt "$COOLDOWN" ]; then
          echo "claude-triage: skipping $ID, triaged ''${AGE}s ago (cooldown ''${COOLDOWN}s)"
          exit 0
        fi
      fi
      printf '%s' "$NOW" > "$MARKER"

      OUTDIR="$STATE/$(date +%Y%m%d-%H%M%S)-$SLUG"
      mkdir -p "$OUTDIR"
      EVIDENCE="$OUTDIR/evidence.md"
      REPORT="$OUTDIR/report.md"

      # ---- evidence ------------------------------------------------------
      if [ "$KIND" = "unit" ]; then
        SUBJECT="systemd user unit $ID"
        {
          echo "# Failure evidence: $ID"
          echo
          echo "## Unit state"
          echo '```'
          systemctl --user show "$ID" \
            -p Id -p Description -p Result -p ExecMainStatus -p ExecMainCode \
            -p NRestarts -p ActiveState -p SubState -p InvocationID 2>&1 || true
          echo '```'
          echo
          echo "## Unit definition"
          echo '```ini'
          systemctl --user cat "$ID" 2>&1 || true
          echo '```'
          echo
          echo "## Journal (last ${toString cfg.journalLines} lines)"
          echo '```'
          journalctl --user -u "$ID" -n ${toString cfg.journalLines} \
            --no-pager -o short-precise 2>&1 || true
          echo '```'
        } > "$EVIDENCE"

        # A unit failure and a coredump for that unit are the same incident when
        # both are present, so fold the stack trace into one evidence file.
        for FIELD in COREDUMP_USER_UNIT COREDUMP_UNIT; do
          if coredumpctl info --no-pager -1 "$FIELD=$ID" > "$OUTDIR/coredump.txt" 2>/dev/null \
             && [ -s "$OUTDIR/coredump.txt" ]; then
            {
              echo
              echo "## Coredump"
              echo '```'
              cat "$OUTDIR/coredump.txt"
              echo '```'
            } >> "$EVIDENCE"
            break
          fi
          rm -f "$OUTDIR/coredump.txt"
        done
      else
        SUBJECT="crashed process $ID"
        {
          echo "# Coredump evidence: $ID"
          echo
          if [ -n "$JSON" ]; then
            echo "## Coredump record"
            echo '```json'
            printf '%s\n' "$JSON" | jq '{
              COREDUMP_COMM, COREDUMP_EXE, COREDUMP_PID, COREDUMP_SIGNAL_NAME,
              COREDUMP_UNIT, COREDUMP_USER_UNIT, COREDUMP_CMDLINE, MESSAGE
            }' 2>&1 || printf '%s\n' "$JSON"
            echo '```'
            echo
          fi
          echo "## Backtrace"
          echo '```'
          coredumpctl info --no-pager -1 "COREDUMP_COMM=$ID" 2>&1 || true
          echo '```'
          echo
          echo "## Surrounding journal"
          echo '```'
          journalctl --user -n ${toString cfg.journalLines} \
            --no-pager -o short-precise 2>&1 || true
          echo '```'
        } > "$EVIDENCE"
      fi

      # ---- diagnosis -----------------------------------------------------
      PROMPT="$(cat <<PROMPT_EOF
The $SUBJECT just failed on this machine (NixOS, flake config at
${cfg.nixosConfigDir}, managed with home-manager).

Evidence has been collected for you at:
  $EVIDENCE

Read that file first, then investigate further with the read-only tools you have.
You cannot modify anything on this system and must not try -- your job is to
explain the failure and propose a change for a human to apply.

Answer with exactly these sections:

## Verdict
One sentence: what failed and why.

## Confidence
high, medium, or low -- and what evidence would raise it.

## Evidence
The two to four specific log lines or facts that support the verdict. Quote them
literally.

## Fix
The concrete change. This machine is declarative, so strongly prefer a diff
against a file under ${cfg.nixosConfigDir}. Show it as a patch. If the cause is
not a configuration problem (upstream bug, hardware, transient network), say so
plainly instead of inventing a config change.

## Risk
What could go wrong if the fix is applied, and how to roll back.

Be terse and concrete. If the evidence genuinely does not explain the failure,
write "insufficient evidence" as the Verdict rather than guessing -- a wrong
confident answer is worse than none here.
PROMPT_EOF
      )"

      set +e
      "${claudeBin}" --print "$PROMPT" \
        --output-format json \
        --allowed-tools ${quoteList allowedTools} \
        --disallowed-tools ${quoteList disallowedTools} \
        --add-dir ${lib.escapeShellArg cfg.nixosConfigDir} \
        > "$OUTDIR/raw.json" 2> "$OUTDIR/claude.err"
      RC=$?
      set -e

      if [ "$RC" -ne 0 ]; then
        {
          echo "# Triage failed"
          echo
          echo "Claude Code exited $RC. Evidence is still at $EVIDENCE."
          echo
          echo '```'
          tail -n 40 "$OUTDIR/claude.err" 2>/dev/null || true
          echo '```'
        } > "$REPORT"
        notify-send -u critical -a "Claude Triage" \
          "Triage failed for $ID" "claude exited $RC -- see $OUTDIR" || true
        exit "$RC"
      fi

      jq -r '.result // empty' "$OUTDIR/raw.json" > "$REPORT" 2>/dev/null || true
      [ -s "$REPORT" ] || cp "$OUTDIR/raw.json" "$REPORT"

      # Keep a stable path so a notification action or a shell alias can always
      # open the most recent report without globbing timestamps.
      ln -sfn "$OUTDIR" "$STATE/latest"

      # ---- notify --------------------------------------------------------
      VERDICT="$(sed -n '/^## *Verdict/,/^## /p' "$REPORT" \
        | grep -v '^## ' | grep -v '^[[:space:]]*$' | head -n 2 | tr '\n' ' ')"
      [ -n "$VERDICT" ] || VERDICT="Report ready at $STATE/latest/report.md"

      notify-send -u critical -a "Claude Triage" "$ID failed" "$VERDICT" || true

      echo "claude-triage: report written to $REPORT"
    '';
  };

  coredumpWatch = pkgs.writeShellApplication {
    name = "claude-coredump-watch";
    runtimeInputs = with pkgs; [ systemd coreutils gnugrep jq triage ];
    text = ''
      # systemd-coredump has no OnFailure= equivalent, so the only general hook
      # for a plain process crash is the journal entry it writes. This follows
      # that one message ID and hands qualifying crashes to claude-triage.
      COREDUMP_MESSAGE_ID=fc2e22bc6ee647b6b90729ab34a250b1

      IGNORE=${lib.escapeShellArg (lib.concatStringsSep "\n" cfg.coredumpIgnore)}

      journalctl --follow --lines=0 --output=json \
        "MESSAGE_ID=$COREDUMP_MESSAGE_ID" \
      | while read -r LINE; do
          COMM="$(printf '%s' "$LINE" | jq -r '.COREDUMP_COMM // empty')"
          [ -n "$COMM" ] || continue

          # Proprietary desktop apps crash on their own schedule and their fixes
          # are never in this config, so triaging them is pure noise.
          if printf '%s\n' "$IGNORE" | grep -qxF -- "$COMM"; then
            echo "claude-coredump-watch: ignoring $COMM"
            continue
          fi

          # A crash inside a systemd unit already reaches triage via OnFailure=,
          # and duplicating it would burn a second diagnosis on one incident.
          UNIT="$(printf '%s' "$LINE" | jq -r '.COREDUMP_USER_UNIT // .COREDUMP_UNIT // empty')"
          if [ -n "$UNIT" ]; then
            echo "claude-coredump-watch: $COMM belongs to $UNIT, leaving it to OnFailure="
            continue
          fi

          echo "claude-coredump-watch: triaging $COMM"
          claude-triage --kind coredump --id "$COMM" --json "$LINE" || true
        done
    '';
  };

in
{
  options.services.claudeTriage = {
    enable = lib.mkEnableOption "Claude Code crash triage for systemd user units";

    units = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "overfly-gateway.service" ];
      description = ''
        User units to attach OnFailure= triage to. Names must include the
        .service suffix. Units defined outside this flake are handled with a
        drop-in, so read-only unit files from the Nix store are fine.
      '';
    };

    watchCoredumps = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Also triage plain process crashes caught by systemd-coredump.";
    };

    coredumpIgnore = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "chrome"
        ".spotify-wrappe"
        "slack"
        "electron"
        ".drkonqi-coredu"
        "wireplumber"
      ];
      description = ''
        COREDUMP_COMM values to skip. Note that the kernel truncates comm to 15
        characters, which is why some entries here look cut off -- match what
        `coredumpctl list` actually prints, not the full binary name.
      '';
    };

    cooldownSec = lib.mkOption {
      type = lib.types.int;
      default = 1800;
      description = "Minimum seconds between two triage runs for the same subject.";
    };

    journalLines = lib.mkOption {
      type = lib.types.int;
      default = 300;
      description = "How many journal lines to include as evidence.";
    };

    timeoutSec = lib.mkOption {
      type = lib.types.int;
      default = 600;
      description = "Hard ceiling on a single triage run, so a stuck session cannot hang.";
    };

    nixosConfigDir = lib.mkOption {
      type = lib.types.str;
      default = "/home/mariano/Development/personal/nixos-config";
      description = "Flake checkout Claude may read when proposing a patch.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ triage ];

    home-manager.users.mariano = {
      systemd.user.services = lib.mkMerge [
        {
          # Templated so one definition serves every watched unit: OnFailure=
          # expands %n to the failing unit name, which arrives here as %i.
          "claude-triage@" = {
            Unit = {
              # %i, not %I: OnFailure= puts the literal unit name in the
              # instance, and unescaping it would turn every hyphen into a
              # slash -- overfly-gateway.service becomes overfly/gateway.service.
              Description = "Claude triage for %i";
              # If triage itself starts failing, stop after three attempts an
              # hour. The limit protects subscription usage, not a bill: a unit
              # that flaps overnight would otherwise spend the Max budget you
              # wanted for actual work and leave you rate-limited by morning.
              StartLimitIntervalSec = 3600;
              StartLimitBurst = 3;
            };
            Service = {
              Type = "oneshot";
              ExecStart = "${triage}/bin/claude-triage --kind unit --id %i";
              TimeoutStartSec = cfg.timeoutSec;
              # notify-send needs the session bus; user units do not always
              # inherit DBUS_SESSION_BUS_ADDRESS, and %t is XDG_RUNTIME_DIR.
              Environment = [ "DBUS_SESSION_BUS_ADDRESS=unix:path=%t/bus" ];
              Nice = 10;
              UMask = "0077";
            };
          };
        }

        (lib.mkIf cfg.watchCoredumps {
          claude-coredump-watch = {
            Unit = {
              Description = "Watch systemd-coredump for crashes worth triaging";
              After = [ "default.target" ];
            };
            Service = {
              Type = "simple";
              ExecStart = "${coredumpWatch}/bin/claude-coredump-watch";
              Restart = "on-failure";
              RestartSec = 30;
              Environment = [ "DBUS_SESSION_BUS_ADDRESS=unix:path=%t/bus" ];
              Nice = 10;
              UMask = "0077";
            };
            Install.WantedBy = [ "default.target" ];
          };
        })
      ];

      # A drop-in rather than a full unit definition, because most watched units
      # are not defined by this flake -- some are read-only Nix store files, some
      # are hand-linked from other repos -- and a drop-in attaches to all alike.
      xdg.configFile = lib.genAttrs
        (map (u: "systemd/user/${u}.d/10-claude-triage.conf")
          # OnFailure= on the triage unit itself would make any triage error an
          # endless chain, so it is filtered out defensively.
          (lib.filter (u: !lib.hasPrefix "claude-triage" u) cfg.units))
        (_: {
          text = ''
            # Generated by modules/nixos/claude-triage.nix -- do not edit.
            [Unit]
            OnFailure=claude-triage@%n.service
          '';
        });
    };
  };
}
