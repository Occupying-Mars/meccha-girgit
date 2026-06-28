#!/usr/bin/env bash
# Run a Noray relay so friends can join WITHOUT port-forwarding their routers.
#
# Internet hosting needs a relay that everyone can reach:
#   * Same Wi-Fi / LAN: run this, then put "<this-machine-LAN-IP>:8890" in the
#     game's Relay field. Friends on the same network can join.
#   * Over the internet: run this on a VPS with a public IP (or port-forward
#     8890/tcp, 8809/udp, 49152-51200/udp on your router), then use that
#     public address in the Relay field.
#
# Usage:  ./tools/run_relay.sh
set -euo pipefail

DIR="${NORAY_DIR:-${TMPDIR:-/tmp}/noray-relay}"
if [ ! -d "$DIR/.git" ]; then
  echo "[relay] cloning noray into $DIR ..."
  git clone --depth 1 https://github.com/foxssake/noray.git "$DIR"
fi
cd "$DIR"
[ -f .env ] || cp .env.example .env

if ! command -v pnpm >/dev/null 2>&1; then
  corepack enable pnpm 2>/dev/null || true
fi
echo "[relay] installing deps ..."
pnpm install --silent

LAN_IP="$(ipconfig getifaddr en0 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}' || echo '127.0.0.1')"
echo "============================================================"
echo "  Relay starting on :8890"
echo "  Same-network friends: set in-game Relay field to  ${LAN_IP}:8890"
echo "  (Internet: run on a VPS/public IP, use that address instead.)"
echo "============================================================"
NODE_ENV=production node bin/noray.ts
