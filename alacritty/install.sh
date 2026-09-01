#!/usr/bin/env bash

set -Eeou pipefail

# -n (--no-dereference) matters: without it, a rerun where the target is
# already a symlink-to-directory makes ln descend into it and create a
# nested <module>/<module> link instead of replacing the symlink.
ln -vfsn $HOME/fedora/alacritty/ $HOME/.config/alacritty
