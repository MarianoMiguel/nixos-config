return {
  -- Disable Neo-tree (LazyVim default) entirely
  { "nvim-neo-tree/neo-tree.nvim", enabled = false },

  -- Enable and configure nvim-tree
  {
    "nvim-tree/nvim-tree.lua",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    opts = {
      git = {
        enable = true,
        ignore = false, -- do not hide gitignored files
      },
      filters = {
        dotfiles = false,    -- show dotfiles
        git_ignored = false, -- show files ignored by git
      },
    },
  },
}

