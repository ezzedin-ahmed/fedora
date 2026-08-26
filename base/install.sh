#! /usr/bin/env bash

set -Eeuo pipefail

FEDORA_VERSION="$(rpm -E %fedora)"

sudo dnf upgrade --refresh -y

sudo dnf install -y \
  ca-certificates \
  curl \
  wget \
  git \
  git-lfs \
  openssh-clients \
  openssh-server \
  rsync \
  unzip \
  zip \
  tar \
  gzip \
  bzip2 \
  xz \
  p7zip \
  p7zip-plugins \
  jq \
  tree \
  file \
  which \
  findutils \
  pciutils \
  usbutils \
  util-linux \
  procps-ng \
  lsof \
  htop \
  btop \
  fastfetch \
  bind-utils \
  iproute \
  iputils \
  traceroute \
  nmap \
  socat \
  syncthing \
  android-tools \
  NetworkManager \
  iwlwifi-mvm-firmware

if ! rpm -q rpmfusion-free-release >/dev/null 2>&1; then
  sudo dnf install "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VERSION}.noarch.rpm"
fi

if ! rpm -q rpmfusion-nonfree-release >/dev/null 2>&1; then
  sudo dnf install "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VERSION}.noarch.rpm"
fi

sudo dnf upgrade --refresh -y

# Syncthing runs as a user service. Lingering keeps it alive from boot rather
# than only while a login session exists.
systemctl --user enable --now syncthing.service
sudo loginctl enable-linger "$USER"
