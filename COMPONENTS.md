# System Components

Freedia Center is a collection of loosely coupled components that share a common **data directory**. Components communicate through the file system only — there is no IPC, shared memory, or network protocol between them.

---

## Component Overview

| Component | Status | Role |
|-----------|--------|------|
| `user-interface` | Active | Read-only media browser and launcher |
| `manager` | Planned | Entity management, metadata scraping, image downloading |

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
- `data/media.json` — media library (format: `DATA-FORMAT.md`)
- `data/images/{uuid}/{role}.{ext}` — cached artwork (format: `IMAGE-CACHING.md`)
- `config.json` — keybindings and action templates

**Technology:**
- Language: Rust
- UI framework: GPUI (Community Edition fork)
- UI components: gpui-component
- Display: Native Wayland, Vulkan GPU acceleration
- Async: smol
- File watching: notify

---

## Media Manager (planned)

A separate application responsible for all **write** operations on the data directory. Expected to be a CLI or TUI tool.

**Responsibilities:**
- Create and edit entity records in `media.json`
- Scrape metadata from external sources (TMDB, Steam, IGDB, TVDB)
- Download and cache artwork images into `data/images/{uuid}/`
- Populate `ImageObject.url` (remote source) and `ImageObject.contentUrl` (local path) for every image
- Maintain UUID stability — never change an entity's `@id` once assigned

**Does NOT:**
- Render any media center UI
- Launch media playback
- Run concurrently with normal media center use (though hot-reload means it can run alongside)

**Expected workflow:** The manager is run separately to add or refresh content. After it writes changes, the user-interface picks them up automatically via hot-reload.

---

## Shared Data Directory

Both components operate on a shared **data directory**. The default is `data/` relative to the working directory; at runtime XDG paths apply.

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

Neither component needs to know anything about the other's implementation details.
