#!/usr/bin/env bash
# Host-side helper: rebuild caelestia-shell inside the running Arch VM from a
# given repo/ref and restart it, so the change can be checked visually.
#
#   ./rebuild-shell.sh my-branch
#   ./rebuild-shell.sh 1a2b3c4 https://github.com/someone/shell.git
set -euo pipefail

SHELL_REF=${1:-${SHELL_REF:-main}}
SHELL_REPO=${2:-${SHELL_REPO:-https://github.com/caelestia-dots/shell.git}}
GUEST_USER=${GUEST_USER:-devin}
GUEST_PASS=${GUEST_PASS:-arch}
SSH_PORT=${SSH_PORT:-2222}
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR)
sshpass -p "$GUEST_PASS" scp "${SSH_OPTS[@]}" -P "$SSH_PORT" "$HERE/build-shell.sh" \
    "$GUEST_USER@127.0.0.1:dev-vm/build-shell.sh"
sshpass -p "$GUEST_PASS" ssh "${SSH_OPTS[@]}" -p "$SSH_PORT" "$GUEST_USER@127.0.0.1" \
    "chmod +x ~/dev-vm/build-shell.sh && SHELL_REPO='$SHELL_REPO' SHELL_REF='$SHELL_REF' ~/dev-vm/build-shell.sh"
