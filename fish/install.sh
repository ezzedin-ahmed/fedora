#! /usr/bin/env bash

set -Eeuo pipefail

chsh -s $(which fish)

ln -vfs $HOME/fedora/fish/ $HOME/.config/fish
