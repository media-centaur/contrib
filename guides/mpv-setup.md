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

## Audio: taming dynamic range

The classic "I can't hear the dialogue, then the explosion deafens me" problem. Theatrical mixes are mastered with a wide dynamic range for a calibrated cinema; on a stereo home setup that range is punishing. Three independent fixes are set up in [`mpv/mpv.conf`](../mpv/mpv.conf) and [`mpv/input.conf`](../mpv/input.conf), with live toggles in the track menu (see below).

### 1. Authored DRC (default, on)

```ini
ad-lavc-ac3drc=1.0
```

AC3/E-AC3 streams carry a dynamic-range-control curve **written by the film's own sound mixers** (the "night mode" your AV receiver would apply). Applying it is the least destructive option because you're using the filmmakers' own home/night mix, not a guessed compression. `1.0` = full DRC, `0.0` = full theatrical range, `0.5` = a compromise. No effect on tracks that carry no DRC metadata (DTS, PCM, FLAC).

### 2. Night mode — `dynaudnorm`

When the authored DRC isn't enough (or isn't present), toggle FFmpeg's `dynaudnorm`. It rides the gain up in quiet passages and eases off in loud ones over a smoothed window — no hard clipping, no obvious pumping. It's a toggle rather than always-on so default playback stays faithful and you opt in per film. Two ways to flip it, sharing one state:

- Key **`n`** (from `input.conf`) — quick, without opening anything.
- The **Sound** column of the track menu (`TAB`).

```ini
n script-message track-menu-toggle-sound dynaudnorm
```

The filter spec (and its tuning) lives in `scripts/track-menu.lua` (`SPECS.dynaudnorm = "...dynaudnorm=f=500:g=31:p=0.9:m=4:s=0"`): `f` frame ms, `g` Gaussian window (odd), `p` target peak, `m` max gain cap, `s` compression strength.

### 3. Dialogue boost — `dialoguenhance`

When dialogue specifically is buried (often a side effect of a 5.1→stereo downmix folding the **center channel** down too far), toggle FFmpeg's `dialoguenhance`, which lifts the center/dialogue component. mpv auto-inserts the stereo downmix the filter needs, so it works on stereo, 5.1, and 7.1 sources alike. Toggle it from the **Sound** column of the track menu.

### The track menu's "Sound" column

`TAB` opens the track menu; `→` past **Audio** and **Subtitles** reaches **Sound**, holding **Night mode** and **Dialogue boost** as on/off toggles (`enter` flips, `●` marks active). The script owns these filters, so the menu and the `n` key are the *same* toggle — they never disagree.

**Remembered per folder.** Choices are saved to `~/.local/state/mpv/sound-toggles.json`, keyed by the file's folder, and restored automatically on load. Set night mode once for a season folder and every episode inherits it; a film in an unconfigured folder starts clean.

**Auto limiter.** Whenever any sound toggle is on, a transparent true-peak limiter (`alimiter`) is appended **last** in the chain to catch clipping from the boosts, and removed when everything is off. It's automatic — not a menu item, not persisted.

These toggles apply instantly during playback. One caveat: flipping them *while paused* can reset the other sound toggle (mpv can't rebuild the audio filter chain without a live stream) — toggle while playing, which is the normal case since the menu doesn't pause the film.

## Hardware: Sofabaton X1S + FLIRC USB Gen 2

- FLIRC Gen 2 (FW v4.10.7) does **not** support `interkey_delay` tuning (N/A on v4 firmware).
- Double key presses occurred only inside mpv (especially uosc menus), not in other apps.
- Root cause: mpv's own key auto-repeat, not the remote hardware.
- Fix: `input-ar-delay=1000` in `mpv.conf` (increases auto-repeat delay to 1 second).
