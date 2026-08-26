#!/usr/bin/env bash
# Boot the Arch dev VM built by build-arch-vm.sh.
#
#   ./start-arch-vm.sh              # GUI window (Hyprland + Caelestia on tty1)
#   HEADLESS=1 ./start-arch-vm.sh   # no window, serial log only
#
# Guest credentials: devin/arch (passwordless sudo), root/arch.
# SSH: ssh -p 2222 devin@127.0.0.1
# Hyprland runs on llvmpipe, so expect soft framerates.
set -euo pipefail

VM_DIR=${VM_DIR:-$HOME/arch}
IMG=$VM_DIR/arch.raw
MEM=${MEM:-8192}
CPUS=${CPUS:-$(nproc)}
SSH_PORT=${SSH_PORT:-2222}
RES=${RES:-1600x900}

[[ -f $IMG ]] || { echo "$IMG not found; run build-arch-vm.sh first" >&2; exit 1; }

display=(-device "virtio-vga,xres=${RES%x*},yres=${RES#*x}" -display gtk)
[[ ${HEADLESS:-0} == 1 ]] && display=(-display none)

exec qemu-system-x86_64 \
    -enable-kvm -m "$MEM" -smp "$CPUS" -cpu host \
    -drive file="$IMG",format=raw,if=virtio \
    -netdev user,id=n0,hostfwd=tcp::"$SSH_PORT"-:22 \
    -device virtio-net-pci,netdev=n0 \
    "${display[@]}" -serial file:"$VM_DIR/console.log" "$@"
