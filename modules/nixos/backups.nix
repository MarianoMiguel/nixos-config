{
  config,
  lib,
  ...
}:

let
  stateDir = "/var/lib/restic";
  home = config.users.users.mariano.home;
in
{
  # Nightly restic snapshots of the home directory. The destination and its
  # credentials deliberately live outside the repository, in root-only files
  # under /var/lib/restic (see README "Backups"):
  #   repository   a restic repository URL: a mounted disk path, sftp:, rest:,
  #                s3:, b2:, ...
  #   environment  KEY=value credentials that URL needs, if any
  #   password     the repository encryption password
  # Until the repository and password files exist the timer fires but the job
  # is skipped, so a fresh install never fails on a target it does not have.
  services.restic.backups.home = {
    user = "root";
    paths = [ home ];
    repositoryFile = "${stateDir}/repository";
    passwordFile = "${stateDir}/password";
    environmentFile = "${stateDir}/environment";
    initialize = true;
    inhibitsSleep = true;
    exclude = [
      # Caches and package stores that any tool rebuilds on demand.
      "${home}/.cache"
      "${home}/.npm/_cacache"
      "${home}/.nvm"
      "${home}/.cargo/registry"
      "${home}/.rustup"
      "${home}/.gradle/caches"
      "${home}/.local/state/nix"
      "**/node_modules"
      "**/.direnv"
      # Container images, game libraries and model weights: large, restorable
      # from their origin, and not personal data.
      "${home}/.local/share/docker"
      "${home}/.local/share/containers"
      "${home}/.local/share/flatpak"
      "${home}/.local/share/Steam"
      "${home}/.steam"
      "${home}/.android/avd"
      "${home}/.lmstudio/models"
      "${home}/.ollama"
      "${home}/.local/share/Trash"
      # The encrypted USB payload is itself a backup artifact.
      "${home}/nixos-usb-payload"
    ];
    extraBackupArgs = [
      "--one-file-system"
      "--exclude-caches"
    ];
    timerConfig = {
      OnCalendar = "03:00";
      RandomizedDelaySec = "1h";
      Persistent = true;
    };
    pruneOpts = [
      "--keep-daily 7"
      "--keep-weekly 4"
      "--keep-monthly 6"
    ];
  };

  systemd.services.restic-backups-home.unitConfig.ConditionPathExists = [
    "${stateDir}/repository"
    "${stateDir}/password"
  ];

  # The unit reads the environment file unconditionally, so keep an empty one
  # around for repositories that need no credentials (local paths, rest:
  # over Tailscale).
  systemd.tmpfiles.rules = [
    "d ${stateDir} 0700 root root -"
    "f ${stateDir}/environment 0600 root root -"
  ];
}
