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
| `ui/` | **swayfx**, waybar, mako, gtklock, ulauncher, greetd + gtkgreet, pipewire, mesa/vulkan, bluetooth, media; **writes `/etc/greetd/{config.toml,sway-config,gtkgreet.css,background.jpg,environments}`** (root, not symlinks) | `~/.config/{sway,waybar,mako,ulauncher,gtklock,gtk-3.0,gtk-4.0}` |
| `nvidia/` | the proprietary driver, branch picked from the GPU's PCI device id; **writes `/etc/modprobe.d/nvidia-ondemand.conf`** (root, not a symlink) and owns all GPU power policy | — |
| `alacritty/` | — | `~/.config/alacritty` |
| `fish/` | `chsh -s fish` | `~/.config/fish` |
| `tmux/` | tmux | `~/.config/tmux` |
| `nvim/` | neovim, rustup, uv, typst, build toolchain | `~/.config/nvim` |
| `fonts/` | `rsms-inter-fonts`, `google-noto-sans-arabic-fonts`, `google-noto-color-emoji-fonts` | `~/.local/share/fonts`, `~/.config/fontconfig` |
| `scripts/` | — | `~/scripts` |
| `apps/` | waterfox, discord, telegram, vlc, obs-studio, nautilus, obsidian; one `install.sh` for all of them, or `./install.sh <app>...` for a subset | — |

There is no top-level bootstrap script. Modules are run by hand and roughly in the order above
(`base` first; `nvim/install.sh` sources `~/.cargo/env`, so it depends on rustup being present or
installing it itself). `nvidia/` is only run on a machine that has the discrete card. Every
directory under `ui/` — `greeter/` included — is plain config installed by the one `ui/install.sh`;
there are no nested modules there.

### The symlink convention

Every module links its *directory* into place with `ln -vfsn <repo dir> <target>`, so editing files
in this repo is immediately live — there is no copy/apply step. Two consequences:

- Never replace a symlinked target with a real directory; that breaks the whole model.
- The `-n` (`--no-dereference`) is load-bearing. Without it `ln` follows a target that is already
  a symlink-to-directory and creates the link *inside* it, producing a nested `<module>/<module>`
  self-symlink instead of replacing the link. That is how `nvim/nvim` got created. With `-n` a
  rerun replaces the symlink, and a target that is a *real* directory fails loudly rather than
  nesting silently.

`ui/install.sh` runs its symlinks *before* its `dnf` calls, on purpose: linking depends on no
package, and under `set -e` a failed install would otherwise skip every link.

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
- `screenshot`, `screenshot-window` — grim + slurp (`-o` for a whole output), save + `wl-copy` +
  notify. Both exit quietly if the selection is cancelled.
- `screen-record` — wf-recorder + slurp to an mp4 in `~/Videos/Recordings`; `-a` adds audio.
  Re-running it stops an active recording (SIGINT, so the container is finalised) and copies the
  path. Bound to `$mod+Print`; needs RPM Fusion's `ffmpeg` for libx264, which `ui/install.sh`
  swaps in over Fedora's `ffmpeg-free`.
- `gpu-down` — unloads the NVIDIA driver so the Quadro drops back to D3hot. The *only* manual GPU
  step, and deliberately the only script: nothing on this hardware can power the card down by
  itself, but everything that wants it brings the driver up on its own. See "Hybrid graphics".
- `prime-run` — runs one command on the discrete NVIDIA GPU via PRIME render offload, loading
  `nvidia_drm modeset=1` first if it is not already up. See "Hybrid graphics" below.
- `scratchterm` — dropdown terminal on `$mod` + backtick (`bindsym $mod+grave`). Toggles an
  alacritty with `app_id=scratchterm` in and out of sway's scratchpad, spawning it on first
  use; the `for_window` rule in `ui/sway/config` floats it, sizes it 60x55 ppt and reveals it,
  so the first press behaves like every later one. Hidden rather than killed, so the shell and
  its jobs survive a toggle.
- `kblayout` — waybar's keyboard-layout module, replacing the built-in `sway/language`. That one
  builds its layout table once at startup from `IPC_GET_INPUTS` and goes permanently blank after a
  suspend/resume, because the input add/remove churn sway emits on resume wipes it; nothing but a
  waybar restart brings it back. This re-reads the layout from sway on every input event instead of
  caching, so the churn heals itself. Wired as `"exec": "~/scripts/kblayout"` in `ui/waybar/config`.
- `pdf2img` — pdftoppm wrapper (poppler-utils): `-f` format, `-r` DPI, `-p` page range, `-o` outdir.
- `playvid`, `gentasks`, `calendar_svg` — fzf video picker; recurring-task markdown generator;
  SVG month calendar to clipboard.

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
  icon glyphs waybar, tmux and Neovim draw. Configs name the **`Hack Nerd Font Mono`** variant,
  whose icons are squeezed to one cell; plain `Hack Nerd Font` keeps their natural (often
  double-cell) width and overhangs a terminal grid.

`fonts/fontconfig/fonts.conf` names all three for the generic families (`sans-serif`, `serif`,
`monospace`). Fontconfig already resolved those correctly on its own — but to Fedora's
stock answers, not to the faces this repo installs. That file is what makes an app asking for a
generic land here. It lives *inside* the directory that is itself the font path, so fontconfig
scans it for fonts and finds none; harmless, and it keeps the module self-contained.

Note the two font packages that are **not** this module's: `ui/install.sh` installs
`google-noto-fonts-all` (the Noto sans/serif that everything falls back to), and `nvim/install.sh`
pulls a LaTeX toolchain whose texlive font packages land display faces like Antykwa Poltawskiego in
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

Obsidian is the other Chromium-family app here, and it needs nothing: it bundles Inter and uses it
by default. It only goes wrong if `textFontFamily`/`interfaceFontFamily` is set in a vault's
`.obsidian/appearance.json`, which is a stray click in its font picker away.

It is `apps/install.sh obsidian`, and the only app in that module installed from an AppImage rather
than a package or an rpm — so it also writes its own `~/.local/share/applications` entry, and `fuse
fuse-libs` (which Fedora does not install by default) is what lets the image mount at all. Two
things there are not obvious: the release is resolved by scanning the last 30 releases for one
carrying an x86_64 `.AppImage`, because `/releases/latest` is the *Android* build as often as not
(desktop and mobile ship from the same repo); and the icon is pulled by running the downloaded image
with `--appimage-extract`, since `.DirIcon` is only a symlink into `usr/share`. Rerunning it is how
you update — unlike `discord`, it is deliberately unguarded.

## The launcher

`ulauncher`, bound to `$mod+d` in `ui/sway/config`, replacing fuzzel. Two things about it are
different in kind from what it replaced, and both are why there is more wiring than a `set
$launcher` line:

- **It is a daemon.** fuzzel was spawned per invocation and exited on selection; `ulauncher-toggle`
  only sends a dbus message (`net.launchpad.ulauncher.toggle_window`) to an instance that must
  already be running. `ui/install.sh` therefore runs `systemctl --user enable --now
  ulauncher.service`. Fedora ships that unit `WantedBy=graphical-session.target`, which the
  `include /etc/sway/config.d/*` line already activates — so nothing needs an `exec` in the sway
  config, and the launcher is up before the first keypress rather than on it.
- **It runs under XWayland.** Fedora's unit pins `GDK_BACKEND=x11` in its `ExecStart`. That is the
  packager's decision, not this repo's, and it is why the `for_window` rule matches `class=
  "Ulauncher"` — an XWayland window has no `app_id`. The rule lists the `app_id` form as well, so
  it keeps working if that pin is ever dropped. Without the rule sway tiles the launcher into the
  layout instead of floating it. `ulauncher-toggle` also ends in a `wmctrl -a` call, which is X11
  and may warn under sway; the dbus message above it is what actually does the work.

Config is `ui/ulauncher/`, symlinked to `~/.config/ulauncher` like every other module — but it
breaks two of this repo's usual assumptions, and both are worth knowing before editing.

**Edits are not live.** Everywhere else here, changing a file in the repo takes effect on the next
use. ulauncher compiles its stylesheet exactly once, in `init_theme()` at window construction, and
the running daemon keeps serving what it built at startup — so a theme edit shows nothing until
`systemctl --user restart ulauncher.service`. `ui/install.sh` ends with that restart for the same
reason. This is the single most likely reason a palette change appears to do nothing.

**It writes back.** ulauncher owns this directory at runtime: `settings.json` is rewritten whenever
a preference changes in its GUI, `ext_preferences/` appears when an extension is configured, and —
because a *user* theme's generated stylesheet is written into the theme directory itself rather
than into `~/.cache` — `generated.css` lands inside `ui/ulauncher/user-themes/frost/`. The last
two are in `.gitignore`, the repo's only one — though its patterns still say `wm/` and so no longer
match; see "Known inconsistencies". `settings.json` is tracked on purpose, so a GUI
change shows up as a diff to keep or discard. Extensions land in `~/.local/share/ulauncher`,
outside the repo.

`ui/install.sh` also has to move an existing `~/.config/ulauncher` aside before linking. ulauncher
is the only app here that creates its own config directory, so on any machine where it has run
before the module did, the symlink target is a real directory and `ln -f` cannot overwrite it —
which under `set -e` would abort the rest of the script.

The frosted-light palette matches `ui/waybar/style.css`, `ui/gtklock/style.css` and
`ui/greeter/gtkgreet.css` (**not** `alacritty/colors.toml` any more — the terminal stays gruvbox
dark on purpose). It lives in `ui/ulauncher/user-themes/frost/`, which is ulauncher's
theme format, not a config file: `manifest.json` (validated — it must carry `manifest_version`,
`name`, `display_name`, `matched_text_hl_colors` and *both* css keys, and both files must exist)
plus two stylesheets. `extend_theme: "light"` means ulauncher generates a stylesheet that
`@import`s the stock light theme and appends ours, so `theme.css` holds only `@define-color`
overrides and every selector and size comes from upstream. The GTK 3.20 file exists because
`caret-color` needs that version; it imports the other. One trap: upstream misspells one variable
as `prefs_backgroud`, and the typo has to be repeated to override it.

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
- Everything under `ui/` uses the frosted-light palette (see "The look"); `alacritty/` and
  `tmux/` stay gruvbox dark. sway mod is `Mod4`, vim-style
  `h/j/k/l` navigation throughout.
- No absolute `/home/<user>` paths anywhere; the repo assumes only that it is checked out at
  `$HOME/fedora`. Where a config format expands variables, it uses `$HOME` — sway runs `output bg`
  paths through wordexp(3), and sway `exec` / waybar `on-click` both hand their command to `sh(1)`.
  Where a format does *not* expand (gtklock's glib key file, GTK CSS), the path is either passed in
  from a caller that does, or written relative to the file itself.

## Known inconsistencies

None outstanding. The `wm/` → `ui/` rename is now complete — every path, symlink and comment follows
it, `.gitignore` included. Previously listed and resolved: the `Print` binding points at `screenshot`
on `PATH`, `$filemanager` is `nautilus`, `pstats` no longer calls itself `gitcheck`, `wofi` /
`hyprland/*` waybar modules are gone (the bar uses `sway/workspaces`), and `fuzzel` is replaced by
`ulauncher`.

## The look

Frosted light: near-black text on translucent white, one blue accent (`#0071e3`), one red for urgent
(`#d70015`). It covers everything under `ui/` — sway borders, waybar, mako, gtklock, gtkgreet,
ulauncher, GTK. `alacritty/` and `tmux/` deliberately stay gruvbox dark; a light terminal was not
wanted.

**The compositor is SwayFX, not sway.** This is the part that is not a config choice. wlroots
implements no blur at all — `sway(5)` does not mention it and there is no flag — so `blur`,
`corner_radius`, `shadows` and `layer_effects` in `ui/sway/config` are swayfx-only directives that
stock sway rejects as unknown commands. SwayFX is a drop-in fork: same config syntax, same
`/usr/bin/sway` binary name, so greetd, `sway-systemd` and every keybinding keep working untouched.
It is not packaged in Fedora, so `ui/install.sh` enables the upstream project's own COPR
(`swayfx/swayfx`) and installs with `--allowerasing`, since swayfx and Fedora's `sway` own the same
binary and conflict.

Two things about the blur are worth knowing before editing any of it:

- **Blur needs something translucent to show through.** An opaque window renders the whole effect
  invisible, which is why `ui/sway/config` sets `opacity` on the terminals and every stylesheet uses
  `rgba(255, 255, 255, α)` rather than a flat white. Raising an alpha to 1.0 does not "make it
  cleaner", it turns the blur off for that surface.
- **Layer surfaces are not windows.** waybar and mako are layer-shell clients and are not covered by
  the window-level rules; each opts in by namespace through `layer_effects "waybar"` and
  `layer_effects "notifications"`. ulauncher is the odd one out and needs neither: Fedora's unit pins
  `GDK_BACKEND=x11`, so it arrives as an ordinary XWayland *window* and picks up the window rules.

**gtklock and gtkgreet get no compositor blur at all**, and this is the trap. A lock screen is an
`ext-session-lock` surface and the greeter runs inside its own compositor; in both cases there is
nothing behind them for swayfx to sample, so `blur enable` does exactly nothing there. Their blur is
baked into an image instead: `ui/install.sh` generates `ui/wallpapers/background-blurred.jpg` from
`background.jpg` with ffmpeg's `gblur`, and regenerates it whenever the sharp one is newer. The sharp
file stays the single source of truth — replace it and rerun. The blurred copy is also what gets
installed to `/etc/greetd/background.jpg`, so login and lock match.

## Hybrid graphics

Optimus laptop: Intel HD 530 (`i915`) plus an NVIDIA Quadro M1000M on the proprietary 580xx akmod.
Every connector — the eDP panel and all the HDMI/DP ports — is wired to the Intel side; the NVIDIA
card has no display attached.

### Installing the driver

`nvidia/install.sh` is its own module, deliberately separate from `ui/` — it needs RPM Fusion
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
  sway keybinding — where sudo has no terminal to prompt in and the app silently falls back to
  Intel. The file is validated with `visudo -c` on a temp copy before install, because a broken file
  in `sudoers.d` breaks `sudo` outright.
- Finally it installs `nvidia-ondemand.conf`, disables `nvidia-powerd`, and calls `gpu-down` — so
  the script ends with the card unbound and in D3hot rather than lit up. **All GPU power policy
  lives in this module**, not in `ui/`. It used to be split across both, which meant the state you
  ended in depended on which module you ran last: `nvidia/` finished by loading the driver while
  `ui/` finished by unloading it.

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

  It also ensures `nvidia_drm` is loaded **with `modeset=1`** first, and that is load-bearing rather
  than defensive. Note it checks that the parameter reads `Y`, not merely that the module is loaded:
  `modeset` is fixed at load time and cannot be changed on a live module, so `nvidia_drm` brought up
  by something else without it needs a *reload*, and testing only for the module leaves exactly the
  silent Intel fallback the guard exists to prevent. Nothing else on this machine sets it: there is no such default in
  `/usr/lib/modprobe.d`, none on the kernel cmdline, and `nvidia-modprobe` — the helper a CUDA
  process trips — brings up `nvidia` and `nvidia_uvm` but never `nvidia_drm`. Without it `prime-run`
  fails *silently*: the variables are set, the app starts, and it renders on the Intel GPU anyway.
  That is worse when the driver is already loaded for compute, because then every obvious check
  (`lsmod | grep nvidia`, `nvidia-smi`) looks healthy.
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

This is also why there is only one script now. `gpu-up` existed to load the driver, but everything
that needs it already does that — its one irreplaceable job was `modprobe nvidia_drm modeset=1`,
which now lives in `prime-run` where it is actually needed. `gpu-run <cmd>` wrapped a command in
load/unload, which is just `<cmd>` followed by `gpu-down`. Both were removed rather than kept as a
symmetrical-looking `up`/`down`/`run` trio that mostly documented an ordering rule you had to
remember.

Nothing here is a manual step at *install* time. `nvidia/install.sh` writes the modprobe file,
disables `nvidia-powerd` and drops the driver once so the change lands without a reboot;
`scripts/install.sh` symlinks the whole `scripts/` directory, so `gpu-down` and `prime-run` need no
separate wiring. The root copies (`/etc/modprobe.d/nvidia-ondemand.conf`, everything under
`/etc/greetd/`) are the parts that are *not* live-on-edit — changing either means rerunning its
module.

Nothing in `ui/greeter/` is live. All four files — `config.toml`, `sway-config`, `gtkgreet.css` and the
wallpaper — are *copied* into `/etc/greetd/`, so a change needs `ui/install.sh` rerun. They
cannot be symlinked the way every other module does it: the greeter runs as the `greetd` user and
the home directory is `0700`, so nothing in this repo is readable to it. That permission bit is the
whole reason for the copy, and it is why the wallpaper is duplicated rather than shared with
`ui/sway/config`.

The script then restarts `greetd` itself — but only when sway is not running, since a restart takes
greetd's VT and every session under it down with it. From inside a session it skips the restart and
the change lands at the next logout. Run from a TTY it applies immediately, which is also how you
recover from a config that bounces you off the greeter. The check is
`pgrep -x -u "$(id -u)" sway`, and the `-u` is load-bearing: the greeter is *itself* a sway now, so a
bare `pgrep -x sway` would always match and the recovery restart would never fire.

## Lock screen and login

Two separate things, easily conflated:

- **Login** — `ui/install.sh` installs greetd + **gtkgreet**, which is the program gtklock was forked
  from (Fedora's own package summary for gtklock is "Lock screen based on gtkgreet"). That is the
  point: login and unlock are the same screen, and `ui/greeter/gtkgreet.css` deliberately mirrors
  `ui/gtklock/style.css` — same frosted-light palette, same blurred wallpaper, same card.

  gtkgreet is a Wayland client, not a standalone program, so it needs a compositor to live in.
  `config.toml` therefore starts **sway** with a greeter-only config (`ui/greeter/sway-config`) whose
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

  There is deliberately **no `[initial_session]`** in `ui/greeter/config.toml`: that is greetd's
  autologin, and it starts a session with no authentication at all, so the first login after a
  shutdown skipped the password entirely.
- **Lock** — `gtklock` (`ui/gtklock/`), driven by `set $lock` in `ui/sway/config`, which the
  keybinding and both swayidle hooks share; waybar's lock button repeats the same command. That is
  also where `-s` names the stylesheet, because `ui/gtklock/config.ini` is a glib key file with no
  variable expansion and a `style=` key there would have to spell out an absolute path. `style.css`
  in turn reaches the wallpaper as `url("../wallpapers/…")`, which GTK resolves against the
  directory of the path it was handed — symlinks not followed, so the `-s` argument has to be the
  repo path and not `~/.config/gtklock/style.css`, which would look in `~/.config/wallpapers`. swayidle's `before-sleep` hook is the important one: there is no
  `bindswitch` for the lid, so lid-close falls through to logind's `HandleLidSwitch=suspend` and
  that hook is all that stands between reopening the lid and a live session.

Upstream `swaylock` was replaced because it draws only a ring — no field to type into, no clock —
and `swaylock-effects` is not packaged for Fedora. gtklock is an `ext-session-lock` client, so the
compositor owns the lock and a crashed locker cannot fall through to the desktop.
