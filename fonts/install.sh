#!/usr/bin/env bash
set -Eeuo pipefail

# Inter is the UI sans: an open face drawn along the same lines as macOS's SF,
# which Apple licenses only for its own platforms. It has no Arabic, so Noto
# Sans Arabic carries that half -- see fontconfig/fonts.conf for how the two are
# paired. Hack Nerd Font is vendored in this directory rather than packaged,
# for the icon glyphs waybar, tmux and Neovim draw.
for pkg in rsms-inter-fonts google-noto-sans-arabic-fonts google-noto-color-emoji-fonts; do
  rpm -q "$pkg" >/dev/null 2>&1 || sudo dnf install -y "$pkg"
done

# -n (--no-dereference) matters: without it, a rerun where the target is
# already a symlink-to-directory makes ln descend into it and create a
# nested <module>/<module> link instead of replacing the symlink.
ln -vfsn $HOME/fedora/fonts/ $HOME/.local/share/fonts

# The generic-family defaults. fontconfig/ lives inside the directory that is
# itself the font path, so fontconfig scans it looking for fonts and finds
# none; that is harmless, and it keeps the module self-contained.
mkdir -p $HOME/.config
ln -vfsn $HOME/fedora/fonts/fontconfig/ $HOME/.config/fontconfig

# Both links point at directories fontconfig tracks by mtime, so a rerun that
# changes nothing still leaves the cache correct. Forced here so that a fresh
# install does not depend on that.
fc-cache -f >/dev/null
echo "font cache rebuilt"
