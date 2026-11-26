# Helpers for scripts/tests/test_dmg_*.zsh, run as: /usr/bin/python3 -I scripts/tests/dmg_inspect.py <command> ...
#   png-pixel <file.png> <x> <y>   the pixel as RRGGBB (8-bit, non-interlaced PNG, no dependencies)
#   tiff-pages <file.tiff>         one "<width>x<height>" line per image in the TIFF
#   contrast <RRGGBB>              the WCAG contrast ratio against white and against black, as "<white> <black>"
#   dsstore <mounted-volume>       the Finder layout in the volume's .DS_Store, as sorted "key=value" lines
import os
import struct
import sys
import zlib

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "dmg", "vendor"))


def png_pixel(path, x, y):
    data = open(path, "rb").read()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", "not a PNG"
    pos, idat, width, height, depth, ctype, interlace = 8, b"", 0, 0, 0, 0, 0
    while pos < len(data):
        (length,) = struct.unpack(">I", data[pos : pos + 4])
        kind = data[pos + 4 : pos + 8]
        body = data[pos + 8 : pos + 8 + length]
        if kind == b"IHDR":
            width, height, depth, ctype, _, _, interlace = struct.unpack(">IIBBBBB", body)
        elif kind == b"IDAT":
            idat += body
        pos += 12 + length
    assert depth == 8 and ctype in (2, 6) and interlace == 0, "only 8-bit RGB/RGBA, not interlaced"
    bpp = 3 if ctype == 2 else 4
    raw = zlib.decompress(idat)
    stride = width * bpp
    prev = bytearray(stride)
    for row in range(y + 1):
        start = row * (stride + 1)
        ftype = raw[start]
        line = bytearray(raw[start + 1 : start + 1 + stride])
        for i in range(stride):
            a = line[i - bpp] if i >= bpp else 0
            b = prev[i]
            c = prev[i - bpp] if i >= bpp else 0
            if ftype == 1:
                line[i] = (line[i] + a) & 255
            elif ftype == 2:
                line[i] = (line[i] + b) & 255
            elif ftype == 3:
                line[i] = (line[i] + (a + b) // 2) & 255
            elif ftype == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pred = a if pa <= pb and pa <= pc else (b if pb <= pc else c)
                line[i] = (line[i] + pred) & 255
        prev = line
    r, g, b = prev[x * bpp : x * bpp + 3]
    return "%02X%02X%02X" % (r, g, b)


def tiff_pages(path):
    data = open(path, "rb").read()
    endian = "<" if data[:2] == b"II" else ">"
    assert data[:2] in (b"II", b"MM") and struct.unpack(endian + "H", data[2:4])[0] == 42, "not a TIFF"
    (offset,) = struct.unpack(endian + "I", data[4:8])
    pages = []
    while offset:
        (count,) = struct.unpack(endian + "H", data[offset : offset + 2])
        size = {}
        for i in range(count):
            tag, ftype, n, value = struct.unpack(endian + "HHI4s", data[offset + 2 + i * 12 : offset + 14 + i * 12])
            if tag in (256, 257):
                size[tag] = struct.unpack(endian + ("H" if ftype == 3 else "I"), value[: 2 if ftype == 3 else 4])[0]
        pages.append("%dx%d" % (size[256], size[257]))
        (offset,) = struct.unpack(endian + "I", data[offset + 2 + count * 12 : offset + 6 + count * 12])
    return pages


def luminance(hexcolor):
    def channel(v):
        v /= 255
        return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4

    r, g, b = (int(hexcolor[i : i + 2], 16) for i in (0, 2, 4))
    return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)


def dsstore(volume):
    from ds_store import DSStore

    lines = []
    with DSStore.open(os.path.join(volume, ".DS_Store"), "r") as store:
        for entry in store:
            code = entry.code.decode()
            if code == "Iloc":
                lines.append("icon.%s=%d,%d" % (entry.filename, entry.value[0], entry.value[1]))
            elif code == "icvp":
                value = entry.value
                lines.append("iconSize=%d" % value["iconSize"])
                lines.append("textSize=%d" % value["textSize"])
                lines.append("backgroundType=%d" % value["backgroundType"])
                lines.append("hasBackgroundAlias=%d" % (1 if value.get("backgroundImageAlias") else 0))
                lines.append("labelOnBottom=%d" % (1 if value.get("labelOnBottom", True) else 0))
            elif code == "bwsp":
                value = entry.value
                for key in ("ShowToolbar", "ShowSidebar", "ShowStatusBar", "ShowPathbar", "ContainerShowSidebar"):
                    if key in value:
                        lines.append("%s=%d" % (key, 1 if value[key] else 0))
                lines.append("WindowBounds=%s" % value["WindowBounds"])
            elif code == "pBBk":
                lines.append("hasBackgroundBookmark=1")
            elif code == "icvl":
                value = entry.value
                lines.append("view=%s" % (value.decode() if isinstance(value, bytes) else value))
    return sorted(lines)


if __name__ == "__main__":
    cmd, args = sys.argv[1], sys.argv[2:]
    if cmd == "png-pixel":
        print(png_pixel(args[0], int(args[1]), int(args[2])))
    elif cmd == "tiff-pages":
        print("\n".join(tiff_pages(args[0])))
    elif cmd == "contrast":
        lum = luminance(args[0])
        print("%.3f %.3f" % (1.05 / (lum + 0.05), (lum + 0.05) / 0.05))
    elif cmd == "dsstore":
        print("\n".join(dsstore(args[0])))
    else:
        sys.exit("unknown command " + cmd)
