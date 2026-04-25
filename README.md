# Media Centarr — Contrib

Supplemental ecosystem material for the [Media Centarr](https://github.com/media-centarr/media-centarr) project — a free, open-source media center for Linux.

This repo is a sibling of the main app repo. It holds configs, scripts, and setup guides for the tools Media Centarr runs *alongside* — mpv, hardware remotes, Hyprland, and other integrations.

## Contents

| Directory | Purpose |
|-----------|---------|
| [`mpv/`](mpv/) | Media Centarr-authored mpv configuration and Lua scripts (copy to `~/.config/mpv/`) |
| [`parser-reference/`](parser-reference/) | Reference material for the filename parser — scene standards, codec tags, streaming service tags |
| [`guides/`](guides/) | User-facing setup walkthroughs — see table below |

The acquisition stack (Prowlarr + qBittorrent + FlareSolverr + VPN gateway) lives in its own repo: [media-centarr/prowlarr-stack](https://github.com/media-centarr/prowlarr-stack). One-liner install, signed releases, VPN isolation, and clean uninstall — see its README for the full flow.

## Guides

| Guide | Description |
|-------|-------------|
| [MPV Setup](guides/mpv-setup.md) | Recommended external mpv plugins (uosc, mpv-mpris) that complement the `mpv/` configs |
| [Hyprland](guides/hyprland.md) | Window rules for Media Centarr + mpv coexistence on Hyprland |
| [FLIRC & Sofabaton](guides/flirc-sofabaton.md) | IR remote receiver pairing and key mapping |
| [Testing](guides/testing.md) | Manual testing and integration verification procedures |

## Related

- **Main app repo:** [`media-centarr/media-centarr`](https://github.com/media-centarr/media-centarr) — the Phoenix application.
- **Protocol specifications** (API, data formats, images, playback) live in the main app repo under `specs/`.
