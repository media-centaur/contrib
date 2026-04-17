# mpv Configuration

Media Centarr-authored mpv configuration and Lua scripts. These are the app's **source of truth** — mpv reads them from `~/.config/mpv/` at runtime, so you install by copying:

```bash
cp mpv.conf ~/.config/mpv/mpv.conf
cp input.conf ~/.config/mpv/input.conf
cp -r scripts/ ~/.config/mpv/scripts/
```

After editing any file here, re-copy the changed ones to your runtime config. There is no automatic sync.

## Files

| File | Purpose |
|------|---------|
| [`mpv.conf`](mpv.conf) | Player settings — Vulkan rendering, subtitle/audio language, OSD |
| [`input.conf`](input.conf) | Key bindings (section-commented, one concern per block) |
| [`scripts/track-menu.lua`](scripts/track-menu.lua) | Two-column audio/subtitle track selector overlay |
| [`scripts/skip-intro.lua`](scripts/skip-intro.lua) | Chapter-based intro skip button |

## Related guides

- [`../guides/mpv-setup.md`](../guides/mpv-setup.md) — recommended **external** mpv plugins (uosc, mpv-mpris) that complement these app-authored configs.
- [`../guides/flirc-sofabaton.md`](../guides/flirc-sofabaton.md) — IR remote setup; the `input-ar-delay` tuning in `mpv.conf` is tied to this.

## Contributor notes

Internal docs live in the main app repo:

- [`media-centarr/docs/mpv.md`](https://github.com/media-centarr/media-centarr/blob/main/docs/mpv.md) — user-facing + implementation details for each script.
- [`media-centarr/.claude/skills/mpv-extensions/SKILL.md`](https://github.com/media-centarr/media-centarr/blob/main/.claude/skills/mpv-extensions/SKILL.md) — conventions for authoring new scripts.
