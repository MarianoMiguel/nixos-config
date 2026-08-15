return {
  {
    "bjarneo/aether.nvim",
    branch = "v3",
    name = "aether",
    priority = 1000,
    opts = {
      colors = {
        bg = "#1C1C1E",
        dark_bg = "#151516",
        darker_bg = "#0e0e0f",
        lighter_bg = "#1C1C1E",

        fg = "#FFFFFF",
        dark_fg = "#2C2C2E",
        light_fg = "#FFFFFF",
        bright_fg = "#FFFFFF",
        muted = "#2C2C2E",

        red = "#F2F2F2",
        yellow = "#6A6A6A",
        orange = "#6A6A6A",
        green = "#FFDD80",
        cyan = "#F2F2F2",
        blue = "#7A7A7A",
        magenta = "#8A8A8A",
        brown = "#353535",

        bright_red = "#F2F2F2",
        bright_yellow = "#A6A6A6",
        bright_green = "#FFE9B3",
        bright_cyan = "#FFFFFF",
        bright_blue = "#B8B8B8",
        bright_magenta = "#CCCCCC",

        accent = "#7A7A7A",
        cursor = "#FFFFFF",
        foreground = "#FFFFFF",
        background = "#1C1C1E",
        selection = "#808080",
        selection_foreground = "#FFFFFF",
        selection_background = "#808080",
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
