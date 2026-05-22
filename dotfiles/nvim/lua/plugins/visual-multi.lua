-- VSCode-style multi-cursor: Ctrl+D selects word, hit again for next occurrence
return {
  {
    "mg979/vim-visual-multi",
    branch = "master",
    event = "VeryLazy",
    init = function()
      vim.g.VM_maps = {
        ["Find Under"] = "<C-n>",
        ["Find Subword Under"] = "<C-n>",
        ["Select All"] = "<C-S-n>",
        ["Skip Region"] = "<C-x>",
      }
      vim.g.VM_set_statusline = 0
      vim.g.VM_silent_exit = 1
    end,
  },
}
