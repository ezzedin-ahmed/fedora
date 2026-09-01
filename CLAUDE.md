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
| `wm/` | sway, waybar, mako, gtklock, pipewire, mesa/vulkan, bluetooth, media; **writes `/etc/modprobe.d/nvidia-ondemand.conf`** (root, not a symlink) | `~/.config/{sway,waybar,mako,fuzzel,gtklock}` |
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
  attention. Root overridable via `PSTATS_ROOT` (legacy `GITCHECK_ROOT` still honoured).
- `k3s-up` / `k3s-down` — on-demand k3s lifecycle. k3s is deliberately **not** enabled at boot;
  `k3s-down` runs `k3s-killall.sh` and verifies only `k8s.io`-namespace shims are gone (Docker's
  `moby` shims must survive).
- `screenshot`, `screenshot-window` — grim + slurp (`-o` for a whole output), save + `wl-copy` +
  notify. Both exit quietly if the selection is cancelled.
- `screen-record` — wf-recorder + slurp to an mp4 in `~/Videos/Recordings`; `-a` adds audio.
  Re-running it stops an active recording (SIGINT, so the container is finalised) and copies the
  path. Bound to `$mod+Print`; needs RPM Fusion's `ffmpeg` for libx264, which `wm/install.sh`
  swaps in over Fedora's `ffmpeg-free`.
- `gpu-up` / `gpu-down` / `gpu-run` — on-demand NVIDIA driver lifecycle, the same shape as the k3s
  pair: the modules are blacklisted at boot so the card sits in D3hot, and these load/unload it.
  `gpu-run <cmd>` does both around one command and only unloads what it loaded.
- `prime-run` — runs one command on the discrete NVIDIA GPU via PRIME render offload. See
  "Hybrid graphics" below.
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

None outstanding. The previously listed ones are resolved: the `Print` binding now points at
`screenshot` on `PATH` (it pointed into a long-gone `~/fedora/dotfiles/` tree), `$filemanager` is
`nautilus` and installed by `wm/`, `pstats` no longer calls itself `gitcheck`, and `wofi` /
`hyprland/*` waybar modules are long gone — `wm/install.sh` installs `fuzzel` and the bar uses
`sway/workspaces`.

## Hybrid graphics

Optimus laptop: Intel HD 530 (`i915`) plus an NVIDIA Quadro M1000M on the proprietary 580xx akmod.
Every connector — the eDP panel and all the HDMI/DP ports — is wired to the Intel side; the NVIDIA
card has no display attached.

The compositor is pinned to the iGPU and the dGPU is opt-in per application:

- **Pin** — done by absence, not by environment. The NVIDIA modules are blacklisted at boot (see
  "Powering the card down"), so no nvidia DRM node exists when greetd starts sway: `/dev/dri` holds
  only the Intel card and wlroots has nothing else it could pick. If the driver *were* loaded at
  boot, `nvidia_drm.modeset=1` would make wlroots enumerate the Quadro and possibly take it as the
  primary renderer — every frame drawn on the dGPU and copied back to Intel for scanout.

  This now covers *two* wlroots compositors, not one: since the greeter is gtkgreet hosted in its
  own sway (see "Lock screen and login"), the login screen would pick the wrong GPU on exactly the
  same terms as the session. The blacklist is upstream of both, so both are covered by the one
  mechanism.

  Historical trap, still worth knowing before reverting to tuigreet: `WLR_DRM_DEVICES` inlined into
  tuigreet's `--cmd` does not work. tuigreet does not word-split that value before passing it to
  greetd, so `--cmd 'env WLR_DRM_DEVICES=... sway'` makes greetd exec a binary named
  `env WLR_DRM_DEVICES=... sway`, which ENOENTs: PAM authenticates, the session opens and closes in
  the same second, and the greeter reappears with no sway output in the journal. tuigreet's `--cmd`
  must stay a single argv-safe token. greetd's own `command` has never had this problem — greetd(5)
  says it is run by `sh(1)` — which is why the current `command = "sway --config ..."` is fine.
- **Opt in, graphics** — `scripts/prime-run <cmd>` sets `__NV_PRIME_RENDER_OFFLOAD` plus the per-API
  vendor selectors (GLX by name, EGL by narrowing the glvnd vendor list, Vulkan via
  `__VK_LAYER_NV_optimus`). Offload is client-side, so it works with the compositor on Intel: the
  app renders on the Quadro and hands over a dma-buf. Verify with `prime-run vulkaninfo --summary`
  — the Quadro should be device 0.
- **Opt in, compute** — nothing to do. CUDA (notebooks, torch, tensorflow, anything linking
  `libcuda.so`) addresses the card directly and never goes through the compositor's render path, so
  `prime-run` is neither needed nor useful there. Caveat is hardware, not config: the M1000M is
  Maxwell / compute capability 5.0, which current upstream torch wheels no longer ship kernels for.

Net effect: the Quadro is idle (`nvidia-smi` shows no processes) unless a `prime-run` command or a
CUDA process asks for it.

### Powering the card down

Idle is not the same as off, and **this hardware cannot power the GPU down by itself**. NVIDIA
runtime D3 needs an ACPI `_PR3` power resource on the PCIe root port — this Skylake board exposes
only `power_resources_D0/D2/D3hot` — plus video-memory-off in hardware, which Maxwell lacks. The
driver says as much: `/proc/driver/nvidia/gpus/*/power` reports `Runtime D3 status: Disabled by
default`, `Video Memory Off: Not Supported`. So a loaded driver holds the card at `D0` whether or
not anything is using it.

Unbinding is the only lever, so the card is kept unbound by default:

- `wm/nvidia-ondemand.conf` → `/etc/modprobe.d/nvidia-ondemand.conf` blacklists the four modules.
  `blacklist` suppresses only udev's modalias autoload; loading by name still works, so `gpu-up`,
  dependency loads, and the setuid `nvidia-modprobe` helper that CUDA apps call are all unaffected.
  A notebook that asks for the GPU therefore still brings the driver up on its own — `gpu-down` (or
  `gpu-run`) is what puts it back.
- `wm/install.sh` also disables `nvidia-powerd`, which drives Dynamic Boost (reported `Not
  Supported` here) and would reload the modules at every boot.
- `gpu-down` re-asserts `power/control=auto` after unloading, because
  `/usr/lib/udev/rules.d/80-nvidia-pm.rules` sets it back to `on` at unbind — which would otherwise
  pin the device at D0 with nothing even bound to it.

Check with `cat /sys/bus/pci/devices/0000:01:00.0/power_state`: `D3hot` unloaded, `D0` loaded.

Nothing here is a manual step. `wm/install.sh` writes the modprobe file, disables `nvidia-powerd`
and drops the driver once so the change lands without a reboot; `scripts/install.sh` symlinks the
whole `scripts/` directory, so the `gpu-*` and `prime-run` commands need no separate wiring. The
root copies (`/etc/modprobe.d/nvidia-ondemand.conf`, everything under `/etc/greetd/`) are the parts
that are *not* live-on-edit — changing either means rerunning its module.

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
