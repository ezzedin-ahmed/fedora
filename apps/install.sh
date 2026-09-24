#!/usr/bin/env bash

set -Eeuo pipefail

# Slack is in no Fedora repo. Its own rpm drops this repofile at install time,
# so dnf can have the package only *after* a manual install; writing it first
# lets dnf do the whole job, updates included. gpgcheck=0 is upstream's own
# setting, reproduced rather than chosen -- the packages on packagecloud are not
# signed with the key the repofile advertises.
if [[ ! -f /etc/yum.repos.d/slack.repo ]]; then
  sudo tee /etc/yum.repos.d/slack.repo >/dev/null <<'REPO'
[slack]
name=slack
baseurl=https://packagecloud.io/slacktechnologies/slack/fedora/21/x86_64
enabled=1
gpgcheck=0
gpgkey=https://packagecloud.io/gpg.key
sslverify=1
REPO
fi

# zathura is only a shell -- with no backend it opens nothing and says little
# about why.
sudo dnf install -y \
  discord \
  telegram-desktop \
  vlc \
  obs-studio \
  mpv \
  zathura zathura-pdf-mupdf \
  syncthing \
  slack

# The daemon is the point; the package alone does nothing. A user unit rather
# than a system one so it runs as the owner of the files it syncs.
systemctl --user enable --now syncthing.service

# The two apps here that are not packages, both for the same reason and both from
# Flathub. Obsidian ships an AppImage, a Flatpak, a .deb and a Snap, and no rpm;
# Zen ships a tarball and a Flatpak and no rpm, and is in neither Fedora nor RPM
# Fusion. In both cases Flathub carries the upstream build and every dnf route is
# a one-person COPR rebuilding the tarball with no following.
# --user throughout, to match the flathub remote being a user remote.
sudo dnf install -y flatpak
flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
flatpak install --user -y flathub md.obsidian.Obsidian app.zen_browser.zen

# The dock icon, which is the whole reason this block is longer than one line.
#
# Obsidian is Electron, and Electron takes its Wayland app_id from `desktopName`
# in package.json -- a field Obsidian does not set, so the window reports the
# literal string `electron`. Nothing matches that: the exported entry is
# md.obsidian.Obsidian.desktop and its StartupWMClass is an X11 property that
# Wayland has no equivalent of. The shell finds no entry, falls back to its
# generic application icon, and under COSMIC that placeholder is a cog -- so an
# open Obsidian shows the Settings icon. The launcher entry is fine; only a
# *running window* is wrong.
#
# --class is Chromium's flag for setting the app_id, supplying by hand what the
# missing field should have. The flatpak's wrapper reads this file and appends
# each line to the argv, which is the supported way in; one flag per line, no
# quoting (the wrapper word-splits).
#
# Note what is NOT done here. The workaround the wrapper itself documents is
# `flatpak override --nosocket=wayland`, dropping to XWayland where the matching
# key comes from the binary name instead -- which is how Discord and Slack avoid
# this, both being X11 clients by default. On this machine that segfaults on
# startup (exit 139, immediately after loading the asar, and not GPU-related --
# it does it with --disable-gpu too), because the manifest grants only
# fallback-x11. So X11 is not available as an escape hatch here.
obsidian_flags="$HOME/.var/app/md.obsidian.Obsidian/config/obsidian/user-flags.conf"
mkdir -p "$(dirname "$obsidian_flags")"
if [[ ! -f $obsidian_flags ]] || ! grep -q '^--class=' "$obsidian_flags"; then
  echo '--class=md.obsidian.Obsidian' >>"$obsidian_flags"
fi

echo "syncthing: http://localhost:8384"
echo "obsidian: turn off the in-app auto-update, 'flatpak update' handles it"
