#!/usr/bin/env bash

set -Eeou pipefail

sudo dnf install neovim jetbrains-mono-fonts-all

sudo dnf install -y \
  python3 \
  python3-pip \
  python3-devel \
  gcc \
  gcc-c++ \
  make \
  just \
  pkg-config \
  openssl-devel \
  golang

if ! command -v rustup >/dev/null 2>&1; then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
fi

source "$HOME/.cargo/env"

if ! command -v uv >/dev/null 2>&1; then
  curl -LsSf https://astral.sh/uv/install.sh | sh
fi

# typst is not packaged in Fedora or RPM Fusion; take the static musl build from
# the latest upstream release.
if ! command -v typst >/dev/null 2>&1; then
  url=$(curl -fsSL "https://api.github.com/repos/typst/typst/releases/latest" |
    jq -r '.assets[] | select(.name == "typst-x86_64-unknown-linux-musl.tar.xz") | .browser_download_url')

  mkdir -p "$HOME/.local/bin"
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT

  echo "Downloading ${url##*/}..."
  curl -fL --progress-bar "$url" -o "$tmp/typst.tar.xz"
  # The tarball nests the binary one directory deep, under the target triple.
  tar -xJf "$tmp/typst.tar.xz" -C "$tmp" --strip-components=1
  install -m 755 "$tmp/typst" "$HOME/.local/bin/typst"
fi

# -n (--no-dereference) matters: without it, a rerun where the target is
# already a symlink-to-directory makes ln descend into it and create a
# nested <module>/<module> link instead of replacing the symlink.
ln -vfsn $HOME/fedora/nvim $HOME/.config/nvim
