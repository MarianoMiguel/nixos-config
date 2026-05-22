{ ... }:

{
  system.activationScripts.ghosttyConfig.text = ''
    install -d -m 0755 -o mariano -g users /home/mariano/.config/ghostty
    install -m 0644 -o mariano -g users ${../../dotfiles/ghostty/config.ghostty} /home/mariano/.config/ghostty/config.ghostty
  '';
}
