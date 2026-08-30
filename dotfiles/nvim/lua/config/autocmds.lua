-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

require("config.transparent").setup()

vim.api.nvim_create_autocmd("FileType", {
  pattern = "qf",
  callback = function(event)
    vim.keymap.set("n", "dd", function()
      local qf_list = vim.fn.getqflist()
      local current_line = vim.fn.line(".")

      if qf_list[current_line] then
        table.remove(qf_list, current_line)
        vim.fn.setqflist(qf_list, "r")

        if #qf_list > 0 then
          vim.cmd("cc " .. math.min(current_line, #qf_list))
        end

        vim.cmd("copen")
      end
    end, { buffer = event.buf, silent = true, desc = "Delete item from quickfix list" })
  end,
})
