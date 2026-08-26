return {
  "stevearc/oil.nvim",
  -- Optional dependencies
  dependencies = { { "nvim-mini/mini.icons", opts = {} } },
  -- dependencies = { "nvim-tree/nvim-web-devicons" }, -- use if you prefer nvim-web-devicons
  -- Lazy loading is not recommended because it is very tricky to make it work correctly in all situations.
  lazy = false,
  config = function()
    require("oil").setup({
      default_file_explorer = true,
      view_options = { show_hidden = true },

      float = {
        padding = 2,
        max_width = 120,
        max_height = 40,
        border = "rounded",
        -- where the preview lands relative to the oil window
        preview_split = "below", -- "auto"|"left"|"right"|"above"|"below"
      },

      preview_win = {
        update_on_cursor_moved = true, -- live preview while you move
        preview_method = "fast_scratch", -- "load"|"scratch"|"fast_scratch"
        disable_preview = function(filename) -- skip things that would lag
          return filename:match("%.%w*$") and filename:match("%.(png|jpe?g|gif|pdf)$") ~= nil
        end,
        win_options = { number = false, relativenumber = false, signcolumn = "no" },
      },
    })
    vim.keymap.set("n", "-", "<CMD>Oil --float --preview<CR>", { desc = "Open parent directory" })
  end,
}
