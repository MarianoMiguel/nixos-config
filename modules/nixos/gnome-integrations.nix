{ librepods-rust, pkgs, ... }:

let
  system = pkgs.stdenv.hostPlatform.system;
  librepods = librepods-rust.packages.${system}.default;
  librepodsDesktopItem = pkgs.makeDesktopItem {
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
      hash = "sha256-Mx2Zs5X2ZniPmqCB5Dk66yYP7DlE5sh/FRzp1mh7J04=";
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
  };

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
  };

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
      substituteInPlace adapters/CliSubprocessFetcher.js \
        --replace-fail \
          'let executable = "/home/linuxbrew/.linuxbrew/bin/codexbar";' \
          'let executable = GLib.find_program_in_path("codexbar") || "/run/current-system/sw/bin/codexbar";'
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
  };
in
{
  environment.systemPackages = [
    librepods
    librepodsDesktopItem
    codexbar
    codexbarCookieImporter
    codexbarSslHelper
  ];

  home-manager.users.mariano.programs.gnome-shell = {
    enable = true;
    extensions = [
      { package = pkgs.gnomeExtensions.appindicator; }
      { package = codexbarGnomeExtension; }
      { package = pkgs.gnomeExtensions.impatience; }
    ];
  };

  home-manager.users.mariano.dconf.settings = {
    "org/gnome/shell/extensions/net/gfxmonk/impatience"."speed-factor" = 0.25;
  };

  systemd.user.tmpfiles.rules = [
    "d %h/.config/librepods 0700 - -"
    "d %h/.local/share/librepods 0700 - -"
    "f %h/.local/share/librepods/devices.json 0600 - - - {}"
  ];

  systemd.user.services.librepods = {
    description = "LibrePods AirPods integration";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    unitConfig.ConditionEnvironment = "XDG_CURRENT_DESKTOP=GNOME";
    serviceConfig = {
      ExecStartPre = waitForStatusNotifierWatcher;
      ExecStart = "${librepods}/bin/librepods --start-minimized";
      Restart = "on-failure";
      RestartSec = 3;
    };
  };
}
