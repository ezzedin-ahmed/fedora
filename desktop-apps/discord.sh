#!/usr/bin/env bash

set -Eeuo pipefail

curl -fL "https://discord.com/api/download?platform=linux&format=rpm" -o "$HOME/Downloads/discord.rpm"
sudo dnf install "$HOME/Downloads/discord.rpm"
