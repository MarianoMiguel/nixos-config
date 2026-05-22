return {
  {
    "folke/flash.nvim",
    event = "VeryLazy",
    opts = {},
    keys = {
      {
        "<CR>",
        mode = { "n", "x", "o" },
        function()
          local ft = vim.bo.filetype
          if ft == "alpha" or ft == "dashboard" then
            local keys = vim.api.nvim_replace_termcodes("<CR>", true, false, true)
            vim.api.nvim_feedkeys(keys, "n", false)
            return
          end
          require("flash").jump()
        end,
        desc = "Flash Jump",
      },
    },
  },
}
