return {
	{
		"RRethy/base16-nvim",
		priority = 1000,
		config = function()
			require("base16-colorscheme").setup({
				base00 = "{{colors.background.default.hex}}",
				base01 = "{{dank16.color0.default.hex}}",
				base02 = "{{dank16.color8.default.hex}}",
				base03 = "{{dank16.color8.default.hex}}",
				base04 = "{{colors.on_surface_variant.default.hex}}",
				base05 = "{{colors.on_surface.default.hex}}",
				base06 = "{{colors.on_surface.default.hex}}",
				base07 = "{{colors.on_surface.default.hex}}",
				base08 = "{{dank16.color1.default.hex}}",
				base09 = "{{dank16.color9.default.hex}}",
				base0A = "{{dank16.color3.default.hex}}",
				base0B = "{{dank16.color2.default.hex}}",
				base0C = "{{dank16.color6.default.hex}}",
				base0D = "{{dank16.color4.default.hex}}",
				base0E = "{{dank16.color5.default.hex}}",
				base0F = "{{dank16.color13.default.hex}}",
			})

			vim.api.nvim_set_hl(0, "Visual", {
				bg = "{{colors.primary_container.default.hex}}",
				fg = "{{colors.on_surface.default.hex}}",
				bold = true,
			})
			vim.api.nvim_set_hl(0, "Statusline", {
				bg = "{{colors.primary.default.hex}}",
				fg = "{{colors.on_primary.default.hex}}",
			})
			vim.api.nvim_set_hl(0, "LineNr", { fg = "{{colors.outline.default.hex}}" })
			vim.api.nvim_set_hl(0, "CursorLineNr", { fg = "{{colors.primary.default.hex}}", bold = true })

			vim.api.nvim_set_hl(0, "Statement", {
				fg = "{{colors.primary.default.hex}}",
				bold = true,
			})
			vim.api.nvim_set_hl(0, "Keyword", { link = "Statement" })
			vim.api.nvim_set_hl(0, "Repeat", { link = "Statement" })
			vim.api.nvim_set_hl(0, "Conditional", { link = "Statement" })

			vim.api.nvim_set_hl(0, "Function", {
				fg = "{{colors.primary.default.hex}}",
				bold = true,
			})
			vim.api.nvim_set_hl(0, "Macro", {
				fg = "{{colors.secondary.default.hex}}",
				italic = true,
			})
			vim.api.nvim_set_hl(0, "@function.macro", { link = "Macro" })

			vim.api.nvim_set_hl(0, "Type", {
				fg = "{{colors.tertiary.default.hex}}",
				bold = true,
				italic = true,
			})
			vim.api.nvim_set_hl(0, "Structure", { link = "Type" })

			vim.api.nvim_set_hl(0, "String", {
				fg = "{{dank16.color2.default.hex}}",
				italic = true,
			})

			vim.api.nvim_set_hl(0, "Operator", { fg = "{{colors.on_surface.default.hex}}" })
			vim.api.nvim_set_hl(0, "Delimiter", { fg = "{{colors.on_surface.default.hex}}" })
			vim.api.nvim_set_hl(0, "@punctuation.bracket", { link = "Delimiter" })
			vim.api.nvim_set_hl(0, "@punctuation.delimiter", { link = "Delimiter" })

			vim.api.nvim_set_hl(0, "Comment", {
				fg = "{{colors.outline.default.hex}}",
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
