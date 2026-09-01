#!/usr/bin/env bash

set -Eeuo pipefail

# Symlinks first. These depend on no package being present, and putting them
# after the dnf calls meant one unrelated package conflict (ffmpeg vs
# ffmpeg-free) aborted the script under `set -e` and silently skipped every
# link. Config should land even if an install fails.
# -n (--no-dereference) matters: without it, a rerun where the target is
# already a symlink-to-directory makes ln descend into it and create a
# nested <module>/<module> link instead of replacing the symlink.
ln -vfsn $HOME/fedora/wm/sway $HOME/.config/sway
ln -vfsn $HOME/fedora/wm/waybar $HOME/.config/waybar
ln -vfsn $HOME/fedora/wm/mako $HOME/.config/mako
ln -vfsn $HOME/fedora/wm/fuzzel/ $HOME/.config/fuzzel
ln -vfsn $HOME/fedora/wm/gtklock $HOME/.config/gtklock

# GTK ships these as real (often empty) directories; ln -s into an existing
# directory would nest instead of replacing, so clear them out first.
for d in gtk-3.0 gtk-4.0; do
  if [ -d "$HOME/.config/$d" ] && [ ! -L "$HOME/.config/$d" ]; then
    rmdir "$HOME/.config/$d" 2>/dev/null ||
      echo "warning: $HOME/.config/$d is not empty; not replacing it" >&2
  fi
  [ -e "$HOME/.config/$d" ] && [ ! -L "$HOME/.config/$d" ] ||
    ln -vfsn "$HOME/fedora/wm/$d" "$HOME/.config/$d"
done

# settings.ini only covers GTK3/GTK4. libadwaita, the xdg-desktop-portal
# appearance setting (which Qt6, Chromium and Firefox follow), and anything
# else reading GSettings need color-scheme set explicitly.
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita'
gsettings set org.gnome.desktop.interface icon-theme 'Adwaita'
gsettings set org.gnome.desktop.interface cursor-theme 'Adwaita'

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
  gtklock \
  waybar \
  fuzzel \
  mako \
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

# Discrete-GPU power. The Quadro cannot runtime-suspend on this hardware (no
# ACPI _PR3 on the root port), so a loaded driver pins it at D0 all session.
# Keeping the modules off at boot lets the card sit in D3hot instead; gpu-up /
# gpu-run bring it back when it is wanted. See wm/nvidia-ondemand.conf.
sudo install -Dm644 "$HOME/fedora/wm/nvidia-ondemand.conf" \
  /etc/modprobe.d/nvidia-ondemand.conf

# nvidia-powerd drives Dynamic Boost, which this GPU reports as "Not
# Supported"; leaving it enabled only reloads the modules at every boot and
# undoes the blacklist above.
if systemctl is-enabled nvidia-powerd.service >/dev/null 2>&1; then
  sudo systemctl disable --now nvidia-powerd.service
fi

# The blacklist only governs the *next* boot, so drop the driver now too and
# the card reaches D3hot without a reboot. Best-effort on purpose: run from a
# session that is still holding the GPU (a pre-pin sway, a live CUDA process)
# and modprobe -r fails with EBUSY, which must not abort the rest of this
# script under `set -e`. gpu-down names whatever is holding it.
if lsmod | grep -q '^nvidia '; then
  "$HOME/fedora/scripts/gpu-down" ||
    echo "warning: NVIDIA driver still loaded; it will stay unloaded from the next boot" >&2
fi

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
