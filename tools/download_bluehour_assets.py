#!/usr/bin/env python3
"""Fetch CC0 props for the Blue Hour cliffside map from Poly Pizza.

Poly Pizza serves each model's real file from static.poly.pizza/<uuid>.glb, but
the short /m/<id> page hides it behind JS. This resolves the page -> CDN glb and
downloads it, and prints provenance (author + license) so it can be recorded in
NOTICES.md. All models chosen here are by Kenney or Quaternius (CC0).

Usage:  python3 tools/download_bluehour_assets.py
Output: assets/maps/bluehour/<name>.glb
"""
import os
import re
import sys
import urllib.request

DEST = os.path.join(os.path.dirname(__file__), "..", "assets", "maps", "bluehour")

# name -> Poly Pizza short id.  All Kenney / Quaternius => CC0.
MODELS = {
    "house_a":  "7VSVwAg2T3",   # House          — Kenney
    "house_b":  "BH2XHWUNmF",   # Fantasy House  — Quaternius
    "rocks_a":  "OQvi8PIZ40",   # Rocks          — Quaternius
    "rock_big": "54jZKTAt5p",   # Rock Large     — Quaternius
    "rock_fmt": "pRY9BCFbmQ",   # Rock Formation — Kenney
    "rock_flat":"CrSoV13mCU",   # Rock Flat      — Kenney
    "boat":     "Bkd4KKQA4O",   # Lifeboat       — Quaternius
}

UA = {"User-Agent": "Mozilla/5.0 (bluehour asset fetch)"}


def fetch(url: str) -> bytes:
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read()


def resolve_glb(short_id: str):
    """Return (glb_url, author, license_str) for a Poly Pizza short id."""
    html = fetch(f"https://poly.pizza/m/{short_id}").decode("utf-8", "ignore")
    m = re.search(r"https://static\.poly\.pizza/[0-9a-f-]+\.glb", html)
    if not m:
        return None, "?", "?"
    author = "?"
    am = re.search(r"[Bb]y\s+([A-Za-z0-9 _.-]{2,30})", html)
    if am:
        author = am.group(1).strip()
    lic = "CC0" if ("Creative Commons Zero" in html or "CC0" in html) else "CC-BY"
    return m.group(0), author, lic


def main() -> int:
    os.makedirs(DEST, exist_ok=True)
    ok = 0
    print("model         author         license   file")
    for name, sid in MODELS.items():
        try:
            url, author, lic = resolve_glb(sid)
            if not url:
                print(f"  ! {name}: could not resolve glb for id {sid}")
                continue
            data = fetch(url)
            if data[:4] != b"glTF":
                print(f"  ! {name}: not a glTF ({url})")
                continue
            out = os.path.join(DEST, f"{name}.glb")
            with open(out, "wb") as f:
                f.write(data)
            ok += 1
            print(f"  {name:<12} {author:<14} {lic:<9} {os.path.basename(out)} ({len(data)//1024}kb)")
        except Exception as e:
            print(f"  ! {name}: {e}")
    print(f"\n{ok}/{len(MODELS)} downloaded to {os.path.relpath(DEST)}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
