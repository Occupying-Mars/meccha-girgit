# Third-Party Notices

Girgit's own code is under the [MIT License](LICENSE). It also bundles the
third-party components listed below, each of which is governed by its **own**
license. Nothing here is owned by the Girgit project.

If you add third-party code or assets, record them here and confirm their
license permits redistribution.

---

## Code / engine plugins

### netfox / netfox.internals / netfox.noray
- **Path:** `addons/netfox.internals/`, `addons/netfox.noray/`
- **Author:** Gálffy Tamás (Tamas Galffy) and contributors — v1.46.2
- **License:** MIT — see `addons/netfox.noray/LICENSE`
- **Upstream:** https://github.com/foxssake/netfox

### gd-eos (Godot EOS GDExtension)
- **Path:** `addons/gd-eos/` (excluding the Epic SDK binaries below)
- **Author:** 忘忧の (Daylily Zeleen), 2024
- **License:** MIT — see `addons/gd-eos/LICENSE`
- **Upstream:** https://github.com/Daylily-Zeleen/godot-eos

### Epic Online Services (EOS) SDK
- **Path:** `addons/gd-eos/bin/**` (e.g. `libEOSSDK-*`, `EOSSDK.framework`,
  `EOSSDK.dll`, and the platform `libgdeos.*` frameworks that link them)
- **Author:** Epic Games, Inc.
- **License:** Proprietary — the **Epic Online Services SDK** terms, *not* MIT.
  Use and redistribution are governed by Epic's developer agreement and the EOS
  SDK license. See https://dev.epicgames.com/en-US/services and the EOS SDK
  license terms.
- **Note:** These binaries are included for convenience so the game builds and
  runs out of the box. If you fork or redistribute, review Epic's terms — you may
  prefer to remove the SDK from your fork and have users fetch it themselves.
  (On macOS the framework carries an added `@loader_path/..` rpath so the loader
  finds the sibling SDK dylib; it is otherwise unmodified.)

---

## Art / assets

### KayKit — Furniture Bits & Dungeon assets
- **Path:** `assets/maps/furniture/`, `assets/maps/kaykit/`
- **Author:** Kay Lousberg — https://www.kaylousberg.com
- **License:** CC0 1.0 (public domain) — see `assets/maps/furniture/LICENSE.txt`
- Crediting Kay Lousberg is appreciated (not required).

### House map surface textures
- **Path:** `assets/maps/house_tex/`
- **Source:** Poly Haven — https://polyhaven.com
- **License:** CC0 1.0 (public domain) — see `assets/maps/house_tex/CREDITS.txt`

### Backrooms textures (alternate map)
- **Path:** `assets/textures/backrooms/`
- **License:** CC0 1.0 (public domain)

### Sponza
- **Path:** `assets/arenas/sponza/` (fetchable via `tools/download_sponza.py`)
- **Source:** Khronos glTF Sample Assets (originally Crytek / Frank Meinl)
- **License:** CC BY 4.0 — attribution required.
  https://github.com/KhronosGroup/glTF-Sample-Assets

### Blue Hour map props (houses, rocks, boat)
- **Path:** `assets/maps/bluehour/` (re-fetchable via `tools/download_bluehour_assets.py`)
- **Authors:** Kenney (kenney.nl) and Quaternius (quaternius.com), via Poly Pizza
- **License:** CC0 1.0 (public domain) — no attribution required; credited here as
  good practice. https://poly.pizza

---

_If any attribution here is incomplete or incorrect, please
[open an issue](https://github.com/Occupying-Mars/mecca-girgit/issues) so we can
fix it._
