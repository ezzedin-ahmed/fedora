#!/usr/bin/env bash

set -Eeou pipefail

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
  sway \
  sway-systemd \
  swaybg \
  swayidle \
  swaylock \
  waybar \
  fuzzel \
  mako \
  wl-clipboard \
  grim \
  slurp \
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

sudo dnf install -y google-noto-fonts-all
fc-cache -f

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
  ffmpeg \
  v4l2loopback \
  v4l-utils \
  yt-dlp

systemctl --user enable --now pipewire.service
systemctl --user enable --now pipewire-pulse.service
systemctl --user enable --now wireplumber.service

# sudo systemctl enable --now bluetooth

ln -vfs $HOME/fedora/wm/sway $HOME/.config/sway
ln -vfs $HOME/fedora/wm/waybar $HOME/.config/waybar
ln -vfs $HOME/fedora/wm/mako $HOME/.config/mako
ln -vfs $HOME/fedora/wm/fuzzel/ $HOME/.config/fuzzel

# GTK ships these as real (often empty) directories; ln -s into an existing
# directory would nest instead of replacing, so clear them out first.
for d in gtk-3.0 gtk-4.0; do
  if [ -d "$HOME/.config/$d" ] && [ ! -L "$HOME/.config/$d" ]; then
    rmdir "$HOME/.config/$d" 2>/dev/null ||
      echo "warning: $HOME/.config/$d is not empty; not replacing it" >&2
  fi
  [ -e "$HOME/.config/$d" ] && [ ! -L "$HOME/.config/$d" ] ||
    ln -vfs "$HOME/fedora/wm/$d" "$HOME/.config/$d"
done

# settings.ini only covers GTK3/GTK4. libadwaita, the xdg-desktop-portal
# appearance setting (which Qt6, Chromium and Firefox follow), and anything
# else reading GSettings need color-scheme set explicitly.
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita'
gsettings set org.gnome.desktop.interface icon-theme 'Adwaita'
gsettings set org.gnome.desktop.interface cursor-theme 'Adwaita'
