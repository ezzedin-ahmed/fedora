# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Personal Fedora workstation provisioning: dnf package installs plus dotfiles, for a **COSMIC**
desktop with Alacritty + fish + tmux + Neovim (LazyVim). Not a git repository and has no build,
test, or lint tooling — the "programs" are bash/python scripts and declarative config files.

The desktop was SwayFX + waybar + mako + gtklock + ulauncher + greetd/gtkgreet until the switch to
COSMIC; `git log` has the whole thing if any of it is ever wanted back. Nothing of it survives in
the tree.

## Layout and execution model

Each top-level directory is an independent, idempotent module with its own `install.sh`:

| Module | Installs | Symlinks into |
| --- | --- | --- |
| `base/` | core CLI tooling, RPM Fusion repos | — |
| `containers/` | docker-ce, k3s (server, kubeconfig mode 644), writes `~/.kube/config` | — |
| `cosmic/` | `@cosmic-desktop`, cosmic-greeter, xdg-desktop-portal-cosmic, mesa/vulkan, pipewire, bluetooth, media; **enables `cosmic-greeter.service`** and **removes the old sway stack** | — (deliberately nothing) |
| `nvidia/` | the proprietary driver, branch picked from the GPU's PCI device id; **writes `/etc/modprobe.d/nvidia-ondemand.conf`** (root, not a symlink) and owns all GPU power policy | — |
| `alacritty/` | — | `~/.config/alacritty` |
| `fish/` | `chsh -s fish` | `~/.config/fish` |
| `tmux/` | tmux | `~/.config/tmux` |
| `nvim/` | neovim, rustup, uv, typst, build toolchain | `~/.config/nvim` |
| `fonts/` | `rsms-inter-fonts`, `google-noto-sans-arabic-fonts`, `google-noto-color-emoji-fonts`, `google-noto-fonts-all` | `~/.local/share/fonts`, `~/.config/fontconfig` |
| `scripts/` | — | `~/scripts` |
| `apps/` | waterfox, discord, telegram, vlc, obs-studio, obsidian; one `install.sh` for all of them, or `./install.sh <app>...` for a subset | — |

`wallpapers/` is not a module — just the image, kept in the repo so COSMIC's appearance settings
have something local to point at.

There is no top-level bootstrap script. Modules are run by hand and roughly in the order above
(`base` first; `nvim/install.sh` sources `~/.cargo/env`, so it depends on rustup being present or
installing it itself). `nvidia/` is only run on a machine that has the discrete card.

### The symlink convention

Every module that has config links its *directory* into place with `ln -vfsn <repo dir> <target>`,
so editing files in this repo is immediately live — there is no copy/apply step. Two consequences:

- Never replace a symlinked target with a real directory; that breaks the whole model.
- The `-n` (`--no-dereference`) is load-bearing. Without it `ln` follows a target that is already
  a symlink-to-directory and creates the link *inside* it, producing a nested `<module>/<module>`
  self-symlink instead of replacing the link. That is how `nvim/nvim` got created. With `-n` a
  rerun replaces the symlink, and a target that is a *real* directory fails loudly rather than
  nesting silently.

**`cosmic/` is the exception, and it is a deliberate one** — see "COSMIC" below. It symlinks
nothing, because the desktop's config is owned and rewritten by the desktop itself.

`fish/config.fish` puts `~/scripts` on `PATH`, so everything in `scripts/` is a global command.

## Scripts

`scripts/` holds standalone executables (no extensions, shebang-dispatched — bash and python3):

- `tmux-sessionizer` — fzf over git repos 1–2 levels under `$PROJECTS_ROOT` (default `~/projects`);
  creates a session with window 1 running `nvim .` plus 3 shell windows, or attaches if it exists.
- `pstats` — scans a tree for repos with uncommitted/unpushed work; exits 1 if anything needs
  attention. Root overridable via `PSTATS_ROOT` (legacy `GITCHECK_ROOT` still honoured).
- `k3s-up` / `k3s-down` — on-demand k3s lifecycle. k3s is deliberately **not** enabled at boot;
  `k3s-down` runs `k3s-killall.sh` and verifies only `k8s.io`-namespace shims are gone (Docker's
  `moby` shims must survive).
- `gpu-down` — unloads the NVIDIA driver so the Quadro drops back to D3hot. The *only* manual GPU
  step, and deliberately the only script: nothing on this hardware can power the card down by
  itself, but everything that wants it brings the driver up on its own. See "Hybrid graphics".
- `prime-run` — runs one command on the discrete NVIDIA GPU via PRIME render offload, loading
  `nvidia_drm modeset=1` first if it is not already up. See "Hybrid graphics" below.
- `pdf2img` — pdftoppm wrapper (poppler-utils): `-f` format, `-r` DPI, `-p` page range, `-o` outdir.
- `playvid`, `gentasks`, `calendar_svg` — fzf video picker; recurring-task markdown generator;
  SVG month calendar to clipboard.

Five scripts went with the sway stack, all replaced by something COSMIC ships:

| Removed | Replaced by |
| --- | --- |
| `screenshot`, `screenshot-window` | `cosmic-screenshot`, bound to `Print` by default |
| `screen-record` | nothing CLI-shaped — see "Screen capture" |
| `kblayout` | COSMIC's own keyboard-layout applet |
| `scratchterm` | nothing; it was built on sway's scratchpad, which has no COSMIC equivalent |

## COSMIC

Stock, and stock on purpose. `cosmic/install.sh` installs the desktop and configures none of it.

**The desktop's config is not in this repo, and cannot usefully be.** COSMIC stores settings as
`~/.config/cosmic/<component>/v1/<key>` — one file per key, in RON — and cosmic-settings rewrites
those files whenever a preference changes in the GUI. There is no direction of flow to reverse: the
GUI is the source of truth. Symlinking that tree in here would reproduce the old ulauncher problem
(a config directory the app owns and rewrites behind you) across the entire desktop, so the trade
was made explicitly: the desktop is configured in cosmic-settings, and this repo installs it and
stays out of the way.

That is the one real ideological cost of the switch, and it is worth being honest about it: this
repo's premise everywhere else is that config is source and the GUI is absent. For the desktop that
is now inverted.

The shipped defaults are readable, which is the fastest way to learn a key's shape before
overriding it in the GUI:

```
/usr/share/cosmic/com.system76.CosmicComp/v1/
/usr/share/cosmic/com.system76.CosmicSettings.Shortcuts/v1/defaults
/usr/share/cosmic/com.system76.CosmicSettings.Shortcuts/v1/system_actions
```

The stock shortcuts are already vim-style and need no porting: `Super+h/j/k/l` focuses,
`Super+Shift+h/j/k/l` moves, `Super+Ctrl+h/j/k/l` switches workspace, `Super+q` closes,
`Super+Escape` locks. Tiling is per-workspace and toggled in the panel, not always-on.

What to set by hand after the first login, since nothing here does it:

- **Appearance** — wallpaper (`wallpapers/background.jpg`), accent colour, light/dark.
- **Appearance → fonts** — interface font `Inter`, monospace `Hack Nerd Font Mono`. COSMIC does not
  ask fontconfig for a generic, so `fonts/fontconfig/fonts.conf` does not reach it; it names
  families outright and has its own picker.
- **Input** — keyboard layouts, which is what `kblayout` used to work around.

`cosmic-comp` is Smithay-based, not wlroots. Mostly invisible, with one exception that is not —
see below.

### Screen capture

`cosmic-comp` implements **`ext-image-copy-capture-v1`**, not **`wlr-screencopy`**. Consequences,
in the order they bite:

- `grim` 1.5 speaks both, so it still works, and `slurp` only needs layer-shell, which cosmic-comp
  has. The old `screenshot` scripts would in fact still run — they were dropped because
  `cosmic-screenshot` is bound to `Print` out of the box and does the same save + copy + notify.
- `wf-recorder` speaks **only** wlr-screencopy, so it cannot capture anything under COSMIC no
  matter how it is invoked. `screen-record` and its `$mod+Print` binding are therefore gone rather
  than ported, and `cosmic/install.sh` removes the package.
- The replacement for recording is the portal: `xdg-desktop-portal-cosmic` provides ScreenCast, and
  OBS (already in `apps/`) uses it. There is no drop-in CLI region-recorder in Fedora that speaks
  either the portal or ext-image-copy — this is a genuine regression, not a rename.

Verify any capture tool before trusting it, since the failure is a clean "no such protocol" at
runtime rather than a build error:

```
wayland-info | grep -E 'screencopy|image_copy_capture'
```

`zwlr_data_control_manager_v1` *is* implemented, which is why `wl-copy`/`wl-paste` — and therefore
nvim's `remote_clipboard.lua` — keep working unchanged.

## Fonts

Three faces, and which one you get depends on the script being rendered, not on the app:

- **Inter** (`rsms-inter-fonts`) — the UI sans. It is the open face drawn along the same lines as
  macOS's SF Pro, which Apple licenses only for its own platforms.
- **Noto Sans Arabic** (`google-noto-sans-arabic-fonts`) — Arabic. Inter has *no* Arabic glyphs, so
  this is not a fallback-if-missing, it is the other half of the pair: fontconfig matches per
  character, so a mixed line takes Latin from Inter and Arabic from Noto in the same run.
- **Noto Color Emoji** (`google-noto-color-emoji-fonts`) — emoji. Not optional and not covered by
  `google-noto-fonts-all`, which excludes emoji: with no emoji font installed, every emoji is
  scavenged from whatever unrelated font happens to have that codepoint, which on this machine
  meant Font Awesome for 😀, Garamond-Math for 👍 and FreeSerif for ⚡. It is named
  explicitly in `fonts.conf` rather than left to its own conf.d snippet, because those squatters
  are still installed and still claim those ranges.
- **Hack Nerd Font** — monospace, vendored as .ttf in `fonts/Hack/` rather than packaged, for the
  icon glyphs tmux and Neovim draw. Configs name the **`Hack Nerd Font Mono`** variant,
  whose icons are squeezed to one cell; plain `Hack Nerd Font` keeps their natural (often
  double-cell) width and overhangs a terminal grid.

`fonts/fontconfig/fonts.conf` names all three for the generic families (`sans-serif`, `serif`,
`monospace`). Fontconfig already resolved those correctly on its own — but to Fedora's
stock answers, not to the faces this repo installs. That file is what makes an app asking for a
generic land here. It lives *inside* the directory that is itself the font path, so fontconfig
scans it for fonts and finds none; harmless, and it keeps the module self-contained.

`google-noto-fonts-all` — the sans/serif fallback the serif generic resolves to — is installed by
this module now. It used to come in with the desktop module, which no longer exists.

Note the other font packages that are **not** this module's: `nvim/install.sh` pulls a LaTeX
toolchain whose texlive font packages land display faces like Antykwa Poltawskiego in
`/usr/share/fonts`, where GUI font pickers surface them near the top of an alphabetical list.

### The browser

Waterfox (`apps/install.sh waterfox`), from `isv:BrowserWorks` on OBS — the channel
waterfox.net/download hands out for dnf, since Waterfox is in no Fedora repo and the
third-party `hawkeye116477` repo most guides still name is unmaintained. The URL is per-release,
so the script builds it from `rpm -E %fedora`. The guard checks the *release* in the installed
repofile, not just the repo id — after a Fedora upgrade the old repofile is still there and still
enabled, so an id-only check would skip the re-add and leave dnf pointed at the previous release's
directory forever. Rerunning the script after an upgrade is therefore enough.

Being Gecko, it needs almost nothing from this module. Its Linux defaults for
`font.name.{serif,sans-serif,monospace}.*` are the literal strings `serif`, `sans-serif` and
`monospace`, which go to fontconfig as generics — so `fonts.conf` is already in the path and there
is nothing to redirect. The script writes exactly two prefs, into each profile's `user.js`:

- `font.default.x-western` → `sans-serif`. This is the one Gecko gets "wrong" for this setup: it
  decides which generic an *unstyled* page gets, and its default is `serif`.
- `font.default.ar` → `sans-serif`. Gecko keys the default generic per language group and Arabic is
  its own group, so without this Arabic stays on serif and renders naskh.

`user.js` rather than `prefs.js` because Waterfox reapplies it at every startup and rewrites
`prefs.js` on exit — so it is both the durable place and safe to write while the browser is
running. The script strips its own two lines before appending them, so a rerun neither duplicates
them nor disturbs prefs added by hand.

This is the part that was much larger under Brave. Chromium's defaults are compiled in as the
literal families `Times New Roman` / `Arial` / `Courier New` and it asks fontconfig for those **by
name**, never for a generic, so `fonts.conf` could not reach it at all. Brave was handed three
invented family names (`DefaultFont`, `DefaultFontSerif`, `DefaultFontMono`) defined in
`fonts.conf` and jq-merged into each profile's `Preferences`. Those placeholder rules are gone with
Brave; a future Chromium-family app would need them back.

### Editing fonts.conf

The rules are more delicate than they look, and every bug found while writing that file parsed
cleanly and simply resolved to the wrong font. Three traps, all load-bearing:

- **`<match>` + `prepend_first`, never `<alias><prefer>`.** Fedora's `conf.d` snippets have already
  put Noto onto the generics before this user config loads, and `<prefer>` appends *behind* them —
  it applies and changes nothing.
- **Never `binding="strong"`.** It makes the first family win even for text it has no glyphs for,
  which collapses the Latin/Arabic split.
- **Never chain the rules.** Pointing one family at another to avoid repeating the families was
  tried, in both directions, and both silently misroute Arabic:
  `prepend_first` inserts at the absolute front, so the rule that fires *last* wins, and Fedora
  aliases the generics into each other's family lists. The repetition is the price of each rule
  being independently correct.

Re-run this after touching that file; all eight should hold.

```
for q in sans-serif sans-serif:lang=ar serif serif:lang=ar \
         monospace monospace:lang=ar system-ui system-ui:lang=ar; do
  printf '%-28s -> ' "$q"; fc-match --format='%{family[0]}\n' "$q"
done
```

Expected: the sans and `system-ui` rows give `Inter`, the mono rows `Hack Nerd Font Mono`, the
serif rows `Noto Serif`; every `:lang=ar` row gives `Noto Sans Arabic` except the serif one, which
gives `Noto Naskh Arabic`. `system-ui` has no rule of its own and needs none — Fedora already
chains it to `sans-serif`, and both halves land correctly without one.

None of this reaches COSMIC's own UI, which names families outright rather than asking for a
generic — set those in cosmic-settings. It still governs GTK apps, Waterfox and anything else that
asks for `sans-serif`.

Obsidian needs nothing: it bundles Inter and uses it by default. It only goes wrong if
`textFontFamily`/`interfaceFontFamily` is set in a vault's `.obsidian/appearance.json`, which is a
stray click in its font picker away.

It is `apps/install.sh obsidian`, and the only app in that module installed from an AppImage rather
than a package or an rpm — so it also writes its own `~/.local/share/applications` entry, and `fuse
fuse-libs` (which Fedora does not install by default) is what lets the image mount at all. Two
things there are not obvious: the release is resolved by scanning the last 30 releases for one
carrying an x86_64 `.AppImage`, because `/releases/latest` is the *Android* build as often as not
(desktop and mobile ship from the same repo); and the icon is pulled by running the downloaded image
with `--appimage-extract`, since `.DirIcon` is only a symlink into `usr/share`. Rerunning it is how
you update — unlike `discord`, it is deliberately unguarded.

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
for Shift/Alt-Shift+Return in `alacritty/alacritty.toml`. Unaffected by the COSMIC switch — the
Wayland half depends on `wl-clipboard`, which cosmic-comp supports.

`after/ftplugin/tex.lua` binds `<leader>m` to save-all + async `make` at the nearest Makefile root,
routing errors into the quickfix list via the tex `errorformat`.

### Rust components

`nvim/install.sh` installs rustup with `--profile complete` *and* then names components explicitly,
which looks redundant and is not. A profile only applies to a toolchain rustup installs itself, so
neither the flag nor `rustup set profile complete` retrofits a machine where rustup already exists —
the `curl` is guarded on `command -v rustup`, and running `rustup toolchain install stable --profile
complete` over an already-installed toolchain re-syncs the components it has rather than adding the
missing ones. `rustup component add` is the only thing that closes the gap; `set profile` still earns
its line because it is what makes the *next* toolchain complete.

`rust-analyzer` and `rust-src` are the two that matter and the two the `default` profile omits, and
their absence fails quietly rather than loudly: rustup drops a `~/.cargo/bin/rust-analyzer` shim
whether or not the component is installed, so rustaceanvim's executable check passes, the server is
spawned, and it exits immediately with `Unknown binary 'rust-analyzer' in official toolchain` — into
`lsp.log`, with nothing surfaced in nvim. Without `rust-src`, stdlib completion and goto fail the
same silent way.

## Conventions

- Bash scripts: `#!/usr/bin/env bash` + `set -Eeuo pipefail`, guard external repo/tool installs with
  `rpm -q` / `dnf repolist | grep` / `command -v` checks so reruns are safe.
- `alacritty/` and `tmux/` are gruvbox dark and stay that way; a light terminal was never wanted.
  The desktop's own palette is whatever is set in cosmic-settings and is not tracked here.
- No absolute `/home/<user>` paths anywhere; the repo assumes only that it is checked out at
  `$HOME/fedora`.

## Known inconsistencies

None outstanding. The COSMIC migration is complete: `ui/` is gone in full, the five sway-dependent
scripts with it, and nothing in the tree references sway, waybar, mako, gtklock, gtkgreet, ulauncher
or fuzzel outside `cosmic/install.sh`'s removal list and this file's history notes. `nautilus` left
`apps/` with it — `cosmic-files` is the file manager now.

## Hybrid graphics

Optimus laptop: Intel HD 530 (`i915`) plus an NVIDIA Quadro M1000M on the proprietary 580xx akmod.
Every connector — the eDP panel and all the HDMI/DP ports — is wired to the Intel side; the NVIDIA
card has no display attached.

### Installing the driver

`nvidia/install.sh` is its own module, deliberately separate from the desktop — it needs RPM Fusion
nonfree from `base/`, and it is the one module that is meaningless on a machine without the card.
Branch selection is the whole reason it is a script and not a `dnf install` line:

- Since 580, mainline `akmod-nvidia` ships only the **open** kernel module, which needs a GSP
  microcontroller — Turing (RTX 20xx) and newer. On anything older the module builds and loads
  fine and then refuses the GPU at probe (`not supported by open nvidia.ko because it does not
  include the required GPU System Processor (GSP)`), after which `nvidia-smi` reports it "couldn't
  communicate with the NVIDIA driver". The Quadro M1000M is GM107 (Maxwell), so it needs the
  `580xx` legacy branch, which still carries the proprietary module.
- The script picks the branch from the PCI device id rather than a hardcoded suffix: `>= 0x1e00` is
  Turing and up, everything below it is stranded on legacy. Device ids are not ordered by
  architecture in general, but they are monotonic across this one boundary.
- The two branches carry hard `Conflicts`, so `dnf install` alone fails when the wrong one is
  present — the script removes the stale branch first, with **`--no-autoremove`**. This is a swap,
  not a cleanup: the shared dependencies (`egl-wayland`, `egl-gbm`, `nvidia-modprobe`, and `akmods`
  itself, which the build step needs) come straight back with the incoming branch, and letting dnf
  autoremove them leaves the system briefly without `akmods`.
- nouveau has to be kept off the card or it binds first and nvidia bails with "already bound to
  nouveau" — but the script only writes a `blacklist-nouveau.conf` when `/proc/cmdline` does *not*
  already carry the karg. Normally it does: the driver packages add
  `modprobe.blacklist=nouveau,nova_core` at install, which covers strictly more than a hand-written
  file would (`nova_core` is the Rust nouveau replacement Fedora ships, and a file saying only
  `blacklist nouveau` misses it). Skipping it also skips a 30–60s `dracut --force` on every rerun.
- It forces `akmods` synchronously so a build failure surfaces here rather than as a black screen
  after reboot, then loads the module once and runs `nvidia-smi` purely to prove the build is good.
- Secure Boot is warned about, not handled: an akmod-built module will not load until its signing
  key is enrolled with `mokutil`.
- It installs `/etc/sudoers.d/nvidia-drm`, a single NOPASSWD rule for the exact argv
  `modprobe nvidia_drm modeset=1`. Not a convenience: `nvidia_drm` is the one module the setuid
  `nvidia-modprobe` helper cannot load (it covers `nvidia`, `nvidia_uvm` and `nvidia_modeset` only),
  so without the rule `prime-run` works when typed at a shell and fails from a `.desktop` entry or a
  COSMIC shortcut — where sudo has no terminal to prompt in and the app silently falls back to
  Intel. The file is validated with `visudo -c` on a temp copy before install, because a broken file
  in `sudoers.d` breaks `sudo` outright.
- Finally it installs `nvidia-ondemand.conf`, disables `nvidia-powerd`, and calls `gpu-down` — so
  the script ends with the card unbound and in D3hot rather than lit up. **All GPU power policy
  lives in this module**, and always should: it used to be split with the desktop module, which
  meant the state you ended in depended on which of the two you ran last.

The compositor is pinned to the iGPU and the dGPU is opt-in per application:

- **Pin** — done by absence, not by environment. The NVIDIA modules are blacklisted at boot (see
  "Powering the card down"), so no nvidia DRM node exists when the greeter starts: `/dev/dri` holds
  only the Intel card and the compositor has nothing else it could pick. If the driver *were*
  loaded at boot, `nvidia_drm.modeset=1` would make it enumerate the Quadro and possibly take it as
  the primary renderer — every frame drawn on the dGPU and copied back to Intel for scanout.

  This covers the greeter as well as the session: cosmic-greeter runs its own cosmic-comp instance,
  and the blacklist is upstream of both, so one mechanism covers both. It survived the sway →
  COSMIC switch untouched for exactly that reason — it never depended on which compositor was
  running, only on which device nodes existed.
- **Opt in, graphics** — `scripts/prime-run <cmd>` sets `__NV_PRIME_RENDER_OFFLOAD` plus the per-API
  vendor selectors (GLX by name, EGL by narrowing the glvnd vendor list, Vulkan via
  `__VK_LAYER_NV_optimus`). Offload is client-side, so it works with the compositor on Intel: the
  app renders on the Quadro and hands over a dma-buf. Verify with `prime-run vulkaninfo --summary`
  — the Quadro should be device 0.

  It also ensures `nvidia_drm` is loaded **with `modeset=1`** first, and that is load-bearing rather
  than defensive. Note it checks that the parameter reads `Y`, not merely that the module is loaded:
  `modeset` is fixed at load time and cannot be changed on a live module, so `nvidia_drm` brought up
  by something else without it needs a *reload*, and testing only for the module leaves exactly the
  silent Intel fallback the guard exists to prevent. Nothing else on this machine sets it: there is
  no such default in `/usr/lib/modprobe.d`, none on the kernel cmdline, and `nvidia-modprobe` — the
  helper a CUDA process trips — brings up `nvidia` and `nvidia_uvm` but never `nvidia_drm`. Without
  it `prime-run` fails *silently*: the variables are set, the app starts, and it renders on the
  Intel GPU anyway. That is worse when the driver is already loaded for compute, because then every
  obvious check (`lsmod | grep nvidia`, `nvidia-smi`) looks healthy.
- **Opt in, compute** — nothing to do. CUDA (notebooks, torch, tensorflow, anything linking
  `libcuda.so`) addresses the card directly and never goes through the compositor's render path, so
  `prime-run` is neither needed nor useful there. Caveat is hardware, not config: the M1000M is
  Maxwell / compute capability 5.0, which current upstream torch wheels no longer ship kernels for.

Net effect: the Quadro is idle (`nvidia-smi` shows no processes) unless a `prime-run` command or a
CUDA process asks for it — but *idle is not unloaded*, and the driver does not come back down on
its own. See below.

### Powering the card down

Idle is not the same as off, and **this hardware cannot power the GPU down by itself**. NVIDIA
runtime D3 needs an ACPI `_PR3` power resource on the PCIe root port — this Skylake board exposes
only `power_resources_D0/D2/D3hot` — plus video-memory-off in hardware, which Maxwell lacks. The
driver says as much: `/proc/driver/nvidia/gpus/*/power` reports `Runtime D3 status: Disabled by
default`, `Video Memory Off: Not Supported`. So a loaded driver holds the card at `D0` whether or
not anything is using it.

Unbinding is the only lever, so the card comes up unbound and there is exactly one command that
puts it back:

- `nvidia/nvidia-ondemand.conf` → `/etc/modprobe.d/nvidia-ondemand.conf` blacklists the four
  modules. `blacklist` suppresses only udev's modalias autoload; loading by name still works, so
  dependency loads and the setuid `nvidia-modprobe` helper that CUDA apps call are unaffected.
- `nvidia/install.sh` also disables `nvidia-powerd`, which drives Dynamic Boost (reported `Not
  Supported` here) and would reload the modules at every boot.
- `gpu-down` re-asserts `power/control=auto` after unloading, because
  `/usr/lib/udev/rules.d/80-nvidia-pm.rules` sets it back to `on` at unbind — which would otherwise
  pin the device at D0 with nothing even bound to it.

Check with `cat /sys/bus/pci/devices/0000:01:00.0/power_state`: `D3hot` unloaded, `D0` loaded.
`gpu-down` derives that address from `lspci` rather than hardcoding it.

**The asymmetry is the thing to understand here.** The up-side is fully automatic and the down-side
is not, so the setup drifts toward permanently-on rather than toward off:

- Anything that wants the card loads the driver by itself. A CUDA process trips `nvidia-modprobe`;
  `prime-run` loads `nvidia_drm` directly. Even a stray `nvidia-smi` does it.
- Nothing ever unloads it. There is no idle timeout to reach, because runtime D3 is unavailable —
  that is the whole premise above.

So a machine can very easily sit at `D0` all day with `nvidia-smi` showing no processes at all,
which looks like the "idle" success case and is not. `gpu-down` is the only thing that fixes it, and
running it is a habit, not a mechanism.

One thing to re-check now rather than assume: COSMIC's own daemons (`cosmic-settings-daemon`,
`cosmic-idle`) probe hardware more eagerly than the sway stack did. If `power_state` starts reading
`D0` on a fresh boot with nothing offloaded, something in the session is tripping
`nvidia-modprobe` — that would be new, and the blacklist is not what would be at fault.

Nothing here is a manual step at *install* time. `nvidia/install.sh` writes the modprobe file,
disables `nvidia-powerd` and drops the driver once so the change lands without a reboot;
`scripts/install.sh` symlinks the whole `scripts/` directory, so `gpu-down` and `prime-run` need no
separate wiring. The root copy (`/etc/modprobe.d/nvidia-ondemand.conf`) is the part that is *not*
live-on-edit — changing it means rerunning the module.

## Lock screen and login

Both are `cosmic-greeter`, and that is the whole section now — the same binary, the same look, one
package. Under the old setup this took two programs (gtkgreet and gtklock) and a deliberate effort
to make them mirror each other.

- **Login** — `cosmic-greeter` is a greetd greeter. greetd itself stays; what changed is which
  config it starts with. The package ships `/etc/greetd/cosmic-greeter.toml` and a unit that runs
  `greetd --config /etc/greetd/cosmic-greeter.toml`, aliased to `display-manager.service`. So
  `cosmic-greeter.service` and the plain `greetd.service` this repo used to configure are mutually
  exclusive — both want vt1 — and `cosmic/install.sh` disables the old one before enabling the new.

  Nothing in `/etc/greetd/` is written by this repo any more. That directory was the awkward part
  of the old setup: the greeter runs as its own user and `$HOME` is `0700`, so nothing here was
  readable to it and four files had to be *copied* into `/etc/greetd/` and re-copied on every edit.
  COSMIC's greeter reads the user's own COSMIC config over its daemon instead, so the copies are
  gone along with the "this part is not live" caveat.

  `cosmic/install.sh` does **not** restart the greeter, on purpose: a restart takes its VT and every
  session under it down with it, so the change lands at the next logout.

  There is deliberately no autologin. greetd's `[initial_session]` starts a session with no
  authentication at all, and the first login after a shutdown then skips the password entirely.

- **Lock** — `Super+Escape` by default, which runs `loginctl lock-session`; `cosmic-idle` handles
  the idle and before-sleep cases, including lid-close, which falls through to logind's
  `HandleLidSwitch=suspend`. cosmic-greeter is an `ext-session-lock` client, so the compositor owns
  the lock and a crashed locker cannot fall through to the desktop — the same guarantee gtklock gave.

**Recovery.** `tuigreet` was the recovery greeter and is removed with the rest of the sway stack;
greetd's built-in `agreety` replaces it at no install cost. If the greeter ever fails to come up,
log in on another VT and set `command = "agreety --cmd start-cosmic"` in
`/etc/greetd/cosmic-greeter.toml`, then restart `cosmic-greeter.service`. Worth knowing *before*
needing it, since the greeter is the one thing that cannot be debugged from inside the session.
