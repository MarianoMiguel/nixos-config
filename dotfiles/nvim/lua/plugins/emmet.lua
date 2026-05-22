-- Emmet HTML/JSX abbreviation expansion.
-- Triggers: <C-y>, or <C-x> in insert mode.
-- Example: type `div.foo>span.bar` then <C-x> to expand to full HTML
local emmet_filetypes = {
  "html",
  "css",
  "scss",
  "javascriptreact",
  "typescript",
  "typescript.tsx",
  "typescriptreact",
  "tsx",
  "vue",
  "svelte",
  "astro",
}
local emmet_expand = '<C-r>=emmet#util#closePopup()<CR><C-r>=emmet#expandAbbr(0, "")<CR>'

local function map_emmet_expand(buf)
  vim.keymap.set("i", "<C-x>", emmet_expand, {
    buffer = buf,
    silent = true,
    desc = "Expand Emmet abbreviation",
  })
end

return {
  {
    "mattn/emmet-vim",
    ft = emmet_filetypes,
    init = function()
      vim.g.user_emmet_leader_key = "<C-y>"
      vim.g.user_emmet_settings = {
        javascript = { extends = "jsx" },
        typescript = { extends = "jsx" },
      }
    end,
    config = function()
      map_emmet_expand(0)
      vim.api.nvim_create_autocmd("FileType", {
        pattern = emmet_filetypes,
        callback = function(args)
          map_emmet_expand(args.buf)
        end,
      })
    end,
  },
}
