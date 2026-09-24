return {
  {
    "lewis6991/gitsigns.nvim",
    lazy = false,
    config = function()
      local gs = require("gitsigns")

      vim.api.nvim_create_user_command("Review", function(opts)
        if vim.bo.modified then
          vim.notify("Current buffer has unsaved changes; save or discard it first", vim.log.levels.WARN)
          return
        end

        local base = opts.args ~= "" and opts.args or "main"
        local mb = vim.fn.systemlist("git merge-base " .. base .. " HEAD")[1]
        gs.change_base(mb, true)

        local files = vim.fn.systemlist("git diff --name-only " .. mb)
        vim.fn.setqflist({}, "r", {
          title = "Review vs " .. base,
          items = vim.tbl_map(function(f)
            return { filename = f, lnum = 1 }
          end, files),
        })

        vim.cmd("only") -- single window
        vim.cmd("bdelete") -- drop current buffer, leaves an empty one
        vim.cmd("copen")
        vim.cmd("cfirst") -- open the first changed file straight away
      end, { nargs = "?" })

      vim.api.nvim_create_user_command("ReviewEnd", function()
        gs.change_base(nil, true)
        vim.cmd("cclose")
      end, {})
    end,
  },
  {
    "sindrets/diffview.nvim",
  },
}
