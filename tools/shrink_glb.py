#!/usr/bin/env python3
"""Allège un .glb : ses images PNG opaques (sans alpha) sont ré-encodées en JPEG (qualité 92).
Les images avec alpha (feuilles) restent en PNG. Usage : python3 tools/shrink_glb.py fichier.glb
Nécessite Pillow. Le fichier est réécrit en place (sauvegarde .orig à côté)."""
import io
import json
import os
import struct
import sys

from PIL import Image


def shrink(path):
    with open(path, "rb") as f:
        data = f.read()
    magic, version, length = struct.unpack("<III", data[:12])
    assert magic == 0x46546C67, "pas un glb"
    clen, ctype = struct.unpack("<II", data[12:20])
    doc = json.loads(data[20:20 + clen])
    blen, btype = struct.unpack("<II", data[20 + clen:28 + clen])
    binv = bytearray(data[28 + clen:28 + clen + blen])
    views = doc["bufferViews"]
    # Nouveau tampon : on recopie chaque bufferView (les images changées sont ré-encodées).
    out = bytearray()
    image_views = {im["bufferView"]: i for i, im in enumerate(doc.get("images", [])) if "bufferView" in im}
    saved = 0
    for vi, bv in enumerate(views):
        off = bv.get("byteOffset", 0)
        ln = bv["byteLength"]
        chunk = bytes(binv[off:off + ln])
        if vi in image_views:
            im = doc["images"][image_views[vi]]
            img = Image.open(io.BytesIO(chunk))
            if img.mode in ("RGB", "L") or (img.mode == "RGBA" and img.getextrema()[3][0] == 255):
                buf = io.BytesIO()
                img.convert("RGB").save(buf, "JPEG", quality=92, optimize=True)
                if buf.tell() < len(chunk):
                    saved += len(chunk) - buf.tell()
                    chunk = buf.getvalue()
                    im["mimeType"] = "image/jpeg"
        while len(out) % 4:
            out.append(0)
        bv["byteOffset"] = len(out)
        bv["byteLength"] = len(chunk)
        out += chunk
    while len(out) % 4:
        out.append(0)
    doc["buffers"][0]["byteLength"] = len(out)
    jbytes = json.dumps(doc, separators=(",", ":")).encode("utf-8")
    while len(jbytes) % 4:
        jbytes += b" "
    total = 12 + 8 + len(jbytes) + 8 + len(out)
    os.replace(path, path + ".orig")
    with open(path, "wb") as f:
        f.write(struct.pack("<III", magic, version, total))
        f.write(struct.pack("<II", len(jbytes), 0x4E4F534A))
        f.write(jbytes)
        f.write(struct.pack("<II", len(out), 0x004E4942))
        f.write(out)
    print("%s : %.1f Mo -> %.1f Mo (%.1f Mo d'images ré-encodées)" % (path, len(data) / 1e6, total / 1e6, saved / 1e6))


if __name__ == "__main__":
    for p in sys.argv[1:]:
        shrink(p)
