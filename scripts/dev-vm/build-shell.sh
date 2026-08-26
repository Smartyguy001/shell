#!/usr/bin/env bash
# Runs *inside* the Arch guest. Builds and installs caelestia-shell from source
# into ~/.config/quickshell/caelestia (the manual installation layout), then
# restarts the running shell.
#
#   SHELL_REF=my-feature-branch ./build-shell.sh
#   SHELL_REPO=https://github.com/someone/shell.git SHELL_REF=pr-123 ./build-shell.sh
set -euo pipefail

SHELL_REPO=${SHELL_REPO:-https://github.com/caelestia-dots/shell.git}
SHELL_REF=${SHELL_REF:-main}
QS_DIR=${QS_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/caelestia}

mkdir -p "$(dirname "$QS_DIR")"
if [[ -d $QS_DIR/.git ]]; then
    git -C "$QS_DIR" remote set-url origin "$SHELL_REPO"
    git -C "$QS_DIR" fetch -q origin
else
    rm -rf "$QS_DIR"
    git clone -q "$SHELL_REPO" "$QS_DIR"
fi
git -C "$QS_DIR" checkout -q --detach "origin/$SHELL_REF" 2>/dev/null || git -C "$QS_DIR" checkout -q --detach "$SHELL_REF"
echo ":: building $(git -C "$QS_DIR" rev-parse --short HEAD)"

cd "$QS_DIR"
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/ -DINSTALL_QSCONFDIR="$QS_DIR"
cmake --build build
sudo cmake --install build
sudo chown -R "$USER" "$QS_DIR"

# Restart the shell if a Hyprland session is up (no-op during image builds).
if [[ -n ${WAYLAND_DISPLAY:-} ]] || [[ -d /run/user/$(id -u)/hypr ]]; then
    export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
    export WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-wayland-1}
    caelestia shell -k 2>/dev/null || true
    sleep 1
    caelestia shell -d >/dev/null 2>&1 || true
fi
