#!/usr/bin/env python3
"""Télécharge les ressources Poly Haven (CC0) listées dans assets/manifest.json.

Utilisation : python3 tools/fetch_polyhaven.py [--res 1k] [--force]
Sans dépendance : bibliothèque standard seulement. Les fichiers déjà présents et intacts (md5)
sont sautés. Sortie : assets/polyhaven/models/<slug>/ et assets/polyhaven/textures/<slug>/.
"""
import argparse
import hashlib
import json
import os
import sys
import urllib.request

API = "https://api.polyhaven.com/files/"
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = os.path.join(ROOT, "assets", "polyhaven")


def fetch_json(url):
    req = urllib.request.Request(url, headers={"User-Agent": "alize-asset-fetcher"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)


def md5_of(path):
    h = hashlib.md5()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def download(url, dest, md5=None, force=False):
    if os.path.exists(dest) and not force:
        if md5 is None or md5_of(dest) == md5:
            return False
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    req = urllib.request.Request(url, headers={"User-Agent": "alize-asset-fetcher"})
    with urllib.request.urlopen(req, timeout=300) as r, open(dest + ".part", "wb") as f:
        while True:
            chunk = r.read(1 << 20)
            if not chunk:
                break
            f.write(chunk)
    os.replace(dest + ".part", dest)
    if md5 and md5_of(dest) != md5:
        raise RuntimeError("md5 incorrect pour %s" % dest)
    return True


def fetch_model(slug, res, force):
    files = fetch_json(API + slug)
    by_res = files["gltf"]
    if res not in by_res:
        res = sorted(by_res.keys(), key=lambda k: int(k.rstrip("k")))[0]
        print("  (résolution indisponible, on prend %s)" % res)
    entry = by_res[res]["gltf"]
    folder = os.path.join(OUT, "models", slug)
    n = 0
    n += download(entry["url"], os.path.join(folder, os.path.basename(entry["url"])), entry.get("md5"), force)
    for rel, info in entry.get("include", {}).items():
        n += download(info["url"], os.path.join(folder, rel), info.get("md5"), force)
    return n


def fetch_texture(slug, res, maps, force):
    files = fetch_json(API + slug)
    folder = os.path.join(OUT, "textures", slug)
    n = 0
    for m in maps:
        if m not in files:
            print("  (pas de carte %s pour %s)" % (m, slug))
            continue
        by_res = files[m]
        r = res if res in by_res else sorted(by_res.keys(), key=lambda k: int(k.rstrip("k")))[0]
        variants = by_res[r]
        fmt = "jpg" if "jpg" in variants else ("png" if "png" in variants else next(iter(variants)))
        info = variants[fmt]
        n += download(info["url"], os.path.join(folder, "%s_%s_%s.%s" % (slug, m, r, fmt)), info.get("md5"), force)
    return n


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--force", action="store_true")
    args = ap.parse_args()
    with open(os.path.join(ROOT, "assets", "manifest.json"), encoding="utf-8") as f:
        manifest = json.load(f)
    total = 0
    for slug, opts in manifest.get("models", {}).items():
        print("modèle", slug)
        total += fetch_model(slug, opts.get("res", "1k"), args.force)
    for slug, opts in manifest.get("textures", {}).items():
        print("texture", slug)
        total += fetch_texture(slug, opts.get("res", "1k"), opts.get("maps", ["Diffuse", "nor_gl", "Rough", "AO"]), args.force)
    print("%d fichier(s) téléchargé(s)." % total)
    return 0


if __name__ == "__main__":
    sys.exit(main())
