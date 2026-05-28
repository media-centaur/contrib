# Media Centaur — Contrib

Supplemental ecosystem material for the [Media Centaur](https://github.com/media-centaur/media-centaur) project — a free, open-source media center for Linux.

This repo is a sibling of the main app repo. It holds configs, scripts, and setup guides for the tools Media Centaur runs *alongside* — mpv, hardware remotes, Hyprland, and other integrations.

## Contents

| Directory | Purpose |
|-----------|---------|
| [`mpv/`](mpv/) | Media Centaur-authored mpv configuration and Lua scripts (copy to `~/.config/mpv/`) |
| [`parser-reference/`](parser-reference/) | Reference material for the filename parser — scene standards, codec tags, streaming service tags |
| [`guides/`](guides/) | User-facing setup walkthroughs — see table below |

The acquisition stack (Prowlarr + qBittorrent + FlareSolverr + VPN gateway) lives in its own repo: [media-centaur/prowlarr-stack](https://github.com/media-centaur/prowlarr-stack). One-liner install, signed releases, VPN isolation, and clean uninstall — see its README for the full flow.

## Guides

| Guide | Description |
|-------|-------------|
| [MPV Setup](guides/mpv-setup.md) | Recommended external mpv plugins (uosc, mpv-mpris) that complement the `mpv/` configs |
| [Hyprland](guides/hyprland.md) | Window rules for Media Centaur + mpv coexistence on Hyprland |
| [FLIRC & Sofabaton](guides/flirc-sofabaton.md) | IR remote receiver pairing and key mapping |
| [Testing](guides/testing.md) | Manual testing and integration verification procedures |

## Related

- **Main app repo:** [`media-centaur/media-centaur`](https://github.com/media-centaur/media-centaur) — the Phoenix application.
- **Protocol specifications** (API, data formats, images, playback) live in the main app repo under `specs/`.
