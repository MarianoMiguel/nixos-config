{ pkgs, ... }:

{
  users.defaultUserShell = pkgs.zsh;

  users.users.mariano = {
    isNormalUser = true;
    description = "Mariano";
    extraGroups = [
      "docker"
      "networkmanager"
      "wheel"
    ];
    packages = with pkgs; [
      kdePackages.kate
    ];
  };

  programs.zsh = {
    enable = true;
    autosuggestions.enable = true;
    syntaxHighlighting.enable = true;
    ohMyZsh = {
      enable = true;
      theme = "robbyrussell";
      plugins = [
        "git"
        "sudo"
      ];
    };
    interactiveShellInit = ''
      eval "$(${pkgs.mise}/bin/mise activate zsh)"
    '';
  };
}
