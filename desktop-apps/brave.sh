#!/usr/bin/env bash

set -Eeou pipfail

if ! dnf repolist | grep -q brave-browser; then
  sudo dnf config-manager addrepo --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
fi

sudo dnf install -y brave-browser
