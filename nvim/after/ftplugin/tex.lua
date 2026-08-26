vim.cmd("compiler tex") -- gives you a LaTeX-aware 'errorformat'

local function build()
  vim.cmd("silent! wall")

  -- capture these now: the callback runs later, possibly in another buffer
  local efm = vim.bo.errorformat
  local root = vim.fs.root(0, "Makefile") or vim.fn.getcwd()

  vim.system({ "make" }, { cwd = root, text = true }, function(out)
    vim.schedule(function()
      if out.code == 0 then
        vim.cmd("cclose")
        vim.notify("make: ok")
        return
      end

      vim.fn.setqflist({}, " ", {
        title = "make",
        lines = vim.split((out.stdout or "") .. (out.stderr or ""), "\n", { trimempty = true }),
        efm = efm,
      })
      vim.cmd("botright copen")
    end)
  end)
end

vim.keymap.set("n", "<leader>m", build, { buffer = true, desc = "Save all + make" })
