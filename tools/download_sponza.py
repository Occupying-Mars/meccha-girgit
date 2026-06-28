#!/usr/bin/env python3
"""Fetch the Khronos Sponza sample map (CC-BY) into assets/arenas/sponza/.

Sponza is the real test map for camouflage / wall-stick / sightline testing.
It is NOT committed (50MB of third-party textures) — run this once after a
fresh clone, then open the project so Godot imports it.

    python3 tools/download_sponza.py
"""
import json
import os
import urllib.request
import concurrent.futures

API = ("https://api.github.com/repos/KhronosGroup/glTF-Sample-Assets"
       "/contents/Models/Sponza/glTF")
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "arenas", "sponza")


def fetch(item):
    name, url = item
    dest = os.path.join(OUT, name)
    try:
        urllib.request.urlretrieve(url, dest)
        size = os.path.getsize(dest)
        # Some blobs occasionally come back as a tiny error page; retry via raw.
        if size < 100:
            raw = ("https://raw.githubusercontent.com/KhronosGroup/"
                   "glTF-Sample-Assets/main/Models/Sponza/glTF/" + name)
            urllib.request.urlretrieve(raw, dest)
            size = os.path.getsize(dest)
        return name, size
    except Exception as exc:  # noqa: BLE001
        return name, "ERR " + str(exc)


def main():
    os.makedirs(OUT, exist_ok=True)
    data = json.load(urllib.request.urlopen(API))
    items = [(d["name"], d["download_url"]) for d in data if d.get("download_url")]
    print(f"fetching {len(items)} Sponza files -> {os.path.normpath(OUT)}")
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as ex:
        results = list(ex.map(fetch, items))
    bad = [r for r in results if isinstance(r[1], str) or r[1] < 100]
    if bad:
        print("WARNING: some files failed/are tiny:")
        for n, s in bad:
            print("  ", n, s)
    print("done. Open the project (or `godot --headless --import`) to import.")


if __name__ == "__main__":
    main()
