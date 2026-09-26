#!/usr/bin/env python3
"""Bounded, no-follow read/write for ~/.config/omarchy/kenburnswallpaper.json."""

from __future__ import annotations

import os
import secrets
import stat
import sys

MAX_BYTES = 64 * 1024

O_DIRECTORY = getattr(os, "O_DIRECTORY", 0)
O_NOFOLLOW = getattr(os, "O_NOFOLLOW", 0)
O_NONBLOCK = getattr(os, "O_NONBLOCK", 0)


def _open_verified_dir_for(path: str) -> tuple[int, str] | tuple[None, None]:
    abspath = os.path.abspath(path)
    parent = os.path.dirname(abspath)
    name = os.path.basename(abspath)
    if not name or not parent:
        return None, None
    try:
        dir_fd = os.open(parent, O_DIRECTORY | O_NOFOLLOW)
    except OSError:
        return None, None
    try:
        st = os.fstat(dir_fd)
        if not stat.S_ISDIR(st.st_mode):
            return None, None
        if st.st_uid != os.geteuid():
            return None, None
        return dir_fd, name
    except OSError:
        os.close(dir_fd)
        return None, None


def _close_dir_fd(dir_fd: int | None) -> None:
    if dir_fd is not None:
        os.close(dir_fd)


def cmd_read(path: str) -> int:
    dir_fd, name = _open_verified_dir_for(path)
    if dir_fd is None:
        return 1
    try:
        try:
            fd = os.open(name, os.O_RDONLY | O_NOFOLLOW | O_NONBLOCK, dir_fd=dir_fd)
        except FileNotFoundError:
            return 2
        except OSError:
            return 1
        try:
            st = os.fstat(fd)
            if not stat.S_ISREG(st.st_mode):
                return 1
            if st.st_size == 0 or st.st_size > MAX_BYTES:
                return 1
            data = os.read(fd, MAX_BYTES + 1)
            if len(data) == 0 or len(data) > MAX_BYTES:
                return 1
            sys.stdout.buffer.write(data)
            return 0
        finally:
            os.close(fd)
    finally:
        _close_dir_fd(dir_fd)


def cmd_write(path: str, payload: str) -> int:
    raw = payload.encode("utf-8")
    if len(raw) > MAX_BYTES:
        return 1

    abspath = os.path.abspath(path)
    parent = os.path.dirname(abspath)
    if not parent:
        return 1
    try:
        os.makedirs(parent, mode=0o700, exist_ok=True)
    except OSError:
        return 1

    dir_fd, name = _open_verified_dir_for(path)
    if dir_fd is None:
        return 1

    temp_name = ".kenburns-" + secrets.token_hex(16)
    temp_fd: int | None = None
    try:
        try:
            temp_fd = os.open(
                temp_name,
                os.O_WRONLY | os.O_CREAT | os.O_EXCL | O_NOFOLLOW,
                0o600,
                dir_fd=dir_fd,
            )
        except OSError:
            return 1
        try:
            offset = 0
            while offset < len(raw):
                offset += os.write(temp_fd, raw[offset:])
            os.fsync(temp_fd)
        finally:
            os.close(temp_fd)
            temp_fd = None

        os.replace(temp_name, name, src_dir_fd=dir_fd, dst_dir_fd=dir_fd)
        return 0
    except OSError:
        if temp_fd is not None:
            try:
                os.close(temp_fd)
            except OSError:
                pass
        try:
            os.unlink(temp_name, dir_fd=dir_fd)
        except OSError:
            pass
        return 1
    finally:
        _close_dir_fd(dir_fd)


def main() -> None:
    if len(sys.argv) < 3:
        sys.exit(1)
    sub = sys.argv[1]
    path = sys.argv[2]
    if sub == "read":
        sys.exit(cmd_read(path))
    if sub == "write":
        if len(sys.argv) != 4:
            sys.exit(1)
        sys.exit(cmd_write(path, sys.argv[3]))
    sys.exit(1)


if __name__ == "__main__":
    main()
