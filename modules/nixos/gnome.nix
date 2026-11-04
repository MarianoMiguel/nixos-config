{ librepods-rust, pkgs, ... }:

# GNOME is the desktop (services.desktopManager.gnome, desktop.nix). This
# module adds what it does not ship: the GNOME Shell extensions packaged or
# pinned here, CodexBar's quota indicator with its CLI and helpers, and
# LibrePods for AirPods. Vicinae and its window management live in
# vicinae.nix; the login screen in login-screen.nix.
let
  system = pkgs.stdenv.hostPlatform.system;
  librepods = librepods-rust.packages.${system}.default;
  # The Rust package currently installs only its binary even though upstream
  # ships a desktop entry and icon. Provide the missing launcher so LibrePods
  # appears in GNOME's application grid.
  librepodsDesktopItem = pkgs.makeDesktopItem {
    # iced publishes this exact value as the Wayland application ID. GNOME
    # matches Wayland windows to the desktop-file basename for dock icons.
    name = "librepods";
    desktopName = "LibrePods";
    genericName = "AirPods Controls";
    comment = "Control AirPods features from Linux";
    exec = "${librepods}/bin/librepods";
    icon = "${librepods-rust}/linux-rust/assets/icon.png";
    categories = [ "Utility" ];
    keywords = [
      "AirPods"
      "Bluetooth"
      "Headphones"
    ];
    startupNotify = true;
    startupWMClass = "librepods";
  };
  # LibrePods lives in the tray, which GNOME offers through the AppIndicator
  # extension below (org.kde.StatusNotifierWatcher on the session bus).
  waitForStatusNotifierWatcher = pkgs.writeShellScript "wait-for-status-notifier-watcher" ''
    for _ in $(${pkgs.coreutils}/bin/seq 1 300); do
      if ${pkgs.systemd}/bin/busctl --user status org.kde.StatusNotifierWatcher >/dev/null 2>&1; then
        exit 0
      fi
      ${pkgs.coreutils}/bin/sleep 0.1
    done

    echo "Timed out waiting for org.kde.StatusNotifierWatcher" >&2
    exit 1
  '';

  codexbarUnwrapped = pkgs.stdenvNoCC.mkDerivation {
    pname = "codexbar-unwrapped";
    version = "0.55.0";

    src = pkgs.fetchzip {
      url = "https://github.com/steipete/CodexBar/releases/download/v0.55.0/CodexBarCLI-v0.55.0-linux-x86_64.tar.gz";
      sha256 = "sha256-Mx2Zs5X2ZniPmqCB5Dk66yYP7DlE5sh/FRzp1mh7J04=";
      stripRoot = false;
    };

    nativeBuildInputs = [ pkgs.autoPatchelfHook ];
    buildInputs = with pkgs; [
      curl
      sqlite
      stdenv.cc.cc.lib
    ];

    installPhase = ''
      runHook preInstall
      install -Dm0755 codexbar "$out/bin/codexbar"
      install -Dm0755 CodexBarCLI "$out/bin/CodexBarCLI"
      cp -R CodexBar_CodexBarCore.bundle "$out/bin/"
      install -Dm0644 VERSION "$out/bin/VERSION"
      runHook postInstall
    '';
  };

  # CodexBar reports provider CLI versions by looking them up in PATH. Its
  # Linux Swift build can trap in Foundation.Process when that lookup runs
  # below GNOME Shell or systemd. Point the Codex probe at a known executable
  # so it never needs the fragile nested `which` process; retain ~/.local/bin
  # for provider CLIs installed outside the system profile.
  codexbar = pkgs.symlinkJoin {
    name = "codexbar-${codexbarUnwrapped.version}";
    paths = [ codexbarUnwrapped ];
    postBuild = ''
      for binary in codexbar CodexBarCLI; do
        rm "$out/bin/$binary"
        ${pkgs.coreutils}/bin/tee "$out/bin/$binary" >/dev/null <<EOF
#!${pkgs.runtimeShell}
export PATH="\$HOME/.local/bin:\$PATH"
export CODEX_CLI_PATH="${pkgs.codex}/bin/codex"
exec "${codexbarUnwrapped}/bin/$binary" "\$@"
EOF
        chmod 0755 "$out/bin/$binary"
      done
    '';
  };

  # CodexBar's GNOME extension uses this helper to import the authenticated
  # Codex session from Chromium-family browsers. Package it in the system
  # profile instead of installing it into an unmanaged global Python prefix.
  codexbarCookieImporter = pkgs.python3Packages.buildPythonApplication rec {
    pname = "codexbar-cookie-importer";
    version = "1.2";
    pyproject = true;

    src = pkgs.fetchPypi {
      pname = "codexbar_cookie_importer";
      inherit version;
      hash = "sha256-Zmep9SCWcA7T7muvV29zzAtLvhEXarBcKi7zwWfYk7g=";
    };

    build-system = [ pkgs.python3Packages.setuptools ];
    dependencies = with pkgs.python3Packages; [
      cryptography
      secretstorage
    ];
    pythonImportsCheck = [ "codexbar_cookie_importer" ];

    meta = {
      description = "Import Chromium session cookies for CodexBar";
      homepage = "https://github.com/InledGroup/codexbar-gnome";
      license = pkgs.lib.licenses.mit;
      mainProgram = "codexbar-cookie-importer";
    };
  };

  # This helper is useful only for Antigravity's local HTTPS service. Keep the
  # upstream command available, but do not run it during activation: it expects
  # a mutable Debian/Fedora trust store, while NixOS trust must be declarative.
  codexbarSslHelper = pkgs.python3Packages.buildPythonApplication rec {
    pname = "codexbar-ssl-helper";
    version = "0.1.1";
    pyproject = true;

    src = pkgs.fetchPypi {
      pname = "codexbar_ssl_helper";
      inherit version;
      hash = "sha256-NXNbqwPlQQUK9Eu/XfCWvogOR755Q/zHjvDHt3coDI8=";
    };

    build-system = [ pkgs.python3Packages.setuptools ];
    pythonImportsCheck = [ "codexbar_ssl_helper" ];

    nativeBuildInputs = [ pkgs.makeWrapper ];
    postFixup = ''
      wrapProgram "$out/bin/codexbar-ssl-helper" \
        --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.iproute2 pkgs.polkit ]}
    '';

    meta = {
      description = "Discover Antigravity's local TLS certificate for CodexBar";
      homepage = "https://github.com/InledGroup/codexbar-gnome";
      license = pkgs.lib.licenses.mit;
      mainProgram = "codexbar-ssl-helper";
    };
  };

  # Pin the current GNOME Extensions release. The nixpkgs revision used by this
  # host still carries CodexBar v4, which does not match the installed v22.
  codexbarGnomeExtension = pkgs.stdenvNoCC.mkDerivation {
    pname = "gnome-shell-extension-codexbar";
    version = "22";

    src = pkgs.fetchzip {
      url = "https://extensions.gnome.org/extension-data/codexbarinled.es.v22.shell-extension.zip";
      hash = "sha256-gkxwGst3wW8QyKkYKpPEF/rmPlFmt+GuAVmeKEPFz80=";
      stripRoot = false;
    };

    nativeBuildInputs = [ pkgs.glib ];
    postPatch = ''
      # Version 22 defaults to Homebrew's path when no hard-coded candidate
      # exists, even when codexbar is available through PATH. Resolve PATH
      # first and retain the stable NixOS system-profile path as the fallback.
      substituteInPlace adapters/CliSubprocessFetcher.js \
        --replace-fail \
          'let executable = "/home/linuxbrew/.linuxbrew/bin/codexbar";' \
          'let executable = GLib.find_program_in_path("codexbar") || "/run/current-system/sw/bin/codexbar";'

      # The Linux CLI probe currently traps inside Swift Foundation while
      # parsing Claude's reset date. OAuth is supported on Linux and succeeds
      # against the same signed-in Claude account, so make it the safe default.
      substituteInPlace prefs.js \
        --replace-fail \
          'defaultCommand: "codexbar --provider claude --source cli --format json",' \
          'defaultCommand: "codexbar --provider claude --source oauth --format json",'
    '';
    buildPhase = ''
      runHook preBuild
      glib-compile-schemas --strict schemas
      runHook postBuild
    '';
    installPhase = ''
      runHook preInstall
      install -d "$out/share/gnome-shell/extensions/codexbar@inled.es"
      cp -R . "$out/share/gnome-shell/extensions/codexbar@inled.es/"
      runHook postInstall
    '';

    passthru.extensionUuid = "codexbar@inled.es";
    meta = {
      description = "Show AI provider usage metrics in the GNOME panel";
      homepage = "https://github.com/InledGroup/codexbar-gnome";
      license = pkgs.lib.licenses.gpl2Plus;
      platforms = pkgs.lib.platforms.linux;
    };
  };
in
{
  # AppIndicator gives GNOME a tray (LibrePods and other tray apps); CodexBar
  # shows the Claude and Codex quotas in the top bar. Dash to Dock, Vicinae
  # and its window management are enabled by vicinae.nix.
  home-manager.users.mariano.programs.gnome-shell = {
    enable = true;
    extensions = [
      { package = pkgs.gnomeExtensions.appindicator; }
      { package = codexbarGnomeExtension; }
    ];
  };
  # The extension's stored default is Gemini through Homebrew's codexbar path,
  # which never runs here. Claude and Codex go through the system codexbar
  # (the patch above resolves it on PATH), signed in with each tool's OAuth.
  home-manager.users.mariano.dconf.settings."org/gnome/shell/extensions/codexbar".providers =
    builtins.toJSON [
      {
        name = "Claude";
        command = "codexbar --provider claude --source oauth --format json";
      }
      {
        name = "Codex";
        command = "codexbar --provider codex --source oauth --format json";
      }
    ];

  environment.systemPackages = with pkgs; [
    # Brightness and media keys from scripts and terminals; GNOME's own keys
    # do not need them.
    brightnessctl
    playerctl
    libnotify
    librepods
    librepodsDesktopItem
    codexbar
    codexbarCookieImporter
    codexbarSslHelper
  ];

  systemd.user.tmpfiles.rules = [
    "d %h/.config/librepods 0700 - -"
    "d %h/.local/share/librepods 0700 - -"
    "f %h/.local/share/librepods/devices.json 0600 - - - {}"
  ];

  # AirPods battery and Apple-only controls, in the tray from login on.
  systemd.user.services.librepods = {
    description = "LibrePods AirPods integration";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStartPre = waitForStatusNotifierWatcher;
      ExecStart = "${librepods}/bin/librepods --start-minimized";
      Restart = "on-failure";
      RestartSec = 3;
    };
  };
}
