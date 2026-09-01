# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Personal Fedora workstation provisioning: dnf package installs plus dotfiles, for a Sway/Wayland
desktop with Alacritty + fish + tmux + Neovim (LazyVim). Not a git repository and has no build,
test, or lint tooling — the "programs" are bash/python scripts and declarative config files.

## Layout and execution model

Each top-level directory is an independent, idempotent module with its own `install.sh`:

| Module | Installs | Symlinks into |
| --- | --- | --- |
| `base/` | core CLI tooling, RPM Fusion repos | — |
| `containers/` | docker-ce, k3s (server, kubeconfig mode 644), writes `~/.kube/config` | — |
| `wm/` | sway, waybar, mako, pipewire, mesa/vulkan, bluetooth, media | `~/.config/{sway,waybar,mako,fuzzel}` |
| `alacritty/` | — | `~/.config/alacritty` |
| `fish/` | `chsh -s fish` | `~/.config/fish` |
| `tmux/` | tmux | `~/.config/tmux` |
| `nvim/` | neovim, rustup, uv, build toolchain | `~/.config/nvim` |
| `fonts/` | — | `~/.local/share/fonts` |
| `scripts/` | — | `~/scripts` |
| `desktop-apps/` | one script per app; **no `install.sh`**, run individually | — |

There is no top-level bootstrap script. Modules are run by hand and roughly in the order above
(`base` first; `nvim/install.sh` sources `~/.cargo/env`, so it depends on rustup being present or
installing it itself).

### The symlink convention

Every module links its *directory* into place with `ln -vfsn <repo dir> <target>`, so editing files
in this repo is immediately live — there is no copy/apply step. Two consequences:

- Never replace a symlinked target with a real directory; that breaks the whole model.
- The `-n` (`--no-dereference`) is load-bearing. Without it `ln` follows a target that is already
  a symlink-to-directory and creates the link *inside* it, producing a nested `<module>/<module>`
  self-symlink instead of replacing the link. That is how `nvim/nvim` got created. With `-n` a
  rerun replaces the symlink, and a target that is a *real* directory fails loudly rather than
  nesting silently.

`wm/install.sh` runs its symlinks *before* its `dnf` calls, on purpose: linking depends on no
package, and under `set -e` a failed install would otherwise skip every link.

`fish/config.fish` puts `~/scripts` on `PATH`, so everything in `scripts/` is a global command.

## Scripts

`scripts/` holds standalone executables (no extensions, shebang-dispatched — bash and python3):

- `tmux-sessionizer` — fzf over git repos 1–2 levels under `$PROJECTS_ROOT` (default `~/Projects`);
  creates a session with window 1 running `nvim .` plus 3 shell windows, or attaches if it exists.
- `pstats` — scans a tree for repos with uncommitted/unpushed work; exits 1 if anything needs
  attention. Root overridable via `GITCHECK_ROOT`.
- `k3s-up` / `k3s-down` — on-demand k3s lifecycle. k3s is deliberately **not** enabled at boot;
  `k3s-down` runs `k3s-killall.sh` and verifies only `k8s.io`-namespace shims are gone (Docker's
  `moby` shims must survive).
- `screenshot`, `screenshot-window`, `screen-record` — grim/slurp/ffmpeg, save + `wl-copy` + notify.
- `playvid`, `gentasks`, `calendar_svg` — fzf video picker; recurring-task markdown generator;
  SVG month calendar to clipboard.

## Neovim

Standard LazyVim starter (`init.lua` → `lua/config/lazy.lua`). Language extras are declared in
`lazyvim.json`, not in Lua. Local customizations live in `lua/plugins/` (gruvbox colorscheme, oil.nvim
as file explorer with `-` as the keymap, bufferline and snacks-explorer disabled in `disabled.lua`,
vim-tmux-navigator in `tmux-navigator.lua` — its `keys` spec is what takes `<C-h>`/`<C-l>` over from
LazyVim, and its tmux counterpart is the `is_vim` block in `tmux/tmux.conf`).

`lua/config/remote_clipboard.lua` is the one non-trivial piece: when running under tmux, SSH, or
herdr it installs a custom `vim.g.clipboard` that always emits OSC 52 on yank (so copies reach the
client machine) while preferring local `wl-copy`/`wl-paste` when a Wayland display exists. It walks
`/proc` ancestors to detect herdr. Alacritty cooperates via `osc52 = "CopyPaste"` and CSI-u encodings
for Shift/Alt-Shift+Return in `alacritty/alacritty.toml`.

`after/ftplugin/tex.lua` binds `<leader>m` to save-all + async `make` at the nearest Makefile root,
routing errors into the quickfix list via the tex `errorformat`.

## Conventions

- Bash scripts: `#!/usr/bin/env bash` + `set -Eeuo pipefail`, guard external repo/tool installs with
  `rpm -q` / `dnf repolist | grep` / `command -v` checks so reruns are safe.
- Sway/waybar/alacritty configs use a gruvbox-ish dark palette; sway mod is `Mod4`, vim-style
  `h/j/k/l` navigation throughout.

## Known inconsistencies

Verify before assuming these are intentional:

- `desktop-apps/{brave,obs-studio,telegram,vlc}.sh` say `set -Eeou pipfail` (typo). Bash rejects the
  option and, because `-e` never takes effect, those scripts run **unguarded**. Fix to `pipefail`.
- `wm/sway/config` binds `Print` to `~/fedora/dotfiles/sway/scripts/screenshot.sh`, a path
  that does not exist. The real script is `~/scripts/screenshot`.
- `wm/install.sh` installs `wofi` but the config and sway's `$launcher` both use `fuzzel`, which is
  never installed.
- Sway's `$filemanager` is `thunar`, also not installed by any module.
- `wm/waybar/config` uses `hyprland/workspaces` and `hyprland/window` modules, but the compositor
  here is sway — those modules will not populate. Sway equivalents are `sway/workspaces` and
  `sway/window`.
- `scripts/pstats` documents itself as `gitcheck` in its header and usage text.
