#!/usr/bin/env bash

set -Eeou pipefail

sudo dnf install -y neovim

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
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile complete
fi

source "$HOME/.cargo/env"

# A profile only applies to a toolchain rustup installs itself, so neither the
# flag above nor `set profile` below retrofits an existing machine: the curl is
# skipped wherever rustup is already present, and running
# `rustup toolchain install stable --profile complete` over an *installed*
# toolchain re-syncs the components it already has instead of adding the missing
# ones. Naming them is the only thing that actually fills the gap. `set profile`
# still earns its line -- it is what makes the *next* toolchain complete.
#
# rust-analyzer and rust-src are the two that matter here, and the two the
# `default` profile leaves out. Their absence is quiet rather than loud: rustup
# drops a ~/.cargo/bin/rust-analyzer shim whether or not the component is
# installed, so rustaceanvim's executable check passes, the server is spawned,
# and it exits immediately with "Unknown binary 'rust-analyzer' in official
# toolchain" -- into lsp.log, with nothing shown in nvim. rust-src is what lets
# it resolve std; without it stdlib completion and goto fail the same way.
rustup set profile complete
rustup component add \
  rust-analyzer \
  rust-src \
  rust-analysis \
  llvm-tools \
  llvm-bitcode-linker \
  rustc-dev \
  rustc-docs

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
