{ ... }:

{
  system.activationScripts.wallpapers.text = ''
    install -d -m 0755 -o mariano -g users /home/mariano/Pictures/Wallpapers

    for wallpaper in ${../../assets/wallpapers}/*; do
      install -m 0644 -o mariano -g users "$wallpaper" /home/mariano/Pictures/Wallpapers/
    done
  '';
}
