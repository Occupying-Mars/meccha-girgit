# Hosting a relay on a VPS (internet play)

To play with friends in **different houses**, you need a **Noray relay** running
somewhere with a **public IP** — a small cloud server (VPS). The relay does
NAT-punchthrough so nobody has to port-forward their router. Once it's up,
everyone points the in-game **Relay** field at it.

> You only need ONE relay for your whole friend group, and one tiny box runs it.
> Same Wi-Fi? You don't need any of this — just HOST and share the invite code.

---

## 1. Get a VPS

Any Linux box with a public IP works. Cheapest/free options:

| Provider | Cost | Notes |
|---|---|---|
| **Oracle Cloud — Always Free** | $0 forever | 1 free Arm VM, real public IP. Best free pick. |
| **Google Cloud free tier** | $0 (e2-micro) | US regions only on the free tier. |
| **Hetzner / DigitalOcean / Vultr** | ~$4–5/mo | Simple, reliable, instant. |

Pick **Ubuntu 22.04+** (or any distro with Docker). Note the VM's **public IP**.

---

## 2. Open the firewall ports

Noray needs these open to the internet (both the cloud provider's firewall/
security-group **and** the VM's own firewall, e.g. `ufw`):

| Port | Proto | Purpose |
|---|---|---|
| `8890` | TCP | clients register + request connections |
| `8809` | UDP | remote-port registrar |
| `49152–51200` | UDP | relay data (when NAT-punch fails) |
| `8891` | TCP | metrics (optional) |

Example with `ufw` on the VM:

```bash
sudo ufw allow 8890/tcp
sudo ufw allow 8809/udp
sudo ufw allow 49152:51200/udp
```

In the cloud console, add the same to the instance's **security group / firewall
rules** (this step is the one people forget).

---

## 3. Run Noray

### Option A — Docker (easiest)

```bash
# install docker if needed: curl -fsSL https://get.docker.com | sh
docker run -d --restart unless-stopped --name noray \
  -p 8890:8890 \
  -p 8809:8809/udp \
  -p 49152-51200:49152-51200/udp \
  ghcr.io/foxssake/noray:main
```

That's it — it's now listening on your VPS's public IP, port 8890.

> Tip: a big relay-port range slows container start. To use fewer ports, pass
> `-e NORAY_UDP_RELAY_PORTS=49152-49200` and forward only `49152-49200/udp`.

### Option B — Node.js (no Docker)

```bash
sudo apt update && sudo apt install -y git nodejs npm
sudo corepack enable pnpm
git clone https://github.com/foxssake/noray.git && cd noray
cp .env.example .env
pnpm install
NODE_ENV=production node bin/noray.ts
```

(For a long-running server, wrap it in `tmux`/`systemd` so it survives logout.)

---

## 4. Verify it's reachable

From your own machine:

```bash
nc -vz YOUR_VPS_IP 8890     # should say "succeeded" / "open"
```

If it hangs/refuses: the port isn't open — re-check the cloud firewall AND the
VM firewall.

---

## 5. Play

In **MECCHA GIRGIT**, for everyone (host + friends):

1. Tick **Play over internet (relay)**.
2. In the **Relay** field, enter `YOUR_VPS_IP:8890`.
3. **Host** → copy the **invite code** (the OID) and send it to friends.
4. Friends: same relay address + the invite code → **JOIN**.

All gameplay then flows through the relay exactly like a LAN game — no router
config on anyone's end.

---

## Troubleshooting

- **Friends can't connect, host is fine:** the cloud **security group** almost
  certainly still blocks the UDP ports (8809 + the relay range). Open them.
- **"Could not host (Timeout)":** the game can't reach `:8890` — wrong IP, relay
  not running, or 8890/tcp closed.
- **Connects then drops:** open the UDP relay range (`49152–51200/udp`); some
  NATs force the relay fallback which needs those.
- **Costs:** Noray relays only when NAT-punch fails; most traffic is P2P, so a
  tiny VM is plenty for a normal lobby.

The public test relay (`tomfol.io:8890`) is unreliable and often down — don't
depend on it; run your own with the steps above.
