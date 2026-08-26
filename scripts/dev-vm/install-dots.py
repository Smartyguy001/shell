#!/usr/bin/env python3
"""Manual installation of the Caelestia dots, following the manifest.

Equivalent to `caelestia install`, but without the CLI's install command: it
reads manifest.toml from a dots checkout, installs the packages of the enabled
components and copies their entries into place. Used by the dev VM so the shell
itself can be built from source instead of pulled from the AUR.

    ./install-dots.py <dots-checkout> [--aur-helper paru] [--skip-packages PKG...]
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import tomllib
from pathlib import Path


LOCAL_PREFIX = "local:"


def expand(value: str) -> str:
    config_home = os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config"))
    return os.path.expandvars(value.replace("$XDG_CONFIG_HOME", config_home))


def run(cmd: list[str] | str, *, check: bool = True) -> int:
    shell = isinstance(cmd, str)
    print(f"  $ {cmd if shell else ' '.join(cmd)}", flush=True)
    return subprocess.run(cmd, shell=shell, check=check).returncode


def install_packages(packages: list[str], helper: str, dots: Path) -> None:
    # The manifest refers to PKGBUILDs shipped in the dots repo as local:<path>.
    local = [p.removeprefix(LOCAL_PREFIX) for p in packages if p.startswith(LOCAL_PREFIX)]
    remote = [p for p in packages if not p.startswith(LOCAL_PREFIX)]
    if remote:
        run([helper, "-S", "--needed", "--noconfirm", "--skipreview", *remote])
    for pkgbuild in local:
        run(f"cd {dots / pkgbuild} && makepkg -si --needed --noconfirm")


def copy_entry(src: Path, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    if src.is_dir():
        shutil.copytree(src, dest, dirs_exist_ok=True)
    else:
        shutil.copy2(src, dest)
    print(f"  {src} -> {dest}", flush=True)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("dots", type=Path, help="path to a caelestia dots checkout")
    parser.add_argument("--aur-helper", default="paru")
    parser.add_argument(
        "--skip-packages",
        nargs="*",
        default=[],
        help="packages to leave out (e.g. caelestia-shell when building it from source)",
    )
    parser.add_argument(
        "--components",
        nargs="*",
        default=None,
        help="components to enable (default: those marked default in the manifest)",
    )
    args = parser.parse_args()

    manifest = tomllib.loads((args.dots / "manifest.toml").read_text())
    skip = set(args.skip_packages)

    def is_enabled(component: dict) -> bool:
        if args.components is None:
            return component.get("default", False)
        return component["name"] in args.components

    enabled = [c for c in manifest.get("components", []) if is_enabled(c)]
    print(f":: Components: {', '.join(c['name'] for c in enabled)}", flush=True)

    packages = [p for p in manifest.get("packages", []) if p not in skip]
    for component in enabled:
        packages += [p for p in component.get("packages", []) if p not in skip]
    print(":: Installing packages", flush=True)
    install_packages(sorted(set(packages)), args.aur_helper, args.dots)

    print(":: Installing config entries", flush=True)
    for component in enabled:
        for entry in component.get("entries", []):
            copy_entry(args.dots / entry["src"], Path(expand(entry["dest"])))

    print(":: Running post-install hooks", flush=True)
    for hook in manifest.get("post_install", []) + [
        h for component in enabled for h in component.get("post_install", [])
    ]:
        # Hooks talk to a running Hyprland/shell, which does not exist during an
        # image build, so a failure here is not fatal.
        if run(hook, check=False) != 0:
            print(f"  warning: hook failed: {hook}", flush=True)

    return 0


if __name__ == "__main__":
    sys.exit(main())
