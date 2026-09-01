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
| `wm/` | sway, waybar, mako, gtklock, pipewire, mesa/vulkan, bluetooth, media | `~/.config/{sway,waybar,mako,fuzzel,gtklock}` |
| `alacritty/` | — | `~/.config/alacritty` |
| `fish/` | `chsh -s fish` | `~/.config/fish` |
| `tmux/` | tmux | `~/.config/tmux` |
| `nvim/` | neovim, rustup, uv, build toolchain | `~/.config/nvim` |
| `fonts/` | — | `~/.local/share/fonts` |
| `scripts/` | — | `~/scripts` |
| `greeter/` | greetd, gtkgreet, sway (tuigreet kept as fallback); **writes `/etc/greetd/{config.toml,sway-config,gtkgreet.css,background.jpg,environments}`** (root, not symlinks) | — |
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
- `screenshot`, `screenshot-window` — grim + slurp (`-o` for a whole output), save + `wl-copy` +
  notify. Both exit quietly if the selection is cancelled.
- `screen-record` — wf-recorder + slurp to an mp4 in `~/Videos/Recordings`; `-a` adds audio.
  Re-running it stops an active recording (SIGINT, so the container is finalised) and copies the
  path. Bound to `$mod+Print`; needs RPM Fusion's `ffmpeg` for libx264, which `wm/install.sh`
  swaps in over Fedora's `ffmpeg-free`.
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

Nothing in `greeter/` is live. All four files — `config.toml`, `sway-config`, `gtkgreet.css` and the
wallpaper — are *copied* into `/etc/greetd/`, so a change needs `greeter/install.sh` rerun. They
cannot be symlinked the way every other module does it: the greeter runs as the `greetd` user and
`/home/ezzedin` is `0700`, so nothing in this repo is readable to it. That permission bit is the
whole reason for the copy, and it is why the wallpaper is duplicated rather than shared with
`wm/sway/config`.

The script then restarts `greetd` itself — but only when sway is not running, since a restart takes
greetd's VT and every session under it down with it. From inside a session it skips the restart and
the change lands at the next logout. Run from a TTY it applies immediately, which is also how you
recover from a config that bounces you off the greeter. The check is
`pgrep -x -u "$(id -u)" sway`, and the `-u` is load-bearing: the greeter is *itself* a sway now, so a
bare `pgrep -x sway` would always match and the recovery restart would never fire.

## Lock screen and login

Two separate things, easily conflated:

- **Login** — `greeter/` installs greetd + **gtkgreet**, which is the program gtklock was forked
  from (Fedora's own package summary for gtklock is "Lock screen based on gtkgreet"). That is the
  point: login and unlock are the same screen, and `greeter/gtkgreet.css` deliberately mirrors
  `wm/gtklock/style.css` — same gruvbox palette, same dimmed wallpaper, same card.

  gtkgreet is a Wayland client, not a standalone program, so it needs a compositor to live in.
  `config.toml` therefore starts **sway** with a greeter-only config (`greeter/sway-config`) whose
  last line is `exec 'gtkgreet …; swaymsg exit'`. The `swaymsg exit` is load-bearing: greetd starts
  the *compositor*, so sway must terminate once gtkgreet finalises a login or the greeter session
  never ends and the user session never begins. That greeter config deliberately omits the
  `include /etc/sway/config.d/*` the real one needs — the greeter is not a user session and must not
  start `graphical-session.target` or the portals as the `greetd` user.

  Two things gtkgreet writes in Pango markup, and markup beats CSS, so they are **not** styleable:
  the clock's size (`<span size='32000'>`, 32pt on the focused output) and the failed-login text
  colour (`<span color="red">`). Everything else about them — family, weight, colour of the clock —
  still takes CSS. Widget names for selectors are `#window`, `#clock`, `#body` (the card),
  `#input-field` and `#command-selector`; they are *not* the same names gtklock uses.

  `tuigreet` is still installed on purpose although nothing references it. It is the recovery
  greeter — no compositor, no GPU, no stylesheet — so pointing `command` back at
  `tuigreet --time --remember --cmd sway` from a TTY is a guaranteed way back in.

  There is deliberately **no `[initial_session]`** in `greeter/config.toml`: that is greetd's
  autologin, and it starts a session with no authentication at all, so the first login after a
  shutdown skipped the password entirely.
- **Lock** — `gtklock` (`wm/gtklock/`), driven by `set $lock` in `wm/sway/config`, which is the one
  place the command is written. swayidle's `before-sleep` hook is the important one: there is no
  `bindswitch` for the lid, so lid-close falls through to logind's `HandleLidSwitch=suspend` and
  that hook is all that stands between reopening the lid and a live session.

Upstream `swaylock` was replaced because it draws only a ring — no field to type into, no clock —
and `swaylock-effects` is not packaged for Fedora. gtklock is an `ext-session-lock` client, so the
compositor owns the lock and a crashed locker cannot fall through to the desktop.
