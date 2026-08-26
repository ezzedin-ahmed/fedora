#!/usr/bin/env bash
#
# NVIDIA proprietary driver for the discrete GPU on this Optimus laptop.
#
# The Intel iGPU keeps driving the sway session; the NVIDIA card is only used
# by applications explicitly offloaded to it (see the notes printed at the end).
# Requires the RPM Fusion nonfree repo, which base/install.sh sets up.

set -Eeuo pipefail

if ! dnf repolist 2>/dev/null | grep -q '^rpmfusion-nonfree'; then
  echo "error: RPM Fusion nonfree is not enabled; run base/install.sh first" >&2
  exit 1
fi

# akmod builds an out-of-tree kernel module. Under Secure Boot it must be signed
# and the key enrolled via MOK, otherwise the module silently fails to load.
if command -v mokutil >/dev/null 2>&1 && mokutil --sb-state 2>/dev/null | grep -qi 'enabled'; then
  echo "warning: Secure Boot is enabled. The akmod-built module will not load" >&2
  echo "         until its signing key is enrolled with mokutil." >&2
fi

sudo dnf install -y \
  akmod-nvidia \
  xorg-x11-drv-nvidia \
  xorg-x11-drv-nvidia-cuda \
  libva-nvidia-driver \
  kernel-devel

# akmods normally runs from a dnf trigger, but it is asynchronous; force it so a
# failure surfaces here rather than as a black screen after reboot.
echo "Building the kernel module (this takes a few minutes)..."
sudo akmods --force

sudo dracut --force

echo
if modinfo -F version nvidia >/dev/null 2>&1; then
  echo "nvidia module built: $(modinfo -F version nvidia)"
else
  echo "warning: the nvidia module is not visible to modinfo yet." >&2
  echo "         Check 'sudo akmods --force' output before rebooting." >&2
fi

cat <<'NOTES'

Reboot to load the driver, then verify with:

    nvidia-smi

This is a hybrid-graphics (Optimus) machine, so sway keeps rendering on the
Intel GPU. Nothing uses the NVIDIA card until you offload to it explicitly:

    __NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia <command>

If sway fails to start after the reboot, pin the compositor to the Intel node:

    WLR_DRM_DEVICES=/dev/dri/card0 sway

NOTES
