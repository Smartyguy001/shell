#!/usr/bin/env bash
# Build an Arch Linux VM image running Hyprland with the Caelestia dots, with
# caelestia-shell built from source, for testing the shell from a non-Arch host.
#
# Runs on a Debian/Ubuntu host with KVM available. Idempotent: an existing image
# is reused unless FORCE_REBUILD=1. Takes ~45-60 min on a cold run (AUR builds).
#
#   ./build-arch-vm.sh                        # upstream shell @ main
#   SHELL_REPO=https://github.com/you/shell.git SHELL_REF=my-branch ./build-arch-vm.sh
#   FORCE_REBUILD=1 ./build-arch-vm.sh
#
# Boot it afterwards with start-arch-vm.sh; rebuild the shell at another ref
# without rebuilding the image with rebuild-shell.sh.
set -euo pipefail

VM_DIR=${VM_DIR:-$HOME/arch}
IMG=$VM_DIR/arch.raw
IMG_SIZE=${IMG_SIZE:-25G}
BOOTSTRAP_URL=${BOOTSTRAP_URL:-https://geo.mirror.pkgbuild.com/iso/latest/archlinux-bootstrap-x86_64.tar.zst}
MIRROR=${MIRROR:-'https://geo.mirror.pkgbuild.com/$repo/os/$arch'}
GUEST_USER=${GUEST_USER:-devin}
GUEST_PASS=${GUEST_PASS:-arch}
SSH_PORT=${SSH_PORT:-2222}
BUILD_CPUS=${BUILD_CPUS:-$(nproc)}
BUILD_MEM=${BUILD_MEM:-8192}
ROOTFS=$VM_DIR/root.x86_64
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

log() { printf '\n=== %s\n' "$*"; }

if [[ -f $IMG && ${FORCE_REBUILD:-0} != 1 ]]; then
    log "$IMG already exists, nothing to do (FORCE_REBUILD=1 to rebuild)"
    exit 0
fi

log 'Installing host dependencies'
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    qemu-system-x86 qemu-utils arch-install-scripts zstd sshpass curl gdisk

[[ -e /dev/kvm ]] || { echo 'no /dev/kvm; this host cannot run the VM' >&2; exit 1; }

mkdir -p "$VM_DIR"
cd "$VM_DIR"

log 'Fetching Arch bootstrap tarball'
if [[ ! -d $ROOTFS ]]; then
    curl -fsSL -o bootstrap.tar.zst "$BOOTSTRAP_URL"
    sudo tar --use-compress-program=unzstd -xf bootstrap.tar.zst
    rm -f bootstrap.tar.zst
fi

log 'Creating and partitioning the disk image'
rm -f "$IMG"
qemu-img create -f raw "$IMG" "$IMG_SIZE" >/dev/null
LOOP=$(sudo losetup -fP --show "$IMG")
cleanup() {
    sudo umount -R "$ROOTFS/mnt" 2>/dev/null || sudo umount -lR "$ROOTFS/mnt" 2>/dev/null || true
    for m in dev/pts dev proc sys run; do
        sudo umount -lR "$ROOTFS/$m" 2>/dev/null || true
    done
    # pacman-key leaves a gpg-agent running inside the bootstrap chroot, which pins the loop device
    sudo pkill -f "$ROOTFS.*gpg-agent" 2>/dev/null || true
    sleep 1
    sudo losetup -d "$LOOP" 2>/dev/null || true
}
trap cleanup EXIT

# 1 MiB BIOS boot partition (GRUB core.img) + ext4 root; SeaBIOS boots this without firmware blobs.
sudo sgdisk -Z "$LOOP" >/dev/null
sudo sgdisk -n1:0:+1M -t1:ef02 -c1:bios -n2:0:0 -t2:8300 -c2:root "$LOOP" >/dev/null
sudo partx -u "$LOOP" || sudo partprobe "$LOOP"
sleep 1
sudo mkfs.ext4 -q -F -L archroot "${LOOP}p2"

log 'Mounting target and preparing the bootstrap chroot'
sudo mkdir -p "$ROOTFS/mnt"
sudo mount "${LOOP}p2" "$ROOTFS/mnt"
sudo mount --bind /dev "$ROOTFS/dev"
sudo mount --bind /dev/pts "$ROOTFS/dev/pts"
sudo mount -t proc proc "$ROOTFS/proc"
sudo mount -t sysfs sys "$ROOTFS/sys"
sudo mount -t tmpfs run "$ROOTFS/run"
sudo cp /etc/resolv.conf "$ROOTFS/etc/resolv.conf"
echo "Server = $MIRROR" | sudo tee "$ROOTFS/etc/pacman.d/mirrorlist" >/dev/null

log 'Initialising pacman keyring'
sudo chroot "$ROOTFS" /bin/bash -c 'pacman-key --init && pacman-key --populate archlinux' >/dev/null

log 'Installing base system and Hyprland'
sudo chroot "$ROOTFS" /bin/bash -c "pacstrap -K /mnt \
    base linux linux-firmware grub openssh sudo networkmanager \
    base-devel git rust vim python \
    mesa vulkan-swrast hyprland xorg-xwayland qt5-wayland qt6-wayland polkit foot"

log 'Configuring the guest'
UUID=$(sudo blkid -s UUID -o value "${LOOP}p2")
sudo chroot "$ROOTFS" /bin/bash -e -s <<CHROOT
echo "UUID=$UUID / ext4 rw,relatime 0 1" > /mnt/etc/fstab
arch-chroot /mnt /bin/bash -e -s <<'INNER'
ln -sf /usr/share/zoneinfo/UTC /etc/localtime
echo 'en_US.UTF-8 UTF-8' > /etc/locale.gen
locale-gen
echo 'LANG=en_US.UTF-8' > /etc/locale.conf
echo archvm > /etc/hostname
printf '127.0.0.1 localhost\n::1 localhost\n127.0.1.1 archvm\n' > /etc/hosts
echo "root:$GUEST_PASS" | chpasswd
useradd -m -G wheel -s /bin/bash $GUEST_USER
echo "$GUEST_USER:$GUEST_PASS" | chpasswd
echo '%wheel ALL=(ALL:ALL) NOPASSWD: ALL' > /etc/sudoers.d/wheel
systemctl enable NetworkManager sshd

# Serial console for headless debugging, plus a fixed mode for the virtio-gpu output.
sed -i 's|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 console=tty0 console=ttyS0,115200 video=Virtual-1:1600x900"|' /etc/default/grub
sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=1/' /etc/default/grub
echo 'GRUB_TERMINAL="console serial"' >> /etc/default/grub
echo 'GRUB_SERIAL_COMMAND="serial --unit=0 --speed=115200"' >> /etc/default/grub
grub-install --target=i386-pc $LOOP
grub-mkconfig -o /boot/grub/grub.cfg
systemctl enable serial-getty@ttyS0.service

# No display manager: autologin on tty1 and start Hyprland from the login shell.
mkdir -p /etc/systemd/system/getty@tty1.service.d
printf '[Service]\nExecStart=\nExecStart=-/usr/bin/agetty --autologin $GUEST_USER --noclear %%I \$TERM\n' \
    > /etc/systemd/system/getty@tty1.service.d/autologin.conf
INNER
CHROOT

# The VM has no GPU, so Hyprland runs on llvmpipe.
sudo tee "$ROOTFS/mnt/home/$GUEST_USER/.bash_profile" >/dev/null <<'PROFILE'
[[ -f ~/.bashrc ]] && . ~/.bashrc
if [ -z "$WAYLAND_DISPLAY" ] && [ "$XDG_VTNR" = 1 ]; then
    export LIBGL_ALWAYS_SOFTWARE=1
    export WLR_RENDERER_ALLOW_SOFTWARE=1
    export XDG_RUNTIME_DIR=/run/user/$(id -u)
    exec Hyprland > ~/hyprland.log 2>&1
fi
PROFILE

# The virtio-gpu output comes up at 640x480 without an explicit mode.
sudo mkdir -p "$ROOTFS/mnt/home/$GUEST_USER/.config/caelestia"
sudo tee "$ROOTFS/mnt/home/$GUEST_USER/.config/caelestia/hypr-user.lua" >/dev/null <<'LUA'
hl.monitor({ output = "Virtual-1", mode = "1600x900@60", position = "0x0", scale = 1 })
LUA
sudo chroot "$ROOTFS" chown -R 1000:1000 "/mnt/home/$GUEST_USER"

cleanup
trap - EXIT
sync

log 'Booting the guest headless to install the dots and build the shell'
qemu-system-x86_64 -enable-kvm -m "$BUILD_MEM" -smp "$BUILD_CPUS" -cpu host \
    -drive file="$IMG",format=raw,if=virtio \
    -netdev user,id=n0,hostfwd=tcp::"$SSH_PORT"-:22 -device virtio-net-pci,netdev=n0 \
    -display none -serial file:"$VM_DIR/build-console.log" &
QEMU_PID=$!
trap 'kill $QEMU_PID 2>/dev/null || true' EXIT

SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR)
guest() { sshpass -p "$GUEST_PASS" ssh "${SSH_OPTS[@]}" -p "$SSH_PORT" "$GUEST_USER@127.0.0.1" "$@"; }

for _ in $(seq 60); do
    guest true 2>/dev/null && break
    sleep 5
done
guest true || { echo 'guest never came up; see build-console.log' >&2; exit 1; }

log 'Copying installer scripts into the guest'
guest 'mkdir -p ~/dev-vm'
sshpass -p "$GUEST_PASS" scp "${SSH_OPTS[@]}" -P "$SSH_PORT" \
    "$HERE/guest-install.sh" "$HERE/build-shell.sh" "$HERE/install-dots.py" \
    "$GUEST_USER@127.0.0.1:dev-vm/"
guest 'chmod +x ~/dev-vm/*'

log 'Installing the dots and building caelestia-shell'
guest "SHELL_REPO='${SHELL_REPO:-https://github.com/caelestia-dots/shell.git}' \
       SHELL_REF='${SHELL_REF:-main}' \
       DOTS_REPO='${DOTS_REPO:-https://github.com/caelestia-dots/caelestia.git}' \
       DOTS_REF='${DOTS_REF:-main}' ~/dev-vm/guest-install.sh"

guest 'sudo systemctl poweroff' || true
wait $QEMU_PID 2>/dev/null || true
trap - EXIT

log "Done. Image at $IMG — boot it with $HERE/start-arch-vm.sh"
