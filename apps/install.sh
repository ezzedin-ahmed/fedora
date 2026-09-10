#!/usr/bin/env bash

set -Eeuo pipefail

# Every other module in this repo is a single install.sh; the old desktop-apps/ was the
# exception, one script per app run by hand. This is that set merged.
#
# The apps stay individually addressable -- `./install.sh vlc waterfox` does
# just those, no arguments does all of them -- because being able to skip an
# app was the entire point of the per-file layout, and merging should not cost
# it. Each app is its own dnf transaction for the same reason: one unavailable
# package should not take the rest of the list down.

apps=(waterfox discord telegram vlc obs-studio nautilus obsidian)

install_waterfox() {
  # The OBS repo is the browser's own Fedora channel (isv:BrowserWorks is
  # BrowserWorks, who publish Waterfox), and it is what waterfox.com/download
  # hands out for dnf. Waterfox is in no Fedora repo, and hawkeye116477's
  # third-party one -- the answer most guides still give -- is unmaintained.
  #
  # The path is per-release, so it is built from rpm -E rather than pinned.
  # The guard matches the release too: after a Fedora upgrade the old repofile
  # is still present and still enabled, so an id-only check would skip the
  # re-add and leave dnf pointed at the previous release's directory forever.
  local fedora repofile
  fedora=$(rpm -E %fedora)
  repofile="https://download.opensuse.org/repositories/isv:/BrowserWorks/Fedora_${fedora}/isv:BrowserWorks.repo"

  if ! grep -rqs "Fedora_${fedora}/" /etc/yum.repos.d/*BrowserWorks*.repo; then
    sudo dnf config-manager addrepo --overwrite --from-repofile="$repofile"
  fi

  sudo dnf install -y waterfox

  # Two prefs, and only two, because Gecko already does the right thing.
  #
  # Unlike Chromium -- whose defaults are compiled in as the literal families
  # "Times New Roman" / "Arial" / "Courier New", so it never asks fontconfig
  # for a generic at all -- Gecko's Linux defaults for font.name.{serif,
  # sans-serif,monospace}.* are the strings "serif", "sans-serif" and
  # "monospace". Those go to fontconfig as generics, so fonts/fontconfig/
  # fonts.conf is already in the path: nothing to point at, no placeholder
  # family to invent.
  #
  # What is left is which generic an *unstyled* page gets, and Gecko's answer
  # is serif. Brave was set to render those in the UI sans, so font.default is
  # moved to sans-serif to keep that. It is set per language group, and Arabic
  # is its own group: unlike Chromium, which routes Arabic off the common entry
  # by language, Gecko would otherwise leave ar on serif and render it naskh.
  #
  # user.js, not prefs.js: Waterfox reapplies it at every startup and rewrites
  # prefs.js on exit, so this is both the durable place and the one that is
  # safe to write while the browser is running.
  local found=0 prefs userjs tmp
  if [[ -d $HOME/.waterfox ]]; then
    while IFS= read -r -d '' prefs; do
      found=1
      userjs="$(dirname "$prefs")/user.js"

      # Rewrite in place: drop the lines this script set last time, keep every
      # other user_pref, append the current pair. Idempotent, and it leaves
      # prefs added by hand alone.
      tmp=$(mktemp)
      if [[ -f $userjs ]]; then
        grep -v '^user_pref("font\.default\.\(x-western\|ar\)"' "$userjs" >"$tmp" || true
      fi
      cat >>"$tmp" <<'PREFS'
user_pref("font.default.x-western", "sans-serif");
user_pref("font.default.ar", "sans-serif");
PREFS
      # mktemp is 0600; user.js is not a secret and Waterfox reads it as the
      # owner either way, but match the 0644 a profile file normally has.
      chmod 644 "$tmp"
      mv "$tmp" "$userjs"
      echo "font prefs written to ${userjs#"$HOME"/}"
    done < <(find "$HOME/.waterfox" -mindepth 2 -maxdepth 2 -name prefs.js -print0)
  fi

  ((found == 0)) &&
    echo "No Waterfox profile yet -- rerun this script after the first launch."
  return 0
}

install_discord() {
  # Discord publishes no repo, only a rolling rpm behind a redirect, so this is
  # the one app here that dnf cannot keep updated. Guarded on the package
  # rather than the file: the download URL always serves the current version,
  # so an unguarded rerun would re-fetch ~100MB to install what is already in.
  if rpm -q discord >/dev/null 2>&1; then
    echo "discord already installed -- skipping (dnf will not update it; rerun after a manual remove)"
    return 0
  fi

  local rpm
  rpm=$(mktemp --suffix=.rpm)
  curl -fL "https://discord.com/api/download?platform=linux&format=rpm" -o "$rpm"
  sudo dnf install -y "$rpm"
  rm -f "$rpm"
}

install_telegram()   { sudo dnf install -y telegram-desktop; }
install_vlc()        { sudo dnf install -y vlc; }
install_obs_studio() { sudo dnf install -y obs-studio; }

install_obsidian() {
  # Not packaged in Fedora or RPM Fusion, so this is the upstream AppImage.
  # Unlike discord above there is no rpm to hand dnf, so it is unpacked by hand
  # into ~/.local and given a desktop entry.
  local bin="$HOME/.local/bin/obsidian"
  local icon="$HOME/.local/share/icons/hicolor/512x512/apps/obsidian.png"
  local desktop="$HOME/.local/share/applications/obsidian.desktop"

  # AppImages mount through libfuse2, which Fedora does not install by default.
  rpm -q fuse-libs >/dev/null 2>&1 || sudo dnf install -y fuse fuse-libs

  # /releases/latest is the Android build (an .apk) as often as not, since
  # desktop and mobile ship from the same repo. Take the newest release that
  # actually carries an x86_64 AppImage.
  local url
  url=$(curl -fsSL "https://api.github.com/repos/obsidianmd/obsidian-releases/releases?per_page=30" |
    jq -r '[.[] | select(.prerelease == false)
                | .assets[] | select(.name | test("\\.AppImage$"))
                | select(.name | test("arm64|aarch64") | not)][0].browser_download_url')

  mkdir -p "$(dirname "$bin")" "$(dirname "$icon")" "$(dirname "$desktop")"

  # Clear any previous install first: if $bin is a stale symlink, curl follows
  # it and writes to (or fails on) the old target instead.
  rm -f "$bin"

  echo "Downloading ${url##*/}..."
  curl -fL --progress-bar "$url" -o "$bin"
  chmod +x "$bin"

  # .DirIcon is only a symlink into usr/share, so extract the real path.
  local tmp icon_src
  tmp=$(mktemp -d)
  (cd "$tmp" && "$bin" --appimage-extract 'usr/share/icons/hicolor/512x512/apps/*.png' >/dev/null 2>&1) || true
  icon_src=$(find "$tmp" -name '*.png' -type f | head -1)
  [[ -n $icon_src ]] && cp -f "$icon_src" "$icon"
  rm -rf "$tmp"

  # Written inline rather than kept as a template file beside this script: the
  # paths are only known here, and every other app in this module is one
  # self-contained function with nothing on disk next to it.
  cat >"$desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Obsidian
Comment=Knowledge base that works on local Markdown files
Exec=$bin %u
Icon=$icon
Terminal=false
Categories=Office;TextEditor;Utility;
MimeType=x-scheme-handler/obsidian;
StartupWMClass=obsidian
DESKTOP

  echo "installed to ${bin#"$HOME"/}"
}

# nautilus is also installed by ui/install.sh, because sway's $filemanager
# binding needs a file manager whether or not this module is ever run. Listing
# it here too keeps this module self-contained; dnf makes the repeat a no-op.
install_nautilus()   { sudo dnf install -y nautilus; }

main() {
  local selected=("$@")
  ((${#selected[@]})) || selected=("${apps[@]}")

  local app fn
  for app in "${selected[@]}"; do
    # obs-studio -> install_obs_studio; function names cannot hold the hyphen.
    fn="install_${app//-/_}"
    if ! declare -F "$fn" >/dev/null; then
      echo "unknown app: $app (known: ${apps[*]})" >&2
      return 1
    fi
    echo "==> $app"
    "$fn"
  done
}

main "$@"
