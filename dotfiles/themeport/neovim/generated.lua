return {
  {
    "bjarneo/aether.nvim",
    branch = "v3",
    name = "aether",
    priority = 1000,
    opts = {
      colors = {
        bg = "#14131e",
        dark_bg = "#10101a",
        darker_bg = "#0c0c14",
        lighter_bg = "#26233a",

        fg = "#e0def4",
        dark_fg = "#908caa",
        light_fg = "#e0def4",
        bright_fg = "#e0def4",
        muted = "#6e6a86",

        red = "#eb6f92",
        yellow = "#f6c177",
        orange = "#f6c177",
        green = "#31748f",
        cyan = "#9ccfd8",
        blue = "#31748f",
        magenta = "#c4a7e7",
        brown = "#7b603c",

        bright_red = "#eb6f92",
        bright_yellow = "#f6c177",
        bright_green = "#31748f",
        bright_cyan = "#9ccfd8",
        bright_blue = "#31748f",
        bright_magenta = "#c4a7e7",

        accent = "#ebbcba",
        cursor = "#e0def4",
        foreground = "#e0def4",
        background = "#14131e",
        selection = "#403d52",
        selection_foreground = "#e0def4",
        selection_background = "#403d52",
      },
    },
  },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "aether",
    },
  },
}
