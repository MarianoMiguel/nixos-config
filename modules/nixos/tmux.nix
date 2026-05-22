{
  programs.tmux = {
    enable = true;
    terminal = "tmux-256color";
    historyLimit = 100000;
    keyMode = "vi";
    escapeTime = 10;
    clock24 = true;

    extraConfig = ''
      set -g mouse on
      set -g focus-events on
      set -g set-clipboard on
      set -g allow-passthrough on
      set -g renumber-windows on
      set -g base-index 1
      setw -g pane-base-index 1

      set -as terminal-features ",xterm-256color:RGB"
      set -as terminal-features ",tmux-256color:RGB"
      set -as terminal-features ",screen-256color:RGB"
      set -as terminal-features ",xterm*:extkeys"
      set -as terminal-features ",ghostty*:extkeys"
      set -s extended-keys on

      bind -T copy-mode-vi v send -X begin-selection
      bind -T copy-mode-vi y send -X copy-pipe-and-cancel "wl-copy"
      bind -T copy-mode-vi MouseDragEnd1Pane send -X copy-pipe-and-cancel "wl-copy"

      bind r source-file /etc/tmux.conf \; display-message "Reloaded tmux config"
    '';
  };
}
