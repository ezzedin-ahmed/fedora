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

# One scratch dir for every download below. A second `trap ... EXIT` would
# *replace* this one rather than add to it, so the blocks share a dir instead of
# each taking their own.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# typst is not packaged in Fedora or RPM Fusion; take the static musl build from
# the latest upstream release.
if ! command -v typst >/dev/null 2>&1; then
  url=$(curl -fsSL "https://api.github.com/repos/typst/typst/releases/latest" |
    jq -r '.assets[] | select(.name == "typst-x86_64-unknown-linux-musl.tar.xz") | .browser_download_url')

  mkdir -p "$HOME/.local/bin"

  echo "Downloading ${url##*/}..."
  curl -fL --progress-bar "$url" -o "$tmp/typst.tar.xz"
  # The tarball nests the binary one directory deep, under the target triple.
  tar -xJf "$tmp/typst.tar.xz" -C "$tmp/" --strip-components=1
  install -m 755 "$tmp/typst" "$HOME/.local/bin/typst"
fi

# protoc *is* packaged -- protobuf-compiler -- but Fedora has been stuck on
# 3.19.6 (2022) for years, because the C++ runtime is ABI-coupled to abseil and
# grpc and the whole stack has to move together. Upstream is v36. That gap is
# not cosmetic: 3.19 predates editions entirely, so a `edition = "2023"` file
# fails to parse rather than compiling to something older. Take the release
# binary, the same way typst does.
if ! command -v protoc >/dev/null 2>&1; then
  url=$(curl -fsSL "https://api.github.com/repos/protocolbuffers/protobuf/releases/latest" |
    jq -r '.assets[] | select(.name | test("^protoc-[0-9.]+-linux-x86_64\\.zip$")) | .browser_download_url')

  mkdir -p "$HOME/.local/bin" "$HOME/.local/include"

  echo "Downloading ${url##*/}..."
  curl -fL --progress-bar "$url" -o "$tmp/protoc.zip"
  unzip -q "$tmp/protoc.zip" -d "$tmp/protoc"
  install -m 755 "$tmp/protoc/bin/protoc" "$HOME/.local/bin/protoc"
  # The well-known types (google/protobuf/timestamp.proto and friends) are not
  # optional extras -- protoc resolves them from ../include relative to its own
  # binary, so they have to land beside it. Without them any file that imports
  # one fails with "File not found", which reads like a mistake in the .proto.
  cp -rf "$tmp/protoc/include/google" "$HOME/.local/include/"
fi

# protoc has no Go backend of its own: it discovers code generators as
# `protoc-gen-<name>` executables on PATH and shells out. Neither Go one is
# usefully packaged -- golang-google-protobuf carries protoc-gen-go but at 1.31,
# and protoc-gen-go-grpc lives in grpc-go and is packaged nowhere (grpc-plugins
# is the C++/Python/Ruby/... set, no Go) -- and `go install` is how upstream
# publishes both. They land in $(go env GOPATH)/bin, which fish/config.fish puts
# on PATH; this checks that path directly rather than using `command -v`, since
# bash running this script has not read the fish config.
#
# gopls is deliberately not in this list: LazyVim's go extra declares it as an
# lspconfig server, so mason installs and updates it. rust-analyzer is the one
# LSP this module installs by hand, and only because rustup's shim shadows it.
gobin=$(go env GOBIN)
gobin=${gobin:-$(go env GOPATH)/bin}

for pkg in google.golang.org/protobuf/cmd/protoc-gen-go@latest \
  google.golang.org/grpc/cmd/protoc-gen-go-grpc@latest; do
  bin=${pkg%@*}
  if [[ ! -x "$gobin/${bin##*/}" ]]; then
    echo "Installing ${bin##*/}..."
    go install "$pkg"
  fi
done

# -n (--no-dereference) matters: without it, a rerun where the target is
# already a symlink-to-directory makes ln descend into it and create a
# nested <module>/<module> link instead of replacing the symlink.
ln -vfsn $HOME/fedora/nvim $HOME/.config/nvim
