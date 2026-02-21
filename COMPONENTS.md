# System Components

Freedia Center is a collection of loosely coupled components that share a common **data directory**. Components communicate through the file system only — there is no IPC, shared memory, or network protocol between them.

---

## Component Overview

| Component | Status | Role |
|-----------|--------|------|
| `user-interface` | Active | Read-only media browser and launcher |
| `media-manager` | Active (in development) | Entity management, metadata scraping, image downloading |

---

## user-interface

**Repository:** `freedia-center/user-interface`

A Rust/GPUI native desktop application. Designed for fullscreen 10-foot UI with remote or gamepad input (FLIRC USB adapter).

**Responsibilities:**
- Load and parse `media.json` at startup
- Render a browsable grid of media entity cards
- Open entity-specific detail views (hero layout, season/episode navigation)
- Resolve and launch shell action commands (e.g. `mpv`, `steam://`, `xdg-open`)
- Hot-reload data and config within seconds of file changes

**Does NOT:**
- Write to `media.json`
- Download or transcode images
- Call external APIs (TMDB, Steam, etc.)
- Manage entity metadata

**Files it reads:**
- `{shared_media_library}` — media library JSON file (format: `DATA-FORMAT.md`). Default: `~/.local/share/freedia-center/media.json`.
- `{media_images_dir}/{uuid}/{role}.{ext}` — cached artwork (format: `IMAGE-CACHING.md`). Default: `~/.local/share/freedia-center/images/`.
- `~/.config/freedia-center/user-interface.json` — keybindings and action templates

`shared_media_library` and `media_images_dir` are set via config fields or CLI flags, and must match the paths configured in `media-manager`.

**Technology:**
- Language: Rust
- UI framework: GPUI (Community Edition fork)
- UI components: gpui-component
- Display: Native Wayland, Vulkan GPU acceleration
- Async: smol
- File watching: notify

---

## Media Manager

**Repository:** `freedia-center/media-manager`

**Status:** Active (in development)

A Phoenix/Elixir web application that is the **write-side** of Freedia Center. It watches a configured media directory for newly completed torrent downloads, identifies the content, scrapes metadata and artwork from external APIs, and maintains `media.json` and the image cache that the `user-interface` reads.

**Design document:** `media-manager/DESIGN.md`

### Architecture

**SQLite is the canonical database.** All entity data (names, descriptions, genres, TMDB IDs, image remote URLs, season/episode structure) is stored in SQLite. `media.json` is a *generated export* of SQLite data — it can always be regenerated from SQLite at any time. This means:

- `media.json` corrupted or deleted → regenerate from SQLite instantly
- Output paths temporarily unavailable → app continues with SQLite; writes queue and resume on reconnect
- Images lost → remote `url` stored in SQLite → re-download on demand

**Processing pipeline:** A Broadway pipeline automatically processes new files through detection → TMDB search → metadata fetch. The Watcher detects files and writes to the database; a Broadway producer polls for new detections every 10 seconds and feeds them to concurrent processors (3 by default). High-confidence TMDB matches are auto-approved and progress through the full pipeline. Low-confidence matches stop at `:pending_review` for human approval in the admin UI. See `media-manager/PIPELINE.md` for full details.

**Responsibilities:**
- Watch `media_dir` for new video files (torrent download completions)
- Parse filenames to extract title, year, and media type
- Automatically search TMDB and compute a confidence score for the best match
- Auto-approve high-confidence matches; queue low-confidence matches for human review via the admin UI
- Fetch full metadata from TMDB (details, cast, seasons, episodes)
- Download and cache artwork images into `{media_images_dir}/{uuid}/`
- Maintain `media.json` at `shared_media_library` — the integration point with the user-interface
- Store remote image URLs (`ImageObject.url`) and local paths (`ImageObject.contentUrl`) in SQLite for re-download resilience
- Maintain UUID stability — never change an entity's `@id` once assigned
- Handle mount resilience: never remove library entries due to a transient `media_dir` unmount

**Supported media types:** Movie, TVSeries (full season/episode metadata), VideoObject (fallback).

**Does NOT:**
- Render any media center UI (has a local admin panel only)
- Launch media playback
- Support games (out of scope)

### Configuration

Reads `~/.config/freedia-center/media-manager.toml` at startup. Key settings:

| Key | Default | Description |
|-----|---------|-------------|
| `media_dir` | `/mnt/videos/Videos` | Video files directory (watched for additions/removals) |
| `shared_media_library` | `~/.local/share/freedia-center/media.json` | Path to the media library JSON file (must match user-interface config) |
| `media_images_dir` | `~/.local/share/freedia-center/images` | Directory for cached artwork images (must match user-interface config) |
| `tmdb.api_key` | `""` | TMDB API key |
| `pipeline.auto_approve_threshold` | `0.85` | Confidence threshold for auto-approval |

### Technology

- Language: Elixir
- Framework: Phoenix + LiveView
- Database: SQLite via Ash + ash_sqlite
- Pipeline: Broadway
- File watching: :file_system (inotify on Linux)
- HTTP client: Req
- Admin UI: Phoenix LiveView (local-only, no authentication)

---

## Shared Data Paths

Both components share two configurable paths. Defaults place them under `~/.local/share/freedia-center/`; each component configures them independently.

| Path | Default | Purpose |
|------|---------|---------|
| `shared_media_library` | `~/.local/share/freedia-center/media.json` | Media library JSON file — written by manager, read by user-interface |
| `media_images_dir` | `~/.local/share/freedia-center/images` | Cached artwork images — one subdirectory per entity UUID |

```
~/.local/share/freedia-center/
├── media.json              # Written by manager, read by user-interface
└── images/
    ├── {uuid}/             # One directory per entity @id
    │   ├── poster.jpg
    │   ├── backdrop.jpg
    │   └── logo.png
    └── ...
```

These shared paths are the **only integration point** between components. Format details are in `DATA-FORMAT.md` and `IMAGE-CACHING.md`.

---

## Integration Contract

The components are fully decoupled. Their integration contract is:

1. `media.json` must conform to `DATA-FORMAT.md` — the user-interface will reject or degrade gracefully on malformed entries.
2. Image files must exist at the paths specified in `ImageObject.contentUrl`, relative to the data directory.
3. Entity `@id` values are stable UUIDs — they double as image directory names and must never be reassigned.
4. The user-interface will reflect any file changes within seconds (hot-reload). No restart required.
5. `media.json` is a **derived artifact** generated from the manager's SQLite database. It can be regenerated at any time without data loss.

Neither component needs to know anything about the other's implementation details.
