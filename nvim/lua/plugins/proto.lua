-- LazyVim has no lang extra for protobuf, so .proto support is assembled here.
-- Treesitter carries the grammar; buf is the language server (format, lint and
-- diagnostics), and mason installs both it and the `buf` binary behind it --
-- protoc itself only compiles, it is not an LSP and nvim never calls it.
return {
  {
    "nvim-treesitter/nvim-treesitter",
    opts = { ensure_installed = { "proto" } },
  },
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = { buf_ls = {} },
    },
  },
  {
    "mason-org/mason.nvim",
    opts = { ensure_installed = { "buf" } },
  },
}
