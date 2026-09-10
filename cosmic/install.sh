#!/usr/bin/env bash

set -Eeuo pipefail

# COSMIC, stock. Deliberately stock: unlike every other module here, this one
# symlinks nothing and ships no config of its own.
#
# COSMIC keeps its settings in ~/.config/cosmic/<component>/v1/<key> -- one file
# per key, in RON -- and every one of those files is rewritten by cosmic-settings
# whenever a preference changes in the GUI. There is no direction of flow to
# reverse: the GUI is the source of truth, not this repo. Symlinking that tree in
# here would give the old ulauncher problem (a config directory the app owns and
# rewrites behind you) applied to the whole desktop, so the desktop is configured
# in cosmic-settings and this module only installs it.
#
# The shipped defaults are readable if you want to know what a key looks like
# before overriding it in the GUI:
#   /usr/share/cosmic/com.system76.CosmicComp/v1/
#   /usr/share/cosmic/com.system76.CosmicSettings.Shortcuts/v1/defaults
# They are already vim-style: Super+h/j/k/l focuses, Super+Shift+h/j/k/l moves,
# Super+Ctrl+h/j/k/l switches workspace, Super+q closes.

# ------------------------------------------------------------------- the desktop

# @cosmic-desktop pulls the shell -- comp, panel, applets, launcher,
# notifications, settings, settings-daemon, idle, bg, osd, workspaces,
# screenshot -- plus cosmic-term, cosmic-files, cosmic-edit, cosmic-player and
# cosmic-store. The greeter and the portal are not in the group, and they are
# what make it a login target and a working screencast/file-chooser session.
#
# Not installed: @cosmic-desktop-apps. Despite the name it is not COSMIC's own
# apps (those are in the group above) -- it is ark, thunderbird, nheko,
# rhythmbox, okular and gnome-system-monitor.
sudo dnf install -y @cosmic-desktop cosmic-greeter xdg-desktop-portal-cosmic

# ------------------------------------------------------------------- the greeter

# greetd stays -- cosmic-greeter *is* a greetd greeter. What changes is which
# config greetd starts with: cosmic-greeter ships its own
# /etc/greetd/cosmic-greeter.toml plus a unit that runs
#     greetd --config /etc/greetd/cosmic-greeter.toml
# aliased to display-manager.service. So it and the plain greetd.service this
# repo used to configure are mutually exclusive: both want vt1, and the old one
# has to go down before the new one comes up.
#
# Not restarted here. A greeter restart takes its VT and every session under it
# down, so this lands at the next logout -- which is also why the recovery path
# below is worth knowing before rebooting.
sudo systemctl disable --now greetd.service 2>/dev/null || true
sudo systemctl enable cosmic-greeter-daemon.service
sudo systemctl enable cosmic-greeter.service

# ------------------------------------------------- hardware, media, and codecs

# None of this is COSMIC-specific -- it is the graphics stack, the audio stack
# and the codec set that used to live in the old ui/install.sh and would
# otherwise have been dropped along with it.
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
  wl-clipboard \
  brightnessctl \
  playerctl \
  pipewire \
  pipewire-pulseaudio \
  pipewire-alsa \
  wireplumber \
  alsa-utils \
  bluez \
  bluez-tools \
  v4l2loopback \
  v4l-utils \
  yt-dlp

systemctl --user enable --now pipewire.service
systemctl --user enable --now pipewire-pulse.service
systemctl --user enable --now wireplumber.service

# wl-clipboard is not optional here: nvim's remote_clipboard prefers wl-copy /
# wl-paste when a Wayland display exists, and cosmic-comp implements
# zwlr_data_control_manager_v1, so both work unchanged.

# Fedora ships ffmpeg-free (no libx264/libx265, hardware encoders only). RPM
# Fusion's ffmpeg is the full build, and the two conflict because both Provide
# ffmpeg-free -- so a plain `dnf install ffmpeg` fails the whole transaction
# rather than replacing it. Swap explicitly, and only once.
if ! rpm -q ffmpeg >/dev/null 2>&1; then
  if rpm -q ffmpeg-free >/dev/null 2>&1; then
    sudo dnf swap -y --allowerasing ffmpeg-free ffmpeg
  else
    sudo dnf install -y ffmpeg
  fi
fi

# ------------------------------------------------------------- the old sway stack

# Removed rather than left installed. With the ui/ module gone there is no
# config behind any of it, so keeping the packages would only mean the greeter
# offering a sway session that opens to an unconfigured desktop.
#
# wf-recorder goes for a second reason that is not tidiness: cosmic-comp
# implements ext-image-copy-capture, not wlr-screencopy, and wf-recorder speaks
# only the latter, so it cannot capture anything here whatever config exists.
# See "Screen capture" in CLAUDE.md.
#
# tuigreet goes too. It was the recovery greeter, and greetd's own built-in
# agreety replaces it in that role at no install cost -- see CLAUDE.md.
sway_stack=(
  swayfx sway-config-upstream sway-wallpapers sway-systemd
  swayidle swaylock swaybg
  waybar mako gtklock gtkgreet tuigreet ulauncher fuzzel
  wf-recorder xdg-desktop-portal-wlr
)
to_remove=()
for pkg in "${sway_stack[@]}"; do
  rpm -q "$pkg" >/dev/null 2>&1 && to_remove+=("$pkg")
done
if ((${#to_remove[@]})); then
  sudo dnf remove -y "${to_remove[@]}"
fi

cat <<'NOTES'

COSMIC installed. The greeter changes at the next logout, not now -- restarting
it would take this session down with it.

Set in cosmic-settings once you are in:
  Appearance   wallpaper -> ~/fedora/wallpapers/background.jpg, accent colour
  Appearance   interface font -> Inter, monospace font -> Hack Nerd Font Mono
  Input        keyboard layouts (this replaces the old kblayout script)

If the greeter ever fails to come up, log in on another VT and point greetd at
its built-in fallback -- edit /etc/greetd/cosmic-greeter.toml to
`command = "agreety --cmd start-cosmic"` and restart cosmic-greeter.service.
NOTES
