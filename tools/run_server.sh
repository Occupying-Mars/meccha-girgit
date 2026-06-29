#!/usr/bin/env bash
# Run the MECCHA GIRGIT dedicated game server (on a VPS / any box with a public
# IP). Everyone — including you — connects OUTBOUND to this box's public IP,
# which works through ANY NAT (symmetric included). No noray, no port-punching.
#
# The server has NO player of its own; the first client to join is the "admin"
# who starts the match. Roles are assigned among the connected players.
#
# Env overrides:  MAP=sponza|backrooms|arena  MODE=random|decided  PREP=45  SEEK=120  GODOT=godot
# Usage:          ./tools/run_server.sh
set -euo pipefail
cd "$(dirname "$0")/.."

MAP="${MAP:-backrooms}"      # backrooms/arena need no downloaded assets; sponza does
MODE="${MODE:-random}"
PREP="${PREP:-45}"
SEEK="${SEEK:-120}"
GODOT="${GODOT:-godot}"

if [ "$MAP" = "sponza" ] && [ ! -f assets/arenas/sponza/Sponza.gltf ]; then
  echo "[server] map=sponza but the Sponza assets aren't here — fetching..."
  python3 tools/download_sponza.py || { echo "fetch failed; falling back to backrooms"; MAP=backrooms; }
fi

echo "[server] importing assets (first run only)…"
"$GODOT" --headless --import >/dev/null 2>&1 || true

echo "============================================================"
echo "  MECCHA GIRGIT dedicated server"
echo "  UDP port 24565  |  map=$MAP  mode=$MODE  prep=${PREP}s seek=${SEEK}s"
echo "  Players: in the menu, DON'T tick 'online', paste this box's"
echo "           PUBLIC IP into the JOIN field, and Join."
echo "  Open UDP 24565 in the firewall/security-group."
echo "============================================================"
exec "$GODOT" --headless --path . scenes/game/net_game.tscn -- \
  --dedicated --map="$MAP" --mode="$MODE" --prep="$PREP" --seek="$SEEK"
