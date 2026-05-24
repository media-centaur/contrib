# 001 — MPV Sound: per-folder persistence + true-peak limiter

## Context (self-contained)

**Repo:** `contrib` — plain git, `main` branch (jujutsu was removed). The mpv configs
in `mpv/` are the canonical source. The **live install** is a *different* repo: the
dotfiles repo, symlinked at `~/.config/mpv` →
`/home/shawn/src/dotfiles/files/home/shawn/.config/mpv`. Deploy by MERGING, not
overwriting — the dotfiles copies carry personal deltas:
- `mpv.conf`: `keepaspect-window=yes`
- `scripts/track-menu.lua`: `bg_alpha="05"` (contrib has `"0A"`) and an extra
  `MBTN_BACK` close binding in `open_menu`.

**Current sound system** (`mpv/scripts/track-menu.lua`): the track menu (`TAB`) has a
third **Sound** column with two toggles, each a labeled audio filter managed via
`af toggle`:
- Night mode: `@dynaudnorm:dynaudnorm=f=500:g=31:p=0.9:m=4:s=0`
- Dialogue boost: `@dialog:dialoguenhance`

On/off state is read live from the `af` chain via `filter_present(label)`. The menu's
`activate()` toggles via `mp.commandv("af","toggle",item.filter)`. Separately,
`mpv/input.conf` binds `n` to `af toggle @dynaudnorm:...` independently. There is an
`af` property observer that re-renders the menu when filters change.

**Verified facts (this session):**
- `alimiter=limit=0.95:level=false` parses in mpv v0.41.0.
- `af remove @<absent-label>` returns success (benign — safe to call unconditionally).
- Rebuild-by-(remove-all-then-add-in-order) yields deterministic chain order
  `[dialog, dynaudnorm, limiter]`.
- Toggling `af` filters works while **playing**; while **paused** mpv drops lavfi-type
  filters on chain reinit. Test with `--pause=no --loop-file=inf`.
- mpv Lua utils: `mp.utils.parse_json` / `format_json`, `split_path`; resolve config
  dir via `mp.command_native({"expand-path","~~/<name>"})`; file IO via Lua `io.open`.

## Goals

1. **Persist** the user's Sound-toggle choices per containing folder; auto-restore on
   file load (a season folder inherits one setting; single-film folders behave per-film).
2. **True-peak limiter**: a transparent `alimiter` that is automatically present
   whenever any sound filter is active, always **last** in the chain, to catch clipping
   introduced by the boosts. Derived/automatic — not a menu item, not persisted.

## Design

### A. Centralized sound-filter manager (refactor)

Make `track-menu.lua` the single owner of the managed sound filters. Rationale: the
limiter must always be last and auto-managed; that ordering cannot be guaranteed when
both the menu and the `n` key issue independent `af toggle` calls.

- Desired-state table: `sound_on = { dynaudnorm=false, dialog=false }`.
- `reconcile()` — rebuild the managed chain deterministically:
  1. `af remove @dialog`, `af remove @dynaudnorm`, `af remove @limiter` (benign if absent)
  2. if `sound_on.dialog`: `af add @dialog:dialoguenhance`
  3. if `sound_on.dynaudnorm`: `af add @dynaudnorm:dynaudnorm=f=500:g=31:p=0.9:m=4:s=0`
  4. if either on: `af add @limiter:alimiter=limit=0.95:level=false`
- `set_sound(label, on)`: set desired, `reconcile()`, `save_state()`, `render()`.
- `toggle_sound(label)`: `set_sound(label, not sound_on[label])`.
- Menu `activate()` for the sound column calls `toggle_sound(item.label)` (replaces the
  current `af toggle`).
- Expose a script-message: `mp.register_script_message("toggle-sound", toggle_sound)`
  → callable as `script-message track-menu/toggle-sound <label>`.
- The two `sound_items` keep `{name,label}`; the `filter`/full-spec moves into
  `reconcile()` (single source of the spec strings). Menu ON/● indicator keeps using
  `filter_present(label)` (still accurate post-reconcile). Keep the `af` observer for
  re-render only (it no longer mutates anything).

**`input.conf` change:** `n af toggle @dynaudnorm:...`  →
`n script-message track-menu/toggle-sound dynaudnorm`. Trade-off: `n` now requires the
script to be loaded (they ship together — acceptable). The `show-text` can be dropped
(the script re-renders the menu state) or kept as a second command.

### B. Per-folder persistence

- Store file: `~/.local/state/mpv/sound-toggles.json` via
  `mp.command_native({"expand-path","~/.local/state/mpv/sound-toggles.json"})` — the XDG
  state dir, NOT `~~/`, to keep runtime state out of the version-controlled dotfiles
  config dir. (mpv's `~~state/` prefix does NOT expand when a filename is appended in
  this build — it collapses to a relative path — so use reliable `~/` expansion.) Lazy
  `mkdir -p` fallback if the write fails.
- Shape: `{ "<dir>": { "dynaudnorm": bool, "dialog": bool } }`.
- Folder key: `path = mp.get_property("path")`; if nil or not a local file (URL /
  `av://` / no directory), **skip persistence** (no-op, no error). Else
  `dir = (mp.utils.split_path(path))`.
- `save_state()`: read+parse JSON (or `{}`), set entry for current dir to a copy of
  `sound_on`, write via `io.open(path,"w")` + `format_json`. No-op if no usable dir.
- `load_state()` on `file-loaded`: read JSON; set `sound_on` from the stored entry for
  the current dir, defaulting **every** managed key to `false` when absent (so a
  previous film's settings never leak into an unconfigured folder); then `reconcile()`
  and `render()`. Register via `mp.register_event("file-loaded", load_state)`.

### Files touched
- `mpv/scripts/track-menu.lua` — manager (A), persistence (B), limiter, script-message.
- `mpv/input.conf` — `n` → script-message.
- `guides/mpv-setup.md` — document persistence + the auto limiter; update the `n` line.
- `mpv/README.md` — extend the track-menu file description if warranted.

### Deployment (only after contrib changes verified)
- Copy `mpv/input.conf` and `mpv/scripts/track-menu.lua` → dotfiles, then RE-APPLY the
  track-menu personal deltas (`bg_alpha "0A"→"05"`, add `MBTN_BACK` close binding).
  `input.conf` has no personal deltas (the `n` line is ours), so a recopy is safe.
  `mpv.conf` is unchanged this round.
- Verify deployed script with `luac -p` + `mpv --idle` load.

## Smoke Tests

**Stable contract:** IPC-driven menu/filter behavior. No automated CI harness exists for
mpv Lua / ASS overlays in this repo; verification uses the scripted IPC harness already
established here: `mpv --idle` + `--input-ipc-server` + an ffmpeg-generated clip, driven
by a python3 unix-socket client, **playing** (`--pause=no --loop-file=inf`).

1. **Limiter auto-on + last:** toggle night mode → `af` == `[dynaudnorm, limiter]`.
   Then toggle dialogue → `af` == `[dialog, dynaudnorm, limiter]` (fixed order, limiter
   last). Toggle both off → `af` == `[]` (limiter removed).
2. **`n` routes through the script:** `keypress n` → `af` has `dynaudnorm` + `limiter`;
   menu shows night mode ON.
3. **Persistence save → restore:** play a clip under dir A, enable night mode → JSON has
   `{"<dirA>":{"dynaudnorm":true,...}}`. Reload a clip under dir A → on `file-loaded`,
   night mode auto-restored (`af` has `dynaudnorm` + `limiter`).
4. **No cross-folder leak:** with night mode saved for dir A, load a clip under dir B
   (no entry) → `sound_on` resets to all-off, `af` == `[]`.
5. **Non-local path:** play `av://lavfi:sine` → persistence no-ops, no error.
6. **Regression:** column nav (audio/sub/sound), `enter`, `esc`, `MBTN_BACK` still work;
   `luac -p` clean; script loads with no errors.

## Risks / notes
- Paused-toggle caveat unchanged (reconcile while paused can drop lavfi filters). Restore
  runs on `file-loaded`; if a file opens paused, the restored filters may not settle
  until playback starts — acceptable, document.
- `n` now depends on the script being loaded.
- `sound-toggles.json` grows by one entry per folder watched — trivial size.
