-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

local map = vim.keymap.set

local function line_end_after_last_char()
  return (vim.v.count > 0 and vim.v.count or "") .. "$l"
end

local pending_tag_split

function _G.__user_split_matching_tag_on_enter()
  local edit = pending_tag_split
  pending_tag_split = nil

  if not edit or not vim.api.nvim_buf_is_valid(edit.buf) then
    return
  end

  vim.api.nvim_buf_set_lines(edit.buf, edit.row - 1, edit.row, false, {
    edit.opening_line,
    edit.inner_line,
    edit.closing_line,
  })
  vim.api.nvim_win_set_cursor(0, { edit.row + 1, #edit.inner_line })
end

local tag_newline_filetypes = {
  astro = true,
  html = true,
  javascriptreact = true,
  svelte = true,
  typescriptreact = true,
  vue = true,
}

local function split_matching_tag_on_enter()
  if not tag_newline_filetypes[vim.bo.filetype] then
    return "<CR>"
  end

  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local line = vim.api.nvim_get_current_line()
  local before = line:sub(1, col)
  local after = line:sub(col + 1)
  local opening_tag = before:match("<([%w:._-]+)[^<>]*>%s*$")
  local closing_tag = after:match("^%s*</([%w:._-]+)>")

  if opening_tag and opening_tag == closing_tag then
    local outer_indent = before:match("^%s*") or ""
    local indent = vim.bo.expandtab and string.rep(" ", vim.fn.shiftwidth()) or "\t"
    local inner_line = outer_indent .. indent
    local opening_line = before:gsub("%s*$", "")
    local closing_line = outer_indent .. after:gsub("^%s*", "")

    pending_tag_split = {
      buf = vim.api.nvim_get_current_buf(),
      row = row,
      opening_line = opening_line,
      inner_line = inner_line,
      closing_line = closing_line,
    }

    return "<Cmd>lua _G.__user_split_matching_tag_on_enter()<CR>"
  end

  return "<CR>"
end

map("i", "<CR>", split_matching_tag_on_enter, { expr = true, desc = "Split matching HTML/JSX tags" })

-- Buffer switching with Tab / Shift-Tab in normal mode
map("n", "<Tab>", "<cmd>bnext<CR>", { silent = true, desc = "Next buffer" })
map("n", "<S-Tab>", "<cmd>bprevious<CR>", { silent = true, desc = "Prev buffer" })

map("n", "$", line_end_after_last_char, { expr = true, desc = "Line end after last char" })

-- VSCode-style line navigation: Alt+Left = Home (first non-blank), Alt+Right = End
map({ "n", "v" }, "<A-Left>", "^", { desc = "Line start (non-blank)" })
map("n", "<A-Right>", line_end_after_last_char, { expr = true, desc = "Line end after last char" })
map("v", "<A-Right>", "$", { desc = "Line end" })
map("i", "<A-Left>", "<C-o>^", { desc = "Line start (non-blank)" })
map("i", "<A-Right>", "<C-o>$", { desc = "Line end" })

-- Ctrl+S to save (works in normal, insert, visual)
map({ "n", "v" }, "<C-s>", "<cmd>w<CR>", { desc = "Save file" })
map("i", "<C-s>", "<Esc><cmd>w<CR>", { desc = "Save file" })

-- VSCode-style project-wide search & replace (uses grug-far, the same plugin as <leader>sr)
map({ "n", "v" }, "<C-S-h>", "<cmd>GrugFar<CR>", { desc = "Search & replace (project)" })

-- Ctrl+/ to toggle comment (handles both <C-/> and <C-_> since terminals differ)
map("n", "<C-/>", "gcc", { remap = true, desc = "Toggle comment" })
map("n", "<C-_>", "gcc", { remap = true, desc = "Toggle comment" })
map("v", "<C-/>", "gc", { remap = true, desc = "Toggle comment" })
map("v", "<C-_>", "gc", { remap = true, desc = "Toggle comment" })
map("i", "<C-/>", "<Esc>gcca", { remap = true, desc = "Toggle comment" })
map("i", "<C-_>", "<Esc>gcca", { remap = true, desc = "Toggle comment" })
