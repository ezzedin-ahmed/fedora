#!/usr/bin/env bash

set -Eeuo pipefail

sudo dnf install -y tmux

ln -vfs $HOME/fedora/tmux/ $HOME/.config/tmux
