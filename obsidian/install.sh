#!/usr/bin/env bash
#
# Obsidian, from the latest upstream AppImage (not packaged in Fedora/RPM Fusion).

set -Eeuo pipefail

BIN="$HOME/.local/bin/obsidian"
ICON="$HOME/.local/share/icons/hicolor/512x512/apps/obsidian.png"
DESKTOP="$HOME/.local/share/applications/obsidian.desktop"

# AppImages mount through libfuse2, which Fedora does not install by default.
rpm -q fuse-libs >/dev/null 2>&1 || sudo dnf install -y fuse fuse-libs

# /releases/latest is the Android build (an .apk) as often as not, since desktop
# and mobile ship from the same repo. Take the newest release with an AppImage.
url=$(curl -fsSL "https://api.github.com/repos/obsidianmd/obsidian-releases/releases?per_page=30" |
  jq -r '[.[] | select(.prerelease == false)
              | .assets[] | select(.name | test("\\.AppImage$"))
              | select(.name | test("arm64|aarch64") | not)][0].browser_download_url')

mkdir -p "$(dirname "$BIN")" "$(dirname "$ICON")" "$(dirname "$DESKTOP")"

# Clear any previous install first: if $BIN is a stale symlink, curl follows it
# and writes to (or fails on) the old target instead.
rm -f "$BIN"

echo "Downloading ${url##*/}..."
curl -fL --progress-bar "$url" -o "$BIN"
chmod +x "$BIN"

# .DirIcon is only a symlink into usr/share, so extract the real path.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
(cd "$tmp" && "$BIN" --appimage-extract 'usr/share/icons/hicolor/512x512/apps/*.png' >/dev/null 2>&1) || true
icon=$(find "$tmp" -name '*.png' -type f | head -1)
[[ -n $icon ]] && cp -f "$icon" "$ICON"

sed -e "s|@EXEC@|$BIN|" -e "s|@ICON@|$ICON|" obsidian.desktop >"$DESKTOP"

echo "Installed to $BIN"
