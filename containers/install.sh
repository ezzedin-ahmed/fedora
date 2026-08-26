#!/usr/bin/env bash

set -Eeou pipefail

KUBECONFIG_FILE="$HOME/.kube/config"

if ! dnf repolist | grep -q '^docker-ce-stable'; then
	sudo dnf config-manager addrepo --from-repofile=https://download.docker.com/linux/fedora/docker-ce.repo
fi

sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

sudo systemctl enable --now docker

if ! groups "$USER" | grep -qw docker; then
	sudo usermod -aG docker "$USER"
fi

if ! command -v k3s >/dev/null 2>&1; then
	curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server --write-kubeconfig-mode=644" sh -
fi

mkdir -p "$HOME/.kube"

sudo k3s kubectl config view --raw > "$KUBECONFIG_FILE"
chmod 600 "$KUBECONFIG_FILE"
