return {
	{
		"RRethy/base16-nvim",
		priority = 1000,
		config = function()
			require("base16-colorscheme").setup({
				base00 = "#1c1c1e",
				base01 = "#1C1C1E",
				base02 = "#827b7b",
				base03 = "#827b7b",
				base04 = "#2c2c2e",
				base05 = "#ffffff",
				base06 = "#ffffff",
				base07 = "#ffffff",
				base08 = "#c36c69",
				base09 = "#ac6b6b",
				base0A = "#9f8e47",
				base0B = "#609351",
				base0C = "#7A7A7A",
				base0D = "#858585",
				base0E = "#383838",
				base0F = "#9e9e9e",
			})

			vim.api.nvim_set_hl(0, "Visual", {
				bg = "#3a3a3b",
				fg = "#ffffff",
				bold = true,
			})
			vim.api.nvim_set_hl(0, "Statusline", {
				bg = "#7a7a7a",
				fg = "#ffffff",
			})
			vim.api.nvim_set_hl(0, "LineNr", { fg = "#2c2c2e" })
			vim.api.nvim_set_hl(0, "CursorLineNr", { fg = "#7a7a7a", bold = true })

			vim.api.nvim_set_hl(0, "Statement", {
				fg = "#7a7a7a",
				bold = true,
			})
			vim.api.nvim_set_hl(0, "Keyword", { link = "Statement" })
			vim.api.nvim_set_hl(0, "Repeat", { link = "Statement" })
			vim.api.nvim_set_hl(0, "Conditional", { link = "Statement" })

			vim.api.nvim_set_hl(0, "Function", {
				fg = "#7a7a7a",
				bold = true,
			})
			vim.api.nvim_set_hl(0, "Macro", {
				fg = "#f2f2f2",
				italic = true,
			})
			vim.api.nvim_set_hl(0, "@function.macro", { link = "Macro" })

			vim.api.nvim_set_hl(0, "Type", {
				fg = "#ffdd80",
				bold = true,
				italic = true,
			})
			vim.api.nvim_set_hl(0, "Structure", { link = "Type" })

			vim.api.nvim_set_hl(0, "String", {
				fg = "#609351",
				italic = true,
			})

			vim.api.nvim_set_hl(0, "Operator", { fg = "#ffffff" })
			vim.api.nvim_set_hl(0, "Delimiter", { fg = "#ffffff" })
			vim.api.nvim_set_hl(0, "@punctuation.bracket", { link = "Delimiter" })
			vim.api.nvim_set_hl(0, "@punctuation.delimiter", { link = "Delimiter" })

			vim.api.nvim_set_hl(0, "Comment", {
				fg = "#2c2c2e",
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
