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
- `{shared_library_dir}/media.json` — media library (format: `DATA-FORMAT.md`). Default: `~/.local/share/freedia-center/data/media.json`.
- `{shared_library_dir}/images/{uuid}/{role}.{ext}` — cached artwork (format: `IMAGE-CACHING.md`)
- `~/.config/freedia-center/user-interface.json` — keybindings and action templates

`shared_library_dir` is set via the `shared_library_dir` config field or the `--shared-library-dir` CLI flag, and must match the path configured in `media-manager`.

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
- `shared_library_dir` temporarily unavailable → app continues with SQLite; writes queue and resume on reconnect
- Images lost → remote `url` stored in SQLite → re-download on demand

**Responsibilities:**
- Watch `media_dir` for new video files (torrent download completions)
- Parse filenames to extract title, year, and media type
- Search TMDB and compute a confidence score for the best match
- Auto-approve high-confidence matches; queue low-confidence matches for human review via the admin UI
- Fetch full metadata from TMDB (details, cast, seasons, episodes)
- Download and cache artwork images into `shared_library_dir/images/{uuid}/`
- Maintain `media.json` in `shared_library_dir` — the integration point with the user-interface
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
| `shared_library_dir` | `~/.local/share/freedia-center/data` | Shared data directory (must match user-interface config) |
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

## Shared Data Directory

Both components operate on a **shared data directory**. The default is `~/.local/share/freedia-center/data`; configured independently in each component.

```
data/
├── media.json              # Written by manager, read by user-interface
└── images/
    ├── {uuid}/             # One directory per entity @id
    │   ├── poster.jpg
    │   ├── backdrop.jpg
    │   └── logo.png
    └── ...
```

The data directory is the **only integration point** between components. Format details are in `DATA-FORMAT.md` and `IMAGE-CACHING.md`.

---

## Integration Contract

The components are fully decoupled. Their integration contract is:

1. `media.json` must conform to `DATA-FORMAT.md` — the user-interface will reject or degrade gracefully on malformed entries.
2. Image files must exist at the paths specified in `ImageObject.contentUrl`, relative to the data directory.
3. Entity `@id` values are stable UUIDs — they double as image directory names and must never be reassigned.
4. The user-interface will reflect any file changes within seconds (hot-reload). No restart required.
5. `media.json` is a **derived artifact** generated from the manager's SQLite database. It can be regenerated at any time without data loss.

Neither component needs to know anything about the other's implementation details.
