#!/usr/bin/env python3
"""生成透明 RGBA 占位 ic_launcher.png，规避本机 AAPT2 9.0.1 对 RGB(无alpha) PNG 的崩溃。

仅影响启动器资源编译；Find N2 (Android 12+) 使用自适应图标 XML，不显示此占位图。
用法：在 WSL 内 python3 tool/fix_launcher_png.py [res目录]
默认 res 目录：/home/actions/app/android/app/src/main/res
"""
import struct
import sys
import zlib
import os


def make_rgba_png(size):
    w = h = size
    raw = b""
    for _ in range(h):
        raw += b"\x00" + b"\x00\x00\x00\x00" * w

    def chunk(typ, data):
        c = typ + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c))

    ihdr = struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", zlib.compress(raw))
        + chunk(b"IEND", b"")
    )


def main():
    res = sys.argv[1] if len(sys.argv) > 1 else "/home/actions/app/android/app/src/main/res"
    for d in ["mipmap-xhdpi", "mipmap-xxhdpi"]:
        p = os.path.join(res, d, "ic_launcher.png")
        with open(p, "wb") as f:
            f.write(make_rgba_png(96))
        print("replaced", p)


if __name__ == "__main__":
    main()