# Data Format Specification

Canonical reference for all JSON data formats in the Freedia Center system. Both the `user-interface` app and the `manager` app use these formats.

---

## Foundation: Schema.org + JSON-LD

All media entities use vocabulary from [schema.org](https://schema.org), serialised as [JSON-LD](https://json-ld.org/). This is the most important design constraint in the system.

- **Field names are schema.org property names.** `name`, `description`, `datePublished`, `contentUrl`, `genre`, `director`, `duration`, `containsSeason`, `episodeNumber`, and all others are schema.org properties. Do not rename them or invent alternatives.
- **`@type` is the schema.org class.** `"Movie"`, `"TVSeries"`, `"VideoGame"`, `"VideoObject"`, `"ImageObject"`, `"PropertyValue"` are schema.org types. Use exact canonical capitalisation.
- **`@id` is a JSON-LD node identifier.** In this system it is a plain UUID (e.g. `"550e8400-e29b-41d4-a716-446655440004"`), not a full URI. It is the app-level stable key used for image directory names and cross-references.
- **The outer wrapper is app-specific.** The `{ "@id": ..., "entity": {...} }` envelope is not schema.org — it is a thin app container. The inner `entity` object is a valid schema.org node.
- **Before adding a field:** check [schema.org](https://schema.org) for an existing property and use it if one fits. Only introduce a non-schema.org field if there is no reasonable match, and document why.

**Why schema.org?** It provides a large, well-maintained vocabulary for media (Movie, TVSeries, VideoGame, VideoObject, etc.) with established field semantics. External metadata sources (TMDB, Steam, IGDB, TVDB) map cleanly onto it. The format is human-readable, git-diffable, and works with standard JSON tooling without a specialised parser.

---

## media.json — Media Library

### Top-Level Structure

`media.json` is a JSON array of **wrapped entities**:

```json
[
  { "@id": "...", "entity": { "@type": "...", ... } },
  { "@id": "...", "entity": { "@type": "...", ... } }
]
```

### Wrapper Object

| Field | Type | Description |
|-------|------|-------------|
| `@id` | `string` (UUID v4) | App-level unique identifier; stable across updates |
| `entity` | `object` | A schema.org entity (see entity types below) |

The `@id` UUID is the stable key used for image directory names and cross-references. It must not change once assigned.

---

### Entity Object

All entities have `@type` as their first field. Remaining fields follow the schema.org type definition.

#### Common Fields (all entity types)

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `@type` | `string` | Yes | Schema.org type name (see supported types below) |
| `name` | `string` | Yes | Display title |
| `description` | `string` | No | Long-form text description |
| `datePublished` | `string` | No | Year or ISO date (`"2017"`, `"2017-10-06"`) |
| `genre` | `string[]` | No | Genre labels |
| `image` | `ImageObject[]` | No | Artwork references (see ImageObject below) |
| `aggregateRating` | `AggregateRating` | No | Numeric score |
| `identifier` | `PropertyValue[]` | No | External storefront IDs |
| `contentUrl` | `string` | No | Local file path used for playback actions |
| `url` | `string` | No | Remote info page URL (TMDB, etc.) |

---

### Supported Entity Types

#### Movie — `schema.org/Movie`

Additional fields:

| Field | Type | Description |
|-------|------|-------------|
| `director` | `string` | Director name |
| `duration` | `string` | ISO 8601 duration (`"PT2H44M"`) |
| `contentRating` | `string` | MPAA rating: `"G"`, `"PG"`, `"PG-13"`, `"R"`, `"NC-17"` |

#### MovieSeries — `schema.org/MovieSeries`

A collection of related movies (e.g. "The Lord of the Rings", "John Wick"). Standalone movies remain top-level `Movie` entities; movies that belong to a series are always nested inside a `MovieSeries` entity via the `hasPart` property.

Additional fields:

| Field | Type | Description |
|-------|------|-------------|
| `director` | `string` | Series-level director (optional; individual movies may differ) |
| `hasPart` | `Movie[]` | Embedded ordered list of movies in the series |

Child `Movie` objects inside `hasPart` use the same fields as standalone `Movie` entities. They are sorted by `datePublished` at display time in the UI.

Example:

```json
{
  "@id": "550e8400-e29b-41d4-a716-446655440020",
  "entity": {
    "@type": "MovieSeries",
    "name": "The Lord of the Rings",
    "description": "Peter Jackson's epic fantasy trilogy.",
    "datePublished": "2001",
    "genre": ["Fantasy", "Adventure"],
    "director": "Peter Jackson",
    "image": [
      {
        "@type": "ImageObject",
        "name": "poster",
        "url": "https://image.tmdb.org/t/p/original/...",
        "contentUrl": "images/550e8400-e29b-41d4-a716-446655440020/poster.jpg"
      }
    ],
    "aggregateRating": { "ratingValue": 8.9 },
    "url": "https://www.themoviedb.org/collection/119",
    "hasPart": [
      {
        "@type": "Movie",
        "name": "The Fellowship of the Ring",
        "datePublished": "2001",
        "director": "Peter Jackson",
        "duration": "PT2H58M",
        "contentRating": "PG-13",
        "description": "A meek Hobbit sets out on a journey...",
        "image": [
          {
            "@type": "ImageObject",
            "name": "poster",
            "contentUrl": "images/550e8400-e29b-41d4-a716-446655440020/fellowship-poster.jpg"
          }
        ],
        "aggregateRating": { "ratingValue": 8.8 },
        "contentUrl": "/media/movies/LOTR/fellowship.mkv"
      }
    ]
  }
}
```

#### VideoGame — `schema.org/VideoGame`

Additional fields:

| Field | Type | Description |
|-------|------|-------------|
| `gamePlatform` | `string` | Platform name (`"PC"`, `"PlayStation 5"`) |
| `publisher` | `string` | Publisher name |

#### TVSeries — `schema.org/TVSeries`

Additional fields:

| Field | Type | Description |
|-------|------|-------------|
| `numberOfSeasons` | `integer` | Total season count (from TMDB; may exceed the number of seasons with scanned files) |
| `containsSeason` | `TVSeason[]` | Embedded ordered list of seasons — **only includes seasons/episodes with scanned video files**, not all seasons from TMDB |

**TVSeason** (embedded; not a top-level wrapper entity):

| Field | Type | Description |
|-------|------|-------------|
| `seasonNumber` | `integer` | Season index, 1-based |
| `numberOfEpisodes` | `integer` | Episode count |
| `name` | `string` | Optional season title |
| `episode` | `TVEpisode[]` | Embedded ordered list of episodes |

**TVEpisode** (embedded inside `episode[]`):

| Field | Type | Description |
|-------|------|-------------|
| `episodeNumber` | `integer` | Episode index, 1-based |
| `name` | `string` | Episode title |
| `duration` | `string` | ISO 8601 duration |
| `description` | `string` | Episode synopsis |
| `image` | `ImageObject[]` | Thumbnail images |
| `contentUrl` | `string` | Local file path for playback |

#### VideoObject — `schema.org/VideoObject`

No additional fields beyond the common set. Used for conference talks, clips, recordings, etc.

#### Unknown Types

Any `@type` not listed above is parsed generically. The UI renders all top-level string and number fields as metadata rows. No data is lost or rejected.

---

### Common Sub-types

#### ImageObject

Used in `image` arrays on all entity types and in TVEpisode.

```json
{
  "@type": "ImageObject",
  "name": "poster",
  "url": "https://image.tmdb.org/t/p/original/1E5baAaEse26fej7uHcjOgEE2t2.jpg",
  "contentUrl": "images/550e8400-e29b-41d4-a716-446655440004/poster.jpg"
}
```

| Field | Type | Description |
|-------|------|-------------|
| `@type` | `"ImageObject"` | Always `"ImageObject"` |
| `name` | `string` | Image role: `"poster"`, `"backdrop"`, `"logo"`, `"thumb"` |
| `url` | `string` | Remote source URL — written by manager app, not read by UI |
| `contentUrl` | `string` or `null` | Local path relative to the data directory — read by UI. `null` while the image download is pending. |

See [`IMAGE-CACHING.md`](IMAGE-CACHING.md) for directory conventions and role definitions.

#### AggregateRating

```json
{ "ratingValue": 8.0 }
```

| Field | Type | Description |
|-------|------|-------------|
| `ratingValue` | `number` | Score value (TMDB: 0–10, Metacritic: 0–100) |

#### PropertyValue (Identifiers)

Used in `identifier` arrays for external storefronts.

```json
[
  { "@type": "PropertyValue", "propertyID": "steam", "value": "1245620" },
  { "@type": "PropertyValue", "propertyID": "tmdb",  "value": "335984" }
]
```

| Field | Type | Description |
|-------|------|-------------|
| `@type` | `"PropertyValue"` | Always `"PropertyValue"` |
| `propertyID` | `string` | Storefront key: `"steam"`, `"tmdb"`, `"gog"`, `"igdb"`, `"tvdb"` |
| `value` | `string` | The external ID |

Identifiers are flattened for action template substitution as `identifier.{propertyID}` — e.g. `identifier.steam` resolves to `"1245620"`.

---

### Complete Entity Examples

**Movie:**

```json
{
  "@id": "550e8400-e29b-41d4-a716-446655440001",
  "entity": {
    "@type": "Movie",
    "name": "Blade Runner 2049",
    "description": "A young blade runner's discovery of a long-buried secret.",
    "datePublished": "2017",
    "genre": ["Sci-Fi", "Drama"],
    "director": "Denis Villeneuve",
    "duration": "PT2H44M",
    "contentRating": "R",
    "image": [
      {
        "@type": "ImageObject",
        "name": "poster",
        "url": "https://image.tmdb.org/t/p/original/gajva2L0rPYkEWjzgFlBXCAVBE5.jpg",
        "contentUrl": "images/550e8400-e29b-41d4-a716-446655440001/poster.jpg"
      }
    ],
    "identifier": [
      { "@type": "PropertyValue", "propertyID": "tmdb", "value": "335984" }
    ],
    "aggregateRating": { "ratingValue": 8.0 },
    "contentUrl": "/media/movies/Blade Runner 2049/movie.mkv",
    "url": "https://www.themoviedb.org/movie/335984"
  }
}
```

**VideoGame:**

```json
{
  "@id": "550e8400-e29b-41d4-a716-446655440004",
  "entity": {
    "@type": "VideoGame",
    "name": "Elden Ring",
    "description": "An action RPG set in the Lands Between.",
    "datePublished": "2022",
    "genre": ["Action RPG", "Open World"],
    "gamePlatform": "PC",
    "publisher": "Bandai Namco",
    "image": [
      {
        "@type": "ImageObject",
        "name": "poster",
        "url": "https://shared.cloudflare.steamstatic.com/store_item_assets/steam/apps/1245620/library_600x900.jpg",
        "contentUrl": "images/550e8400-e29b-41d4-a716-446655440004/poster.jpg"
      }
    ],
    "identifier": [
      { "@type": "PropertyValue", "propertyID": "steam", "value": "1245620" }
    ],
    "aggregateRating": { "ratingValue": 9.2 }
  }
}
```

---

## config.json — User Configuration

### Structure

```json
{
  "keybindings": { ... },
  "actions": { ... }
}
```

### Keybindings

Maps logical action names to key strings. Key strings use GPUI keystroke notation.

```json
{
  "keybindings": {
    "move_up":     "up",
    "move_down":   "down",
    "move_left":   "left",
    "move_right":  "right",
    "select":      "enter",
    "back":        "escape",
    "scale_up":    "=",
    "scale_down":  "-",
    "cycle_theme": "t",
    "quit":        "q"
  }
}
```

### Action Templates

Actions are grouped by `@type` and define shell commands with placeholder variables.

```json
{
  "actions": {
    "Movie": [
      { "name": "Play",        "command": "mpv '{contentUrl}'" },
      { "name": "Info (TMDB)", "command": "xdg-open '{url}'" }
    ],
    "VideoGame": [
      { "name": "Launch (Steam)", "command": "steam steam://rungameid/{identifier.steam}" }
    ],
    "TVSeries": [
      { "name": "Play Episode", "command": "mpv '{contentUrl}'" }
    ],
    "MovieSeries": [
      { "name": "Info (TMDB)", "command": "xdg-open '{url}'" }
    ]
  }
}
```

#### Placeholder Resolution

Placeholders use `{fieldName}` syntax and are resolved from the raw entity JSON at load time.

| Pattern | Source |
|---------|--------|
| `{name}` | Top-level string field |
| `{contentUrl}` | Top-level `contentUrl` |
| `{identifier.steam}` | `identifier` array entry with `propertyID == "steam"`, its `value` |
| `{genre}` | String arrays joined with `", "` |

An action is omitted from the UI (greyed out in prior designs, excluded in current) if any placeholder in its `command` cannot be resolved for that specific entity.
