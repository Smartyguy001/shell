#!/usr/bin/env bash
# Runs *inside* the Arch guest. Installs paru, the Caelestia dots (manual
# install via install-dots.py) and builds caelestia-shell from source.
#
# Invoked by build-arch-vm.sh; can also be re-run by hand inside the VM.
#
#   SHELL_REPO=... SHELL_REF=... ./guest-install.sh
set -euo pipefail

SHELL_REPO=${SHELL_REPO:-https://github.com/caelestia-dots/shell.git}
SHELL_REF=${SHELL_REF:-main}
DOTS_REPO=${DOTS_REPO:-https://github.com/caelestia-dots/caelestia.git}
DOTS_REF=${DOTS_REF:-main}
SRC_DIR=${SRC_DIR:-$HOME/src}
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

log() { printf '\n=== %s\n' "$*"; }

if ! command -v paru >/dev/null; then
    log 'Building paru'
    # paru-bin is linked against whatever libalpm its packager had, so build from source.
    sudo pacman -S --needed --noconfirm base-devel git rust
    rm -rf /tmp/paru
    git clone -q https://aur.archlinux.org/paru.git /tmp/paru
    (cd /tmp/paru && makepkg -si --noconfirm)
fi

log 'Installing shell dependencies'
# Runtime + build deps from the shell's manual installation instructions.
paru -S --needed --noconfirm --skipreview \
    glibc gcc-libs ddcutil brightnessctl networkmanager lm_sensors aubio \
    pipewire libqalculate power-profiles-daemon qt6-base qt6-declarative \
    qt6-imageformats swappy fish bash cmake ninja qt6-shadertools jq \
    libcava ttf-material-symbols-variable ttf-rubik-vf ttf-cascadia-code-nerd \
    quickshell-git caelestia-cli

log 'Installing the dots'
# The dots pull pipewire-jack, which conflicts with jack2 if something dragged it in.
sudo pacman -Rdd --noconfirm jack2 2>/dev/null || true
mkdir -p "$SRC_DIR"
if [[ -d $SRC_DIR/caelestia/.git ]]; then
    git -C "$SRC_DIR/caelestia" fetch -q origin "$DOTS_REF"
else
    git clone -q "$DOTS_REPO" "$SRC_DIR/caelestia"
fi
git -C "$SRC_DIR/caelestia" checkout -q "$DOTS_REF"
git -C "$SRC_DIR/caelestia" pull -q --ff-only || true
# caelestia-shell is built from source below, so keep the AUR package out.
"$HERE/install-dots.py" "$SRC_DIR/caelestia" --skip-packages caelestia-shell

log "Building caelestia-shell ($SHELL_REPO @ $SHELL_REF)"
"$HERE/build-shell.sh"

log 'Done'
