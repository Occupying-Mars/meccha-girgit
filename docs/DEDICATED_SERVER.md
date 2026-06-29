# Dedicated server (the symmetric-NAT fix)

If a player's ISP uses **symmetric NAT** (common on Indian broadband; every
outbound destination gets a different public port), **NAT-punch and the noray
relay both fail** for them — they reach the relay but get nothing back. No
firewall toggle fixes it; it's the NAT itself.

**The fix:** run the *game server itself* on a box with a public IP (a VPS).
Then nobody hosts from home — **everyone connects OUTBOUND** to the server's
public IP. Outbound connections to a public IP work through *any* NAT, because
the server replies from the exact address you contacted.

```
You (symmetric NAT) ─┐
Friend (cone NAT)    ─┼── outbound to PUBLIC_IP:24565 ──►  VPS runs the game server
Friend (whatever)    ─┘                                    (no player of its own)
```

The server has **no player**; the **first client to join is the admin** who
starts the match. Roles (seeker/hiders) are assigned among the connected
players.

---

## 1. Set up the VPS (one time)

Any cheap/free Linux box with a public IP (Oracle Always-Free, a $5 droplet…).

```bash
# install Godot 4.6 headless (Linux)
wget https://github.com/godotengine/godot/releases/download/4.6.2-stable/Godot_v4.6.2-stable_linux.x86_64.zip
unzip Godot_v4.6.2-stable_linux.x86_64.zip
sudo mv Godot_v4.6.2-stable_linux.x86_64 /usr/local/bin/godot
sudo apt install -y git python3   # python3 only needed if you want the Sponza map

# get the game
git clone git@github.com:Occupying-Mars/mecca-girgit.git
cd mecca-girgit
```

**Open the port** (this is the step people forget) — UDP **24565** in the VM's
firewall AND the cloud provider's security group:
```bash
sudo ufw allow 24565/udp
```

## 2. Run the server

```bash
./tools/run_server.sh                       # default: backrooms map, random seeker
MAP=sponza MODE=random ./tools/run_server.sh # other options
```
It prints the port and keeps running. Leave it up (use `tmux`/`screen`/systemd
so it survives logout). `backrooms` and `arena` need no asset download; `sponza`
auto-fetches its textures.

## 3. Everyone joins (no NAT issues)

In the game menu, each player:
1. Sets a name.
2. **Leaves "Play over internet (relay)" UNCHECKED.**
3. Pastes the **server's public IP** into the **JOIN** field (e.g. `203.0.113.5`,
   or `203.0.113.5:24565`).
4. Hits **JOIN**.

Everyone lands in the lobby. The **first to join** sees **START MATCH**; they
press it and the round begins. That's it — works for symmetric-NAT players too.

---

### Notes
- The LAN/invite-code and noray/relay paths still work for groups where they're
  fine; this dedicated server is the bulletproof option for symmetric NAT.
- 6–12 players is trivial load — a 1 GB VM with tons of headroom (the server
  renders nothing and the game is slow-paced; bandwidth is tens of KB/s).
- Default map is `backrooms` so the server needs no downloaded assets.
