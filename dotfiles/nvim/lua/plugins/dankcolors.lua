return {
	{
		"RRethy/base16-nvim",
		priority = 1000,
		config = function()
			require("base16-colorscheme").setup({
				base00 = "#1a1b26",
				base01 = "#1a1b26",
				base02 = "#9498a0",
				base03 = "#9498a0",
				base04 = "#565f89",
				base05 = "#a9b1d6",
				base06 = "#a9b1d6",
				base07 = "#a9b1d6",
				base08 = "#ff7198",
				base09 = "#ff9eb9",
				base0A = "#fff871",
				base0B = "#7af78c",
				base0C = "#7aa2f7",
				base0D = "#5c89ea",
				base0E = "#082a72",
				base0F = "#a4c1ff",
			})

			vim.api.nvim_set_hl(0, "Visual", {
				bg = "#394669",
				fg = "#a9b1d6",
				bold = true,
			})
			vim.api.nvim_set_hl(0, "Statusline", {
				bg = "#7aa2f7",
				fg = "#c0caf5",
			})
			vim.api.nvim_set_hl(0, "LineNr", { fg = "#414868" })
			vim.api.nvim_set_hl(0, "CursorLineNr", { fg = "#7aa2f7", bold = true })

			vim.api.nvim_set_hl(0, "Statement", {
				fg = "#7aa2f7",
				bold = true,
			})
			vim.api.nvim_set_hl(0, "Keyword", { link = "Statement" })
			vim.api.nvim_set_hl(0, "Repeat", { link = "Statement" })
			vim.api.nvim_set_hl(0, "Conditional", { link = "Statement" })

			vim.api.nvim_set_hl(0, "Function", {
				fg = "#7aa2f7",
				bold = true,
			})
			vim.api.nvim_set_hl(0, "Macro", {
				fg = "#449dab",
				italic = true,
			})
			vim.api.nvim_set_hl(0, "@function.macro", { link = "Macro" })

			vim.api.nvim_set_hl(0, "Type", {
				fg = "#9ece6a",
				bold = true,
				italic = true,
			})
			vim.api.nvim_set_hl(0, "Structure", { link = "Type" })

			vim.api.nvim_set_hl(0, "String", {
				fg = "#7af78c",
				italic = true,
			})

			vim.api.nvim_set_hl(0, "Operator", { fg = "#a9b1d6" })
			vim.api.nvim_set_hl(0, "Delimiter", { fg = "#a9b1d6" })
			vim.api.nvim_set_hl(0, "@punctuation.bracket", { link = "Delimiter" })
			vim.api.nvim_set_hl(0, "@punctuation.delimiter", { link = "Delimiter" })

			vim.api.nvim_set_hl(0, "Comment", {
				fg = "#414868",
				italic = true,
			})

			local current_file_path = vim.fn.stdpath("config") .. "/lua/plugins/dankcolors.lua"
			if not _G._matugen_theme_watcher then
				local uv = vim.uv or vim.loop
				local watcher = uv.new_fs_event()
				local timer = uv.new_timer()
				local function restart()
					pcall(function()
						watcher:stop()
					end)
					pcall(function()
						watcher:start(current_file_path, {}, vim.schedule_wrap(function()
							timer:stop()
							timer:start(100, 0, vim.schedule_wrap(function()
								package.loaded["plugins.dankcolors"] = nil
								local new_spec = dofile(current_file_path)
								if new_spec and new_spec[1] and new_spec[1].config then
									new_spec[1].config()
									print("Theme reload")
								end
								restart()
							end))
						end))
					end)
				end
				_G._matugen_theme_watcher = { watcher = watcher, timer = timer }
				restart()
			end
		end,
	},
}
