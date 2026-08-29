-- Seamless movement between nvim splits and tmux panes with <C-h/j/k/l>.
-- The tmux half of this lives in tmux/tmux.conf.
--
-- Declaring the mappings under `keys` matters: LazyVim's safe_keymap_set skips
-- any lhs a lazy keys handler already owns, so this takes <C-h>/<C-l> over from
-- LazyVim's plain <C-w>h/<C-w>l without having to unmap anything.
return {
  "christoomey/vim-tmux-navigator",
  cmd = {
    "TmuxNavigateLeft",
    "TmuxNavigateDown",
    "TmuxNavigateUp",
    "TmuxNavigateRight",
    "TmuxNavigatePrevious",
    "TmuxNavigatorProcessList",
  },
  keys = {
    { "<C-h>", "<cmd><C-U>TmuxNavigateLeft<cr>", desc = "Go to Left Window/Pane" },
    { "<C-j>", "<cmd><C-U>TmuxNavigateDown<cr>", desc = "Go to Lower Window/Pane" },
    { "<C-k>", "<cmd><C-U>TmuxNavigateUp<cr>", desc = "Go to Upper Window/Pane" },
    { "<C-l>", "<cmd><C-U>TmuxNavigateRight<cr>", desc = "Go to Right Window/Pane" },
    { "<C-\\>", "<cmd><C-U>TmuxNavigatePrevious<cr>", desc = "Go to Previous Window/Pane" },
  },
}
