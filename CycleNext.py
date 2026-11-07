#!/usr/bin/env python3
"""Advance the live background to the next distinct picture.

Omarchy's omarchy-theme-bg-next compares the symlink text with the paths
`find` prints. On Omarchy 4.5 that symlink often points at the theme file
(~/.config/omarchy/themes/<name>/backgrounds/...) while find lists
~/.config/omarchy/backgrounds/<name>/... and a second copy under the state
dir. Nothing matches, so the command exits 0 and rewrites the symlink to the
same picture.

When ~/.local/bin/omarchy-theme-bg-next exists it still runs, unchanged.
Otherwise this picks the next basename and installs it with
/usr/bin/omarchy-theme-bg-set.
"""

from __future__ import annotations

import os
import sys

EXTS = {
    ".jpg", ".jpeg", ".png", ".gif", ".bmp", ".webp",
    ".mp4", ".m4v", ".mov", ".webm", ".mkv", ".avi",
}


def choose_next(home: str) -> str | None:
    theme_name = ""
    theme_file = os.path.join(home, ".local", "state", "omarchy", "current", "theme.name")
    try:
        with open(theme_file, "r", encoding="utf-8") as handle:
            theme_name = handle.read().strip()
    except OSError:
        theme_name = ""

    directories = []
    if theme_name:
        directories.append(os.path.join(home, ".config", "omarchy", "backgrounds", theme_name))
    directories.append(os.path.join(
        home, ".local", "state", "omarchy", "current", "theme", "backgrounds"))

    # First directory wins for a basename, so the user/theme picture is kept
    # and the state-dir copy of the same name is not a second stop.
    by_name: dict[str, str] = {}
    for directory in directories:
        try:
            names = os.listdir(directory)
        except OSError:
            continue
        for name in names:
            ext = os.path.splitext(name)[1].lower()
            if ext not in EXTS:
                continue
            path = os.path.join(directory, name)
            if not os.path.isfile(path):
                continue
            key = name.lower()
            if key not in by_name:
                by_name[key] = path

    if not by_name:
        return None

    link = os.path.join(home, ".local", "state", "omarchy", "current", "background")
    current_name = ""
    try:
        current_name = os.path.basename(os.path.realpath(link)).lower()
    except OSError:
        current_name = ""

    ordered = sorted(by_name)
    try:
        index = ordered.index(current_name)
    except ValueError:
        index = -1
    return by_name[ordered[(index + 1) % len(ordered)]]


def main(argv: list[str]) -> int:
    home = os.environ.get("HOME", "")
    local = os.path.join(home, ".local", "bin", "omarchy-theme-bg-next")
    if os.path.isfile(local) and os.access(local, os.X_OK):
        os.execv(local, [local])

    target = choose_next(home)
    if not target:
        print("kenburns cycle: no backgrounds", file=sys.stderr)
        return 1
    if "--print" in argv:
        print(target)
        return 0

    setter = "/usr/bin/omarchy-theme-bg-set"
    os.execv(setter, [setter, target])
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
