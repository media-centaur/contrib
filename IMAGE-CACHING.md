# Image Cache Specification

This document specifies how artwork images are stored, referenced, and loaded in the Freedia Center system.

---

## Design Principles

- **One copy per role, GPU scales.** Store a single high-quality image per role (poster, backdrop, logo). Never store multiple resolutions. GPUI renders via Vulkan — GPU texture scaling is free.
- **Remote URL + local path separation.** Each image record stores both the original remote URL and the local cached path. The manager app writes both; the user-interface reads only the local path.
- **Always use an array.** `image` is always `ImageObject[]`, even when there is one image. This avoids a schema migration when additional roles are added.
- **UUID-keyed directories.** Each entity's images live under `data/images/{entity-@id}/`. The entity `@id` is the sole key — no name-based paths.

---

## ImageObject Schema

Each entry in an entity's `image` array is a schema.org `ImageObject`:

```json
{
  "@type": "ImageObject",
  "name": "poster",
  "url": "https://image.tmdb.org/t/p/original/1E5baAaEse26fej7uHcjOgEE2t2.jpg",
  "contentUrl": "images/550e8400-e29b-41d4-a716-446655440004/poster.jpg"
}
```

| Field | Type | Written by | Read by | Description |
|-------|------|-----------|---------|-------------|
| `@type` | `"ImageObject"` | manager | — | Always `"ImageObject"` |
| `name` | `string` | manager | UI | Image role (see roles below) |
| `url` | `string` | manager | manager | Canonical remote source URL |
| `contentUrl` | `string` | manager | UI | Local path relative to data directory |

The `contentUrl` path is always relative to the data directory root (e.g. `images/{uuid}/poster.jpg`, not an absolute path).

---

## Image Roles

| Role | `name` value | Aspect ratio | Usage |
|------|-------------|--------------|-------|
| Poster | `"poster"` | 2:3 portrait | Grid card artwork; required for v1 |
| Backdrop | `"backdrop"` | 16:9 landscape | Detail view hero background |
| Logo | `"logo"` | variable, transparent | Detail view title overlay |
| Thumbnail | `"thumb"` | 16:9 | Episode thumbnails in TVSeries |

**v1 requirement:** Only `poster` is needed for the grid card view. Backdrop and logo are used in detail hero layouts.

### Roles by Entity Type

| Role | Movie | TVSeries | VideoGame | VideoObject |
|------|-------|----------|-----------|-------------|
| `poster` | TMDB poster (2:3) | TMDB poster (2:3) | Steam capsule (600×900) | Thumbnail |
| `backdrop` | TMDB backdrop (16:9) | TMDB backdrop (16:9) | Steam hero (3840×1240) | — |
| `logo` | TMDB logo (transparent) | TMDB logo (transparent) | SteamGridDB logo | — |
| `thumb` | — | Episode thumbnail | — | — |

---

## Directory Structure

```
data/
└── images/
    ├── 550e8400-e29b-41d4-a716-446655440001/   # Blade Runner 2049
    │   ├── poster.jpg
    │   └── backdrop.jpg
    ├── 550e8400-e29b-41d4-a716-446655440004/   # Elden Ring
    │   └── poster.jpg
    └── ...
```

- One subdirectory per entity, named by the entity's `@id` UUID.
- Filename is `{role}.{ext}` — extension matches the source format (`.jpg` or `.png`).
- `contentUrl` in `media.json` must match the actual file path exactly.

---

## Remote URL Patterns

The manager app uses these patterns when downloading images:

**Movies and TV Series (TMDB):**

| Role | URL pattern |
|------|-------------|
| Poster | `https://image.tmdb.org/t/p/original/{poster_path}` |
| Backdrop | `https://image.tmdb.org/t/p/original/{backdrop_path}` |
| Logo | `https://image.tmdb.org/t/p/original/{logo_path}` |

`{poster_path}` etc. come from the TMDB API response (e.g. `/1E5baAaEse26fej7uHcjOgEE2t2.jpg`). Use `original` or `w780` for poster; `original` or `w1280` for backdrop.

**Video Games (Steam):**

| Role | URL pattern |
|------|-------------|
| Poster | `https://shared.cloudflare.steamstatic.com/store_item_assets/steam/apps/{appid}/library_600x900.jpg` |
| Backdrop | `https://shared.cloudflare.steamstatic.com/store_item_assets/steam/apps/{appid}/library_hero.jpg` |

`{appid}` comes from `identifier` where `propertyID == "steam"`.

**Video Objects:** No standard source. User-provided thumbnails or frames extracted from video.

---

## Responsibilities

### Manager App

- Query external APIs to get image URLs
- Download images to `data/images/{uuid}/{role}.{ext}`
- Write `ImageObject` entries into the entity's `image` array with both `url` and `contentUrl` populated
- Never overwrite a locally modified image without user confirmation

### User-Interface App

- Read `contentUrl` from the first `ImageObject` where `name == "poster"` for grid card rendering
- Read `contentUrl` for `backdrop` and `logo` when rendering detail view hero areas
- If `contentUrl` is absent or the file does not exist, render a solid-color placeholder — no crash, no error
- Never write to the `data/images/` directory

---

## Fallback Behavior

The user-interface must handle missing images gracefully at every level:

1. Entity has no `image` array or empty array → solid-color placeholder
2. No entry with `name == "poster"` → solid-color placeholder
3. `contentUrl` field is absent → solid-color placeholder
4. File at `contentUrl` does not exist on disk → solid-color placeholder

Fallback colors are assigned per `MediaKind` for visual distinction.
