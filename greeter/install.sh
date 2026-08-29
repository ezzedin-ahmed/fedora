#!/usr/bin/env bash
#
# greetd + tuigreet: boot straight into sway, with a TUI greeter on logout.

set -Eeuo pipefail

sudo dnf install -y greetd tuigreet

sudo install -Dm644 "$HOME/fedora/greeter/config.toml" /etc/greetd/config.toml

sudo systemctl enable greetd.service
sudo systemctl set-default graphical.target

echo "Done. Reboot to boot into sway."
