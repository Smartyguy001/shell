# Arch dev VM

An Arch Linux VM running Hyprland with the Caelestia dots, with `caelestia-shell`
built from source, so the shell can be developed and checked visually from a
non-Arch host (e.g. an Ubuntu CI box). Everything is installed the manual way
(dots cloned + `manifest.toml` applied, shell built with CMake) rather than via
`caelestia install`, so any branch or commit can be built and swapped in.

Requires a Linux host with `/dev/kvm` and ~30 GB of free disk.

## Build the image

```sh
./build-arch-vm.sh                                     # upstream shell @ main
SHELL_REPO=https://github.com/you/shell.git SHELL_REF=my-branch ./build-arch-vm.sh
FORCE_REBUILD=1 ./build-arch-vm.sh                     # rebuild from scratch
```

Cold runs take ~45-60 min, mostly `quickshell-git` and the other AUR builds. The
image lands at `~/arch/arch.raw` (25 GB sparse); the script is a no-op if it is
already there.

## Boot it

```sh
./start-arch-vm.sh              # QEMU window, Hyprland + Caelestia on tty1
HEADLESS=1 ./start-arch-vm.sh   # no window, serial log in ~/arch/console.log
```

Guest credentials: `devin`/`arch` (passwordless sudo), `root`/`arch`, and
`ssh -p 2222 devin@127.0.0.1`.

## Test another revision of the shell

With the VM running, from the host:

```sh
./rebuild-shell.sh my-branch
./rebuild-shell.sh 1a2b3c4 https://github.com/someone/shell.git
```

This rebuilds the checkout in `~/.config/quickshell/caelestia` inside the guest
(incremental, ~1 min), installs it and restarts the running shell, so the change
shows up in the QEMU window. `build-shell.sh` does the same from inside the
guest.

## Layout

- `build-arch-vm.sh` — host-side: partitions and pacstraps the image, configures
  autologin into Hyprland, then boots it headless and runs `guest-install.sh`.
- `guest-install.sh` — guest-side: builds `paru`, installs the shell's
  dependencies, applies the dots and builds the shell.
- `install-dots.py` — manual equivalent of `caelestia install`: reads
  `manifest.toml` from a dots checkout, installs each enabled component's
  packages (including the repo-local PKGBUILDs) and copies its config entries.
- `build-shell.sh` — guest-side: clone/checkout a ref of the shell into
  `~/.config/quickshell/caelestia`, `cmake --build`, `cmake --install`, restart.
- `rebuild-shell.sh` — host-side wrapper around `build-shell.sh` over SSH.
- `start-arch-vm.sh` — boot the built image.

## Caveats

- No GPU: Hyprland runs on llvmpipe, so animations and blur are slow.
- No emulated battery, WiFi, Bluetooth or backlight — those widgets stay empty.
  The kernel's `test_power` module can fake a battery if needed.
- QEMU's GTK window swallows Super keybinds; use View → Grab Input, or drive the
  session over SSH.
