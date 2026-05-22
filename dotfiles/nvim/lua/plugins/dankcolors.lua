return {
	{
		"RRethy/base16-nvim",
		priority = 1000,
		config = function()
			require('base16-colorscheme').setup({
				base00 = '#1f1d2e',
				base01 = '#1f1d2e',
				base02 = '#908a96',
				base03 = '#908a96',
				base04 = '#eae3f2',
				base05 = '#fbf8ff',
				base06 = '#fbf8ff',
				base07 = '#fbf8ff',
				base08 = '#ff9fb1',
				base09 = '#ff9fb1',
				base0A = '#ddc2fe',
				base0B = '#a5ffba',
				base0C = '#eddfff',
				base0D = '#ddc2fe',
				base0E = '#e3cdff',
				base0F = '#e3cdff',
			})

			vim.api.nvim_set_hl(0, 'Visual', {
				bg = '#908a96',
				fg = '#fbf8ff',
				bold = true
			})
			vim.api.nvim_set_hl(0, 'Statusline', {
				bg = '#ddc2fe',
				fg = '#1f1d2e',
			})
			vim.api.nvim_set_hl(0, 'LineNr', { fg = '#908a96' })
			vim.api.nvim_set_hl(0, 'CursorLineNr', { fg = '#eddfff', bold = true })

			vim.api.nvim_set_hl(0, 'Statement', {
				fg = '#e3cdff',
				bold = true
			})
			vim.api.nvim_set_hl(0, 'Keyword', { link = 'Statement' })
			vim.api.nvim_set_hl(0, 'Repeat', { link = 'Statement' })
			vim.api.nvim_set_hl(0, 'Conditional', { link = 'Statement' })

			vim.api.nvim_set_hl(0, 'Function', {
				fg = '#ddc2fe',
				bold = true
			})
			vim.api.nvim_set_hl(0, 'Macro', {
				fg = '#ddc2fe',
				italic = true
			})
			vim.api.nvim_set_hl(0, '@function.macro', { link = 'Macro' })

			vim.api.nvim_set_hl(0, 'Type', {
				fg = '#eddfff',
				bold = true,
				italic = true
			})
			vim.api.nvim_set_hl(0, 'Structure', { link = 'Type' })

			vim.api.nvim_set_hl(0, 'String', {
				fg = '#a5ffba',
				italic = true
			})

			vim.api.nvim_set_hl(0, 'Operator', { fg = '#eae3f2' })
			vim.api.nvim_set_hl(0, 'Delimiter', { fg = '#eae3f2' })
			vim.api.nvim_set_hl(0, '@punctuation.bracket', { link = 'Delimiter' })
			vim.api.nvim_set_hl(0, '@punctuation.delimiter', { link = 'Delimiter' })

			vim.api.nvim_set_hl(0, 'Comment', {
				fg = '#908a96',
				italic = true
			})

			local current_file_path = vim.fn.stdpath("config") .. "/lua/plugins/dankcolors.lua"
			if not _G._matugen_theme_watcher then
				local uv = vim.uv or vim.loop
				_G._matugen_theme_watcher = uv.new_fs_event()
				_G._matugen_theme_watcher:start(current_file_path, {}, vim.schedule_wrap(function()
					local new_spec = dofile(current_file_path)
					if new_spec and new_spec[1] and new_spec[1].config then
						new_spec[1].config()
						print("Theme reload")
					end
				end))
			end
		end
	}
}
