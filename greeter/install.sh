#!/usr/bin/env bash
#
# greetd + gtkgreet: a GTK greeter that authenticates every login, then starts
# sway. gtkgreet is the program gtklock (the lock screen, wm/gtklock/) was
# forked from, so login and unlock look like the same screen; greeter/gtkgreet.css
# is deliberately the same palette and card as wm/gtklock/style.css.
#
# gtkgreet needs a Wayland compositor to run inside, so the greeter session is
# sway with a greeter-only config (greeter/sway-config) that execs gtkgreet and
# exits once it has finalised a login.

set -Eeuo pipefail

# tuigreet is intentionally left installed even though nothing references it
# any more. It is the recovery greeter: it needs no compositor, no GPU and no
# CSS, so if gtkgreet ever fails to come up, switching config.toml back to
#     command = "tuigreet --time --remember --cmd sway"
# from a TTY and rerunning this script is a guaranteed way back in.
sudo dnf install -y greetd gtkgreet sway tuigreet

# Everything the greeter reads has to be a root-owned copy under /etc/greetd.
# It cannot be symlinked into this repo the way every other module does it:
# the greeter runs as the greetd user and this user's home is 0700, so the whole
# repo -- CSS, wallpaper, sway config -- is unreadable to it. Consequence:
# none of these three files is live-on-edit. Changing any of them means
# rerunning this script.
sudo install -Dm644 "$HOME/fedora/greeter/config.toml"   /etc/greetd/config.toml
sudo install -Dm644 "$HOME/fedora/greeter/sway-config"   /etc/greetd/sway-config
sudo install -Dm644 "$HOME/fedora/greeter/gtkgreet.css"  /etc/greetd/gtkgreet.css
sudo install -Dm644 "$HOME/fedora/wm/wallpapers/background.jpg" /etc/greetd/background.jpg

# gtkgreet's session picker reads /etc/greetd/environments, a newline-separated
# list of command lines. The package's %post generates it from the installed
# .desktop files the first time and never touches it again, so a session
# installed later is missing from the list until this is rerun. `--command sway`
# in greeter/sway-config is what keeps sway first and preselected regardless.
if [ -x /usr/libexec/gtkgreet-update-environments ]; then
  sudo /usr/libexec/gtkgreet-update-environments -w /etc/greetd/environments
fi

# Catch a CSS syntax error now rather than at the next login. GTK does not
# fail on a bad stylesheet -- it logs a warning and carries on unstyled, which
# from the greeter means a white-on-white Adwaita prompt and no obvious cause.
# GTK3 ships no CSS linter, so ask the parser itself. Skipped, not fatal, if
# python3-gobject is not installed.
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

# greetd reads its config only at start, so the copies above do nothing until
# it restarts. Restarting tears down greetd's VT and every session started from
# it, so do it only when there is nothing to lose -- from a TTY with no
# compositor up. With sway running, the change lands at the next logout anyway,
# and killing the user's session to apply a config file is never worth it.
#
# The no-sway case is also the recovery path: a bad config leaves you bouncing
# off the greeter, and this is what puts a fixed one into effect without a
# reboot.
#
# The -u is load-bearing now that the *greeter* is a sway too. A bare
# `pgrep -x sway` matches greetd's greeter compositor, which is running
# whenever the login screen is up -- so the guard would be true even from a
# TTY and the restart, i.e. the whole recovery path, would never fire.
# Restricting to this user's own uid sees only a real desktop session, since
# the greeter's sway runs as greetd.
if pgrep -x -u "$(id -u)" sway >/dev/null; then
  echo "Your sway session is running; leaving greetd alone. The new config applies at next login."
else
  echo "Restarting greetd to pick up the new config..."
  sudo systemctl restart greetd.service
fi

echo "Done."
