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

# nouveau has to be kept off the card, or it binds first and the nvidia module
# then bails with "already bound to nouveau". The driver packages already do
# this by adding kernel args at install time, and theirs are *better* than a
# hand-written modprobe.d file: they also cover nova_core, the Rust nouveau
# replacement Fedora ships, which a file saying only "blacklist nouveau" misses.
#
# So only write one -- and pay for the initramfs rebuild -- where the kargs are
# actually absent. On this machine they are not, and this whole block is a
# no-op that saves a 30-60s dracut run on every rerun.
if grep -q 'modprobe.blacklist=.*nouveau' /proc/cmdline; then
  echo "nouveau already blacklisted on the kernel cmdline; nothing to write."
else
  echo "No nouveau karg found; writing a modprobe.d blacklist instead."
  sudo tee /etc/modprobe.d/blacklist-nouveau.conf >/dev/null <<'CONF'
blacklist nouveau
blacklist nova_core
options nouveau modeset=0
CONF
  sudo dracut --force
fi

# akmods normally runs from a dnf trigger, but it is asynchronous; force it so a
# failure surfaces here rather than as a black screen after reboot. Scope it to
# the running kernel so a stale kernel's build failure is not fatal.
echo "Building the kernel module (this takes a few minutes)..."
sudo akmods --force --kernels "$(uname -r)"

# --------------------------------------------------------- verify, no reboot

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

# Load it once, here, purely to prove the akmod build is good -- a broken
# module should surface now rather than as a black screen or a dead nvidia-smi
# days later. It gets unloaded again at the end of this script.
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

# ------------------------------------------------------------- power policy

# The Quadro cannot runtime-suspend on this hardware: no ACPI _PR3 on the PCIe
# root port, and Maxwell has no video-memory-off. So a loaded driver pins the
# card at D0 for the whole session whether or not anything is using it, and
# unbinding is the only lever. Keeping the modules off at boot is what lets it
# come up in D3hot; see nvidia-ondemand.conf for the full reasoning.
#
# This lives here rather than in ui/ because it is driver policy, not desktop
# config -- and installing a blacklist for a driver that module never installs
# only made the ordering between the two matter.
sudo install -Dm644 "$HOME/fedora/nvidia/nvidia-ondemand.conf" \
  /etc/modprobe.d/nvidia-ondemand.conf

# Let prime-run load nvidia_drm without a password prompt.
#
# nvidia_drm must be loaded with modeset=1 for PRIME render offload, and it is
# the one module the setuid nvidia-modprobe helper cannot load -- it handles
# nvidia, nvidia_uvm and nvidia_modeset, but has no drm option. Without this
# rule prime-run only works when typed into an interactive shell: launched from
# a .desktop entry or a sway keybinding there is no terminal for sudo to prompt
# in, so the load fails and the app silently renders on the Intel GPU instead.
#
# Scoped to one exact argv with no wildcards, so it cannot be used to insert an
# arbitrary module. Validated before install because a syntactically broken file
# in sudoers.d breaks sudo entirely -- visudo -c on a temp copy first, and only
# then move it into place.
sudoers_tmp=$(mktemp)
cat >"$sudoers_tmp" <<'SUDOERS'
# Installed by nvidia/install.sh. Lets scripts/prime-run load nvidia_drm with
# modeset=1 from a non-interactive context (.desktop entry, sway keybinding),
# where sudo has no terminal to prompt in. One fixed argv, no wildcards.
%wheel ALL=(root) NOPASSWD: /usr/bin/modprobe nvidia_drm modeset=1
SUDOERS

if sudo visudo -cf "$sudoers_tmp" >/dev/null; then
  sudo install -Dm440 "$sudoers_tmp" /etc/sudoers.d/nvidia-drm
  echo "sudoers rule installed: prime-run can load nvidia_drm without a prompt"
else
  echo "error: generated sudoers file failed validation; not installing it" >&2
fi
rm -f "$sudoers_tmp"

# nvidia-powerd drives Dynamic Boost, which this GPU reports as "Not
# Supported"; leaving it enabled only reloads the modules at every boot and
# undoes the blacklist above.
if systemctl is-enabled nvidia-powerd.service >/dev/null 2>&1; then
  sudo systemctl disable --now nvidia-powerd.service
fi

# The blacklist only governs the *next* boot, so drop the driver now as well
# and the card reaches D3hot without one. Best-effort: a live CUDA process
# makes modprobe -r fail with EBUSY, which must not abort the script under
# `set -e`. gpu-down names whatever is holding it.
"$HOME/fedora/scripts/gpu-down" ||
  echo "warning: driver still loaded; it will stay unloaded from the next boot" >&2

cat <<'NOTES'

Hybrid-graphics (Optimus) machine, so sway keeps rendering on the Intel GPU and
the card above is now unbound and back in D3hot. Two ways to use it:

    <command>              CUDA/compute -- talks to the card directly, and the
                           setuid nvidia-modprobe helper loads the driver for it
    prime-run <command>    graphics -- PRIME render offload

Neither ever powers the card back down, because nothing on this hardware can.
Run `gpu-down` when you are finished with it.

NOTES
