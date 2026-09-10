#!/usr/bin/env bash

set -Eeuo pipefail

# Symlinks first. These depend on no package being present, and putting them
# after the dnf calls meant one unrelated package conflict (ffmpeg vs
# ffmpeg-free) aborted the script under `set -e` and silently skipped every
# link. Config should land even if an install fails.
# -n (--no-dereference) matters: without it, a rerun where the target is
# already a symlink-to-directory makes ln descend into it and create a
# nested <module>/<module> link instead of replacing the symlink.
ln -vfsn $HOME/fedora/ui/sway $HOME/.config/sway
ln -vfsn $HOME/fedora/ui/waybar $HOME/.config/waybar
ln -vfsn $HOME/fedora/ui/mako $HOME/.config/mako
ln -vfsn $HOME/fedora/ui/gtklock $HOME/.config/gtklock

# ulauncher, unlike every other app here, creates its own config directory on
# first run -- so on any machine where it has been started before this script,
# the target is a real directory and `ln -f` cannot overwrite it. Same shape as
# the GTK case below, and the same failure if left unhandled: ln exits non-zero
# and `set -e` takes the whole script down.
if [ -d "$HOME/.config/ulauncher" ] && [ ! -L "$HOME/.config/ulauncher" ]; then
  # settings.json is the only file worth keeping, and this repo's copy is
  # authoritative, so the directory is moved aside rather than merged.
  mv -v "$HOME/.config/ulauncher" "$HOME/.config/ulauncher.bak.$(date +%s)"
fi
ln -vfsn $HOME/fedora/ui/ulauncher $HOME/.config/ulauncher

# GTK ships these as real (often empty) directories; ln -s into an existing
# directory would nest instead of replacing, so clear them out first.
for d in gtk-3.0 gtk-4.0; do
  if [ -d "$HOME/.config/$d" ] && [ ! -L "$HOME/.config/$d" ]; then
    rmdir "$HOME/.config/$d" 2>/dev/null ||
      echo "warning: $HOME/.config/$d is not empty; not replacing it" >&2
  fi
  [ -e "$HOME/.config/$d" ] && [ ! -L "$HOME/.config/$d" ] ||
    ln -vfsn "$HOME/fedora/ui/$d" "$HOME/.config/$d"
done

# settings.ini only covers GTK3/GTK4. libadwaita, the xdg-desktop-portal
# appearance setting (which Qt6, Chromium and Firefox follow), and anything
# else reading GSettings need color-scheme set explicitly.
gsettings set org.gnome.desktop.interface color-scheme 'prefer-light'
gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita'
gsettings set org.gnome.desktop.interface icon-theme 'Adwaita'
gsettings set org.gnome.desktop.interface cursor-theme 'Adwaita'

# SwayFX: sway plus blur, rounded corners and shadows. Stock sway has none of
# those -- wlroots does not implement blur at all, so the frosted look this
# config asks for is not reachable with a config change alone.
#
# It is a drop-in fork: same config syntax, same `sway` binary name, so greetd,
# sway-systemd and every keybinding here keep working. Only the effect
# directives below (blur, corner_radius, shadows, layer_effects) are new, and
# stock sway would reject those as unknown commands.
#
# Not packaged in Fedora; this is the upstream project's own COPR. Guarded on
# the repofile so a rerun does not re-add it.
if ! ls /etc/yum.repos.d/*swayfx*.repo >/dev/null 2>&1; then
  sudo dnf copr enable -y swayfx/swayfx
fi

# --allowerasing because swayfx installs the same /usr/bin/sway that Fedora's
# sway package owns, so the two conflict and dnf will not replace one with the
# other on its own.
sudo dnf install -y --allowerasing swayfx

sudo dnf install -y \
  mesa-dri-drivers \
  mesa-vulkan-drivers \
  mesa-libGL \
  mesa-libEGL \
  mesa-libgbm \
  vulkan-loader \
  vulkan-tools \
  libva \
  libva-utils \
  sway-systemd \
  swaybg \
  swayidle \
  gtklock \
  waybar \
  ulauncher \
  mako \
  nautilus \
  wl-clipboard \
  grim \
  slurp \
  wf-recorder \
  brightnessctl \
  playerctl \
  pavucontrol \
  network-manager-applet \
  NetworkManager-tui \
  blueman \
  xdg-desktop-portal \
  xdg-desktop-portal-wlr \
  xdg-desktop-portal-gtk \
  qt5-qtwayland \
  qt6-qtwayland \
  power-profiles-daemon

sudo systemctl enable --now power-profiles-daemon

# ulauncher is a daemon, not a spawn-per-invocation launcher like the fuzzel it
# replaced: $mod+d runs ulauncher-toggle, which only sends a dbus message to an
# already-running instance. Fedora ships the unit WantedBy=graphical-session
# .target, which the /etc/sway/config.d include activates, so enabling it is
# all the wiring needed. Its ExecStart pins GDK_BACKEND=x11 -- ulauncher runs
# under XWayland here, which is the packager's choice and not ours to fix.
systemctl --user enable --now ulauncher.service

# ulauncher compiles its stylesheet once, in init_theme() at window
# construction, so unlike the rest of this repo a theme edit is NOT live -- the
# running daemon keeps serving the stylesheet it built at startup. Restart it
# so a rerun of this script actually shows the current ui/ulauncher theme.
systemctl --user restart ulauncher.service

sudo dnf install -y google-noto-fonts-all
fc-cache -f

# Fedora ships ffmpeg-free (no libx264/libx265, hardware encoders only). RPM
# Fusion's ffmpeg is the full build, and the two conflict because both Provide
# ffmpeg-free -- so a plain `dnf install ffmpeg` fails the entire transaction
# rather than replacing it. Swap explicitly, and only once.
if ! rpm -q ffmpeg >/dev/null 2>&1; then
  if rpm -q ffmpeg-free >/dev/null 2>&1; then
    sudo dnf swap -y --allowerasing ffmpeg-free ffmpeg
  else
    sudo dnf install -y ffmpeg
  fi
fi

sudo dnf install -y \
  pipewire \
  pipewire-pulseaudio \
  pipewire-alsa \
  wireplumber \
  alsa-utils \
  pavucontrol \
  bluez \
  bluez-tools \
  blueman \
  v4l2loopback \
  v4l-utils \
  yt-dlp

systemctl --user enable --now pipewire.service
systemctl --user enable --now pipewire-pulse.service
systemctl --user enable --now wireplumber.service

# sudo systemctl enable --now bluetooth

# ------------------------------------------------------------ blurred wallpaper

# gtklock and gtkgreet draw their own background, and neither has anything
# behind it for swayfx to sample -- a lock surface and the greeter's own
# compositor respectively -- so compositor blur does nothing for them and the
# blur has to be baked into an image. Generated rather than committed blurred,
# so background.jpg stays the single source of truth: replace that one file and
# a rerun regenerates this.
#
# ffmpeg is already a dependency of scripts/screen-record (RPM Fusion's build,
# swapped in above), so this adds nothing to install.
blurred="$HOME/fedora/ui/wallpapers/background-blurred.jpg"
sharp="$HOME/fedora/ui/wallpapers/background.jpg"
if [ ! -e "$blurred" ] || [ "$sharp" -nt "$blurred" ]; then
  echo "Regenerating the blurred wallpaper..."
  ffmpeg -hide_banner -loglevel error -y -i "$sharp" \
    -vf "gblur=sigma=28,eq=brightness=0.06:saturation=0.9" -q:v 4 "$blurred"
fi

# --------------------------------------------------------------- the greeter

# greetd + gtkgreet. This used to be ui/greeter/install.sh, a nested module --
# the only subdirectory here that was not plain config. Folded in so every
# directory under ui/ means the same thing: config, installed by this script.
#
# gtkgreet is the program gtklock (the lock screen) was forked from, so login
# and unlock are the same screen by design; ui/greeter/gtkgreet.css deliberately
# mirrors ui/gtklock/style.css.
#
# tuigreet is installed although nothing references it. It is the recovery
# greeter -- no compositor, no GPU, no CSS -- so if gtkgreet fails to come up,
# pointing config.toml at
#     command = "tuigreet --time --remember --cmd sway"
# from a TTY and rerunning this script is a guaranteed way back in.
sudo dnf install -y greetd gtkgreet tuigreet

# Everything the greeter reads has to be a root-owned copy under /etc/greetd.
# It cannot be symlinked the way the rest of this script works: the greeter runs
# as the greetd user and this user's home is 0700, so nothing in this repo is
# readable to it. Consequence: unlike every other file in ui/, these four are
# NOT live-on-edit -- changing one means rerunning this script.
sudo install -Dm644 "$HOME/fedora/ui/greeter/config.toml"  /etc/greetd/config.toml
sudo install -Dm644 "$HOME/fedora/ui/greeter/sway-config"  /etc/greetd/sway-config
sudo install -Dm644 "$HOME/fedora/ui/greeter/gtkgreet.css" /etc/greetd/gtkgreet.css
# The blurred copy, not the sharp one: the greeter draws its own background and
# has nothing behind it for swayfx to blur, so the blur has to be baked in.
sudo install -Dm644 "$HOME/fedora/ui/wallpapers/background-blurred.jpg" /etc/greetd/background.jpg

# gtkgreet's session picker reads /etc/greetd/environments, a newline-separated
# list of command lines. The package's %post generates it from the installed
# .desktop files once and never touches it again, so a session installed later
# is missing until this is rerun. `--command sway` in sway-config is what keeps
# sway first and preselected regardless.
if [ -x /usr/libexec/gtkgreet-update-environments ]; then
  sudo /usr/libexec/gtkgreet-update-environments -w /etc/greetd/environments
fi

# Catch a CSS syntax error now rather than at the next login. GTK does not fail
# on a bad stylesheet -- it logs a warning and carries on unstyled, which from
# the greeter means a white-on-white Adwaita prompt and no obvious cause. GTK3
# ships no CSS linter, so ask the parser itself. Skipped, not fatal, if
# python3-gobject is missing.
if python3 -c 'import gi' 2>/dev/null; then
  python3 - <<'PYEOF' || echo "WARNING: gtkgreet.css has parse errors; the greeter will render unstyled."
import gi, sys
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk, GLib

errors = []
provider = Gtk.CssProvider()
provider.connect(
    "parsing-error",
    lambda prov, section, error: errors.append(
        f"line {section.get_start_line() + 1}: {error.message}"
    ),
)
try:
    provider.load_from_path("/etc/greetd/gtkgreet.css")
except GLib.Error as err:
    errors.append(str(err))

for error in errors:
    print(f"  gtkgreet.css: {error}", file=sys.stderr)
sys.exit(1 if errors else 0)
PYEOF
fi

sudo systemctl enable greetd.service
sudo systemctl set-default graphical.target

# greetd reads its config only at start, so the copies above do nothing until it
# restarts -- and restarting tears down greetd's VT and every session under it.
# So do it only when there is nothing to lose: from a TTY with no compositor up.
# With sway running the change lands at the next logout anyway, and killing the
# session to apply a config file is never worth it.
#
# The no-sway case is also the recovery path: a bad config leaves you bouncing
# off the greeter, and this is what puts a fixed one into effect without a
# reboot.
#
# The -u is load-bearing now that the *greeter* is a sway too. A bare
# `pgrep -x sway` matches greetd's greeter compositor, which is up whenever the
# login screen is, so the guard would be true even from a TTY and the recovery
# restart would never fire. Restricting to this user's uid sees only a real
# desktop session, since the greeter's sway runs as greetd.
if pgrep -x -u "$(id -u)" sway >/dev/null; then
  echo "Your sway session is running; leaving greetd alone. New config applies at next login."
else
  echo "Restarting greetd to pick up the new config..."
  sudo systemctl restart greetd.service
fi

