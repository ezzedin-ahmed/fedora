#!/usr/bin/env bash
#
# NVIDIA proprietary driver for the discrete GPU on this Optimus laptop.
#
# The Intel iGPU keeps driving the sway session; the NVIDIA card is only used
# by applications explicitly offloaded to it (see the notes printed at the end).
# Requires the RPM Fusion nonfree repo, which base/install.sh sets up.
#
# Branch selection matters here. Since 580, the mainline akmod-nvidia ships only
# the *open* kernel module, which needs a GSP microcontroller on the card --
# Turing (RTX 20xx) and newer. On anything older the module builds and loads
# fine but refuses the GPU at probe time:
#
#   NVRM: ... is not supported by open nvidia.ko because it does not include
#   NVRM: the required GPU System Processor (GSP).
#   nvidia 0000:01:00.0: probe with driver nvidia failed with error -1
#
# and nvidia-smi then reports "couldn't communicate with the NVIDIA driver".
# The Quadro M1000M in this machine is GM107 (Maxwell), so it needs the 580xx
# legacy branch, which still carries the proprietary module.

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

# ---------------------------------------------------------------- branch pick

# Optimus dGPUs show up under either class depending on whether a display is
# wired to them.
gpu=$(lspci -nn -d 10de: | grep -E 'VGA compatible controller|3D controller' | head -1)
if [[ -z $gpu ]]; then
  echo "error: no NVIDIA GPU found on the PCI bus" >&2
  exit 1
fi
devid=$(grep -oE '10de:[0-9a-f]{4}' <<<"$gpu" | head -1 | cut -d: -f2)

# Turing is the GSP cutoff and starts at device id 0x1e00; everything below it
# (Maxwell, Pascal, Volta) is stranded on the 580xx legacy branch. Device ids
# are not strictly ordered by architecture, but they are monotonic across this
# particular boundary, which is the only one that matters.
if (( 16#$devid >= 0x1e00 )); then
  branch=""      # mainline, open module
  suffix=""
else
  branch="580xx" # legacy, proprietary module
  suffix="-580xx"
fi

echo "GPU:    ${gpu#*: }"
echo "Branch: ${branch:-mainline (open kernel module)}"

want=(
  "akmod-nvidia${suffix}"
  "xorg-x11-drv-nvidia${suffix}"
  "xorg-x11-drv-nvidia${suffix}-cuda"
)

# ------------------------------------------------------- drop the other branch

# The branches carry hard Conflicts against each other, so dnf install alone
# fails if the wrong one is present -- it will not remove a conflicting package
# on its own.
#
# --no-autoremove is load-bearing. This is a swap, not a cleanup: the shared
# dependencies (egl-wayland, egl-gbm, nvidia-modprobe, and akmods itself, which
# the build step below needs) are pulled straight back in by the incoming
# branch. Letting dnf autoremove them leaves the system briefly without akmods
# and drags out unrelated packages like the openssl CLI, which akmods uses for
# module signing.
mapfile -t stale < <(
  rpm -qa --qf '%{NAME}\n' \
    'akmod-nvidia*' 'kmod-nvidia*' 'xorg-x11-drv-nvidia*' 'nvidia-settings*' 2>/dev/null |
    if [[ -n $branch ]]; then grep -v -- "-${branch}"; else grep -E -- '-[0-9]+xx'; fi
)

if (( ${#stale[@]} )); then
  echo "Removing the ${branch:+mainline}${branch:-legacy} branch: ${stale[*]}"
  sudo dnf remove -y --no-autoremove "${stale[@]}"
fi

# ------------------------------------------------------------------- install

# akmods needs headers for the *running* kernel, which is not necessarily the
# newest one in the repos.
kdevel="kernel-devel-$(uname -r)"
if ! dnf list --available "$kdevel" >/dev/null 2>&1 && ! rpm -q "$kdevel" >/dev/null 2>&1; then
  kdevel="kernel-devel"
fi

sudo dnf install -y "${want[@]}" libva-nvidia-driver "$kdevel"

# The kernel args from the package are not always enough: if nouveau binds the
# GPU first, the nvidia module loads and then bails with "already bound to
# nouveau". Blacklist it explicitly and rebuild the initramfs afterwards.
sudo tee /etc/modprobe.d/blacklist-nouveau.conf >/dev/null <<'CONF'
blacklist nouveau
options nouveau modeset=0
CONF

sudo dracut --force

# akmods normally runs from a dnf trigger, but it is asynchronous; force it so a
# failure surfaces here rather than as a black screen after reboot. Scope it to
# the running kernel so a stale kernel's build failure is not fatal.
echo "Building the kernel module (this takes a few minutes)..."
sudo akmods --force --kernels "$(uname -r)"

# ------------------------------------------------------- load it, no reboot

# Tear down whatever is loaded from the old branch first. If something still
# holds the module we cannot swap it live and a reboot is the only option --
# say so rather than leaving a half-swapped stack behind.
for m in nvidia_drm nvidia_modeset nvidia_uvm nvidia; do
  if lsmod | grep -q "^${m} "; then
    sudo modprobe -r "$m" 2>/dev/null || true
  fi
done

if lsmod | grep -qE '^nvidia'; then
  echo
  echo "The previous nvidia modules are still in use and could not be unloaded;"
  echo "reboot to finish the swap, then check nvidia-smi." >&2
  exit 0
fi

echo "Loading the module..."
if ! sudo modprobe nvidia; then
  echo "error: modprobe nvidia failed. Check 'sudo akmods --force' output." >&2
  exit 1
fi

echo
echo "nvidia module: $(modinfo -F version nvidia)"

if nvidia-smi >/dev/null 2>&1; then
  nvidia-smi
else
  echo "warning: the module loaded but nvidia-smi still cannot talk to it." >&2
  echo "         Check 'journalctl -k | grep NVRM' for the probe error." >&2
fi

cat <<'NOTES'

This is a hybrid-graphics (Optimus) machine, so sway keeps rendering on the
Intel GPU. Nothing uses the NVIDIA card until you offload to it explicitly:

    __NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia <command>

If sway fails to start after a later reboot, pin the compositor to the Intel
node:

    WLR_DRM_DEVICES=/dev/dri/card0 sway

NOTES
