# MPV Setup

## Recommended Plugins & Scripts

MPV-side enhancements (Lua scripts or C plugins in `~/.config/mpv/scripts/`). These require no backend changes — the IPC observers pick up any state changes they cause.

| Plugin | Purpose |
|--------|---------|
| [mpv-oled-screensaver](https://github.com/Akemi/mpv-oled-screensaver) | Fades to black after 15s when paused in fullscreen. Prevents OLED burn-in. |
| [chapterskip](https://github.com/po5/chapterskip) / [SmartSkip](https://github.com/Eisa01/mpv-scripts/#smartskip) | Auto-skip intros/outros/credits by chapter name. Requires MKV chapter metadata. |
| [mpv-kscreen-doctor](https://gitlab.com/smaniottonicola/mpv-kscreen-doctor) | Auto-match display refresh rate to video framerate (24Hz for 24fps). Eliminates judder. Wayland-compatible. |
| [mpv-mpris](https://github.com/hoyon/mpv-mpris) | Standard Linux media key support (play/pause/next/prev). State changes flow through existing IPC property observers. |

### uosc

[uosc](https://github.com/tomasklaen/uosc) — feature-rich proximity-based UI replacement.

**Install:** Clone to `~/.config/mpv/scripts/uosc/`, copy fonts to `~/.config/mpv/fonts/`.

**Required `mpv.conf` settings:**
```ini
osc=no
osd-bar=no
```

Menu is bound to `TAB` (FLIRC USB Gen 2 doesn't support the `menu` key).

## Hardware: Sofabaton X1S + FLIRC USB Gen 2

- FLIRC Gen 2 (FW v4.10.7) does **not** support `interkey_delay` tuning (N/A on v4 firmware).
- Double key presses occurred only inside mpv (especially uosc menus), not in other apps.
- Root cause: mpv's own key auto-repeat, not the remote hardware.
- Fix: `input-ar-delay=1000` in `mpv.conf` (increases auto-repeat delay to 1 second).
