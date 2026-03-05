# MPV Setup

## Plugins & Scripts

Future enhancements to the MPV playback experience. These are all MPV-side (Lua scripts or C plugins in `~/.config/mpv/scripts/`) and require no backend code changes — our IPC observers pick up any state changes they cause.

- [ ] **OLED screensaver** — [mpv-oled-screensaver](https://github.com/Akemi/mpv-oled-screensaver). Fades to black after 15s when paused in fullscreen. Prevents OLED burn-in.
- [ ] **Chapter skip** — [chapterskip](https://github.com/po5/chapterskip) or [SmartSkip](https://github.com/Eisa01/mpv-scripts/#smartskip). Auto-skip intros/outros/credits by chapter name. Useful for TV series binging. Requires chapters in media files (MKV chapter metadata).
- [ ] **Refresh rate matching** — [mpv-kscreen-doctor](https://gitlab.com/smaniottonicola/mpv-kscreen-doctor) or similar Wayland-compatible solution. Auto-match display refresh rate to video framerate (24Hz for 24fps film). Eliminates judder.
- [ ] **MPRIS** — [mpv-mpris](https://github.com/hoyon/mpv-mpris). Standard Linux media key support (play/pause/next/prev). MPV state changes from MPRIS flow through our existing IPC property observers, so watch progress tracking remains intact.

### Installed

- **uosc** — Feature-rich proximity-based UI. Installed locally at `~/.config/mpv/scripts/uosc/` (cloned from `tomasklaen/uosc`), fonts in `~/.config/mpv/fonts/`. Requires `osc=no` and `osd-bar=no` in `mpv.conf`. Menu bound to `TAB` (FLIRC USB Gen 2 doesn't support the `menu` key).

## Hardware: Sofabaton X1S + FLIRC USB Gen 2

- FLIRC Gen 2 (FW v4.10.7) does NOT support `interkey_delay` tuning — N/A on v4 firmware.
- Double key presses occurred ONLY inside mpv (especially uosc menus), not in other apps.
- Root cause: mpv's own key auto-repeat, not the remote hardware.
- Fix: `input-ar-delay=1000` in `mpv.conf` (increases auto-repeat delay to 1 second).

### Configurations

- [ ] Don't visualize cache
