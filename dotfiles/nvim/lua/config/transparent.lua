local M = {}

local transparent_groups = {
  "Normal",
  "NormalNC",
  "NormalFloat",
  "FloatBorder",
  "FloatTitle",
  "FloatFooter",
  "SignColumn",
  "FoldColumn",
  "Folded",
  "LineNr",
  "CursorLine",
  "CursorLineNr",
  "CursorLineFold",
  "CursorLineSign",
  "EndOfBuffer",
  "WinSeparator",
  "VertSplit",
  "StatusLine",
  "StatusLineNC",
  "TabLine",
  "TabLineFill",
  "TabLineSel",
  "WinBar",
  "WinBarNC",
  "MsgArea",
  "MsgSeparator",
  "ModeMsg",
  "NormalSB",
  "NonText",
  "Whitespace",
  "Pmenu",
  "PmenuKind",
  "PmenuExtra",
  "PmenuSbar",
  "PmenuThumb",
}

local transparent_prefixes = {
  "Aerial",
  "Alpha",
  "BlinkCmp",
  "BufferLine",
  "Cmp",
  "Dashboard",
  "Diffview",
  "Dressing",
  "Fzf",
  "FzfLua",
  "GrugFar",
  "Lazy",
  "Mason",
  "Mini",
  "NeoTree",
  "Neogit",
  "Noice",
  "Notify",
  "NvimTree",
  "Oil",
  "Outline",
  "Snacks",
  "Telescope",
  "TreesitterContext",
  "Trouble",
  "WhichKey",
  "lualine_",
}

local scheduled = false

local function has_transparent_prefix(name)
  for _, prefix in ipairs(transparent_prefixes) do
    if name:sub(1, #prefix) == prefix then
      return true
    end
  end
  return false
end

local function clear_bg(name, create_if_missing)
  local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
  if not ok then
    return
  end

  if vim.tbl_isempty(hl) then
    if create_if_missing then
      pcall(vim.api.nvim_set_hl, 0, name, { bg = "NONE" })
    end
    return
  end

  hl.bg = nil
  hl.ctermbg = nil
  hl.blend = nil
  pcall(vim.api.nvim_set_hl, 0, name, hl)
end

local function clear_matching_groups()
  local ok, groups = pcall(vim.api.nvim_get_hl, 0, {})
  if ok then
    for name in pairs(groups) do
      if has_transparent_prefix(name) then
        clear_bg(name, false)
      end
    end
    return
  end

  for _, name in ipairs(vim.fn.getcompletion("", "highlight")) do
    if has_transparent_prefix(name) then
      clear_bg(name, false)
    end
  end
end

function M.apply()
  vim.opt.winblend = 0
  vim.opt.pumblend = 0

  for _, name in ipairs(transparent_groups) do
    clear_bg(name, true)
  end

  clear_matching_groups()
end

function M.schedule()
  if scheduled then
    return
  end

  scheduled = true
  vim.defer_fn(function()
    scheduled = false
    M.apply()
  end, 25)
end

local function watch_generated_theme()
  if _G._transparent_theme_watcher then
    return
  end

  local uv = vim.uv or vim.loop
  local path = vim.fn.stdpath("config") .. "/lua/plugins/dankcolors.lua"
  if not uv.fs_stat(path) then
    return
  end

  local watcher = uv.new_fs_event()
  local ok = watcher
    and pcall(function()
      watcher:start(path, {}, vim.schedule_wrap(M.schedule))
    end)

  if ok then
    _G._transparent_theme_watcher = watcher
  elseif watcher then
    watcher:close()
  end
end

function M.setup()
  local group = vim.api.nvim_create_augroup("user_transparent_background", { clear = true })

  vim.api.nvim_create_autocmd({ "ColorScheme", "UIEnter", "WinEnter", "BufWinEnter" }, {
    group = group,
    callback = M.schedule,
  })

  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = { "VeryLazy", "LazyVimStarted", "LazyLoad" },
    callback = M.schedule,
  })

  pcall(vim.api.nvim_del_user_command, "TransparentBackground")
  vim.api.nvim_create_user_command("TransparentBackground", M.apply, {})

  watch_generated_theme()
  M.schedule()
end

return M
