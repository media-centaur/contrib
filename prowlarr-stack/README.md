# Prowlarr Stack

A starting template for the acquisition stack Media Centarr integrates with — **Prowlarr** (indexer aggregator) + **qBittorrent** (download client) + **FlareSolverr** (Cloudflare bypass), wired together and ready to hand off to Media Centarr.

This is an **opinionated starting point**, not a product. You're expected to fork it: adjust paths, swap services, add a VPN, drop services you don't want. The defaults work as a minimal LAN-only setup.

## Architecture

```
┌────────────┐       ┌──────────────┐       ┌──────────────┐
│ Prowlarr   │──────▶│ qBittorrent  │──────▶│ MEDIA_ROOT/  │
│ (search +  │ grab  │ (download)   │ save  │ downloads/   │
│  indexers) │       │              │       │ complete/    │
└────┬───────┘       └──────────────┘       └──────────────┘
     │                                              │
     │                                              │ Media Centarr
     ▼                                              ▼ Watcher picks up
┌────────────┐                              ┌──────────────┐
│ Flare-     │                              │ MEDIA_ROOT/  │
│ Solverr    │                              │ media/       │
│ (CF bypass)│                              │ Movies/ TV/  │
└────────────┘                              └──────────────┘
```

Media Centarr itself runs on the host (native, systemd) and talks to Prowlarr via API for search / grab, and to qBittorrent via API for live queue status.

## Quick start

```bash
# 1. Copy this directory wherever you want it
cp -r prowlarr-stack ~/prowlarr-stack
cd ~/prowlarr-stack

# 2. Create .env from the template and edit as needed
cp .env.example .env
$EDITOR .env

# 3. Bring the stack up
docker compose up -d

# 4. Auto-integrate with Media Centarr
./scripts/link
```

The `link` script waits for the stack to be healthy, sets qBittorrent's password to a known default (`mediacentarr`), registers qBittorrent as a download client inside Prowlarr, and prints a copy-paste block of values for Media Centarr's Settings page.

## Directory layout

With the default `MEDIA_ROOT=./data`, the stack lays out:

```
data/
  media/
    Movies/       ← add to Media Centarr's watch_dirs
    TV/           ← add to Media Centarr's watch_dirs
  downloads/
    complete/     ← qBittorrent save path (optional watch dir)
    incomplete/   ← in-progress downloads (do not watch)
```

For a real setup, point `MEDIA_ROOT` at your actual library root:

```
MEDIA_ROOT=/mnt/media
```

**The critical integration point:** qBittorrent's completion path must land somewhere Media Centarr is watching. Either put qBittorrent's save path *inside* a watch dir (e.g. `complete/Movies/` under a watched `data/downloads/complete/`), or watch your media dirs and have qBittorrent move completed files there via a category save path.

## Configure Prowlarr

Open `http://localhost:9696` in a browser.

1. **Set an admin password** — first-run prompt.
2. **Add a FlareSolverr proxy** — *Settings → Indexers → Indexer Proxies → Add → FlareSolverr*, host `http://flaresolverr:8191`. Required for Cloudflare-fronted trackers.
3. **Add indexers** — *Indexers → Add Indexer*. Public trackers (1337x, TorrentGalaxy, etc.) work without credentials. Private trackers need your account details.
4. **Configure qBittorrent category save paths** — open qBittorrent (`http://localhost:8080`, login `admin` / `mediacentarr`), go to *Options → Downloads*, and set "Default Save Path" or per-category paths that land inside a Media Centarr watch directory.

The `link` script has already done the Prowlarr ⇄ qBittorrent wiring for you; you don't need to touch *Settings → Apps* or *Settings → Download Clients* manually.

## VPN

This stack uses **host networking for outbound traffic** — docker containers inherit your host's routing. If you want torrent traffic to go through a VPN:

1. Start your host-level VPN (WireGuard, NordVPN CLI, etc.) **before** `docker compose up -d`.
2. Containers route via the tunnel automatically.
3. When the VPN drops, there is **no kill-switch** — traffic falls back to your ISP's connection. Watch for this.

For a kill-switched container-level VPN, look at [gluetun](https://github.com/qdm12/gluetun). The pattern is to run qBittorrent with `network_mode: "service:gluetun"` and expose ports from the gluetun container. Left out of this template to keep the defaults minimal; add it yourself if you need it.

## Run as a service

An example systemd user unit lives in [`extras/systemd/prowlarr-stack.service.example`](extras/systemd/prowlarr-stack.service.example). Install per the comments at the top of that file to have the stack come up automatically on login.

## Re-running `./scripts/link`

Safe. The script is idempotent — it detects already-linked state and skips work that's already done. If the qBittorrent password is already `mediacentarr` it won't try to reset it; if a qBittorrent download client is already registered in Prowlarr it won't add a duplicate.

## Troubleshooting

- **`docker compose ps` shows a service unhealthy** — check container logs: `docker logs prowlarr` / `qbittorrent` / `flaresolverr`.
- **`./scripts/link` fails with "could not find qBittorrent temp password"** — qBittorrent's temp password has already been consumed (from a prior manual login) but the default wasn't set. Reset: `docker compose down && rm -rf config/qbittorrent && docker compose up -d && ./scripts/link`.
- **`./scripts/link` fails with "config.xml not found"** — Prowlarr hasn't completed its first-run setup yet. Wait ~15s and re-run.
- **Media Centarr says "connection refused" for Prowlarr or qBittorrent** — the Media Centarr process can't reach the host port. If Media Centarr runs in its own container or on a different host, adjust the URLs to use the Docker host IP instead of `localhost`.
- **Downloads complete but don't appear in Media Centarr** — qBittorrent's save path isn't inside a watch directory. Fix it in qBittorrent's *Options → Downloads*.

## Starting over

```bash
docker compose down            # stop containers, keep config
docker compose down -v         # stop and remove named volumes (none by default)
rm -rf config/ data/           # wipe all state
```
