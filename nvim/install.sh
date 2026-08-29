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

ln -vfs $HOME/fedora/nvim $HOME/.config/nvim
