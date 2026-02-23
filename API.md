# Phoenix Channels API Specification

This document specifies the WebSocket API between the backend (media-manager) and the user-interface. The API uses the [Phoenix Channels](https://hexdocs.pm/phoenix/channels.html) protocol over a single WebSocket connection.

---

## Connection

### Endpoint

```
ws://localhost:4000/socket/websocket
```

The UI connects on startup. The Phoenix Channels protocol handles multiplexing, heartbeat, and reconnection over this single connection.

### Lifecycle

1. **Connect:** UI opens a WebSocket to the endpoint
2. **Join channels:** UI joins one or more topic channels (see below)
3. **Heartbeat:** Phoenix sends heartbeat pings every 30 seconds; the UI must respond or the connection is closed
4. **Reconnect:** On disconnect, the UI retries with exponential backoff (1s, 2s, 4s, 8s, max 30s)
5. **Rejoin:** After reconnection, the UI re-joins all channels and receives fresh state

### Authentication

None for v1 — the backend runs locally and serves a single household. Authentication may be added if remote access is ever needed.

---

## Channel Topics

| Topic | Purpose |
|-------|---------|
| `library` | Media library data: full sync on join, incremental updates |
| `playback` | Playback commands and state: play, pause, stop, progress |

---

## `library` Channel

### Join

**Topic:** `library`

On join, the backend returns an empty reply and begins streaming the library as a series of `library:entities` batches, followed by a `library:sync_complete` signal. No parameters required.

**Reply:**

```json
{
  "status": "ok",
  "response": {}
}
```

After the reply, the backend pushes the full library in batches (see `library:entities` below), then pushes `library:sync_complete` to signal the initial sync is done. The UI should accumulate entities from each batch and consider the library fully loaded once `library:sync_complete` arrives.

### Server Push: `library:entities`

A batch of entity payloads with upsert semantics. Used for both initial sync batches and incremental updates from the pipeline.

```json
{
  "entities": [
    {
      "@id": "550e8400-...",
      "entity": { "@type": "Movie", "name": "Blade Runner 2049", ... },
      "progress": null
    },
    {
      "@id": "660f9500-...",
      "entity": { "@type": "TVSeries", "name": "Severance", ... },
      "progress": {
        "current_episode": { "season": 2, "episode": 3 },
        "episode_position_seconds": 1200.5,
        "episode_duration_seconds": 3200.0,
        "episodes_completed": 12,
        "episodes_total": 20
      }
    }
  ]
}
```

Each entity in the `entities` array follows the wrapper format defined in `DATA-FORMAT.md` (`{@id, entity}`), with an added `progress` field containing aggregated watch progress for that entity (or `null` if no progress exists). The UI replaces its local copy of each entity entirely (upsert).

### Server Push: `library:sync_complete`

Signals the initial library sync is done. Sent exactly once after join, after all initial `library:entities` batches. Never sent during incremental updates.

```json
{}
```

### Server Push: `library:entities_removed`

Sent when entities are removed from the library. Contains a batch of removed entity IDs.

```json
{
  "ids": ["550e8400-..."]
}

---

## `playback` Channel

### Join

**Topic:** `playback`

On join, the backend sends the current playback state (if anything is playing).

**Reply:**

```json
{
  "status": "ok",
  "response": {
    "state": "idle",
    "now_playing": null
  }
}
```

Or if something is playing:

```json
{
  "status": "ok",
  "response": {
    "state": "playing",
    "now_playing": {
      "entity_id": "660f9500-...",
      "entity_name": "Severance",
      "season_number": 2,
      "episode_number": 3,
      "episode_name": "Who Is Alive?",
      "content_url": "/media/tv/Severance/S02/S02E03.mkv",
      "position_seconds": 1200.5,
      "duration_seconds": 3200.0
    }
  }
}
```

### Client Message: `play`

Request playback of a specific entity. The backend determines the exact episode and position using the resume algorithm (see `PLAYBACK.md`).

```json
{
  "entity_id": "660f9500-..."
}
```

**Reply:**

```json
{
  "status": "ok",
  "response": {
    "action": "resume",
    "entity_id": "660f9500-...",
    "season_number": 2,
    "episode_number": 3,
    "position_seconds": 1200.5
  }
}
```

Possible `action` values: `"resume"`, `"play_next"`, `"restart"`.

If playback cannot start:

```json
{
  "status": "error",
  "response": {
    "reason": "no_playable_content"
  }
}
```

### Client Message: `play_episode`

Play a specific episode (bypasses resume algorithm). Used when the user selects an episode from the detail view.

```json
{
  "entity_id": "660f9500-...",
  "season_number": 2,
  "episode_number": 5
}
```

**Reply:** Same format as `play`.

### Client Message: `pause`

Toggle pause on the current playback.

```json
{}
```

**Reply:** `{"status": "ok"}`

### Client Message: `stop`

Stop the current playback and close MPV.

```json
{}
```

**Reply:** `{"status": "ok"}`

### Client Message: `seek`

Seek to an absolute position.

```json
{
  "position_seconds": 600.0
}
```

**Reply:** `{"status": "ok"}`

### Server Push: `playback:state_changed`

Sent when the playback state changes (play, pause, stop, new episode).

```json
{
  "state": "playing",
  "now_playing": {
    "entity_id": "660f9500-...",
    "entity_name": "Severance",
    "season_number": 2,
    "episode_number": 3,
    "episode_name": "Who Is Alive?",
    "content_url": "/media/tv/Severance/S02/S02E03.mkv",
    "position_seconds": 1200.5,
    "duration_seconds": 3200.0
  }
}
```

Possible `state` values: `"playing"`, `"paused"`, `"stopped"`, `"idle"`.

When `state` is `"idle"` or `"stopped"`, `now_playing` is `null`.

### Server Push: `playback:progress`

Sent every 2 seconds during active playback. Lightweight message for updating the UI progress bar.

```json
{
  "position_seconds": 1205.3,
  "duration_seconds": 3200.0
}
```

### Server Push: `playback:entity_progress_updated`

Sent when an entity's overall progress summary changes (e.g. an episode was marked completed). The UI uses this to update progress indicators on grid cards without re-fetching the entire library.

```json
{
  "entity_id": "660f9500-...",
  "progress": {
    "current_episode": { "season": 2, "episode": 4 },
    "episode_position_seconds": 0,
    "episode_duration_seconds": 3100.0,
    "episodes_completed": 13,
    "episodes_total": 20
  }
}
```

---

## Entity Progress Summary

The `progress` object attached to entities (in library sync and progress updates) is a backend-computed summary. It is **not** the raw `WatchProgress` records — the backend aggregates them into a display-ready format.

| Field | Type | Description |
|-------|------|-------------|
| `current_episode` | `{season, episode}` or `null` | Next episode to play (TV only); null for movies |
| `episode_position_seconds` | float | Position in the current/last-watched item |
| `episode_duration_seconds` | float | Duration of the current/last-watched item |
| `episodes_completed` | integer | Number of completed episodes (TV only; 0 or 1 for movies) |
| `episodes_total` | integer | Total number of episodes with files (TV only; 1 for movies) |

For movies, `current_episode` is `null`, `episodes_total` is `1`, and `episodes_completed` is `0` or `1`.

---

## Error Handling

All client messages receive a reply with `status: "ok"` or `status: "error"`. Error replies include a `reason` string:

| Reason | Meaning |
|--------|---------|
| `"not_found"` | Entity ID does not exist |
| `"no_playable_content"` | Entity has no content_url (no files) |
| `"not_playing"` | Pause/stop/seek sent but nothing is playing |
| `"invalid_episode"` | The requested season/episode doesn't exist |

> **Note:** Sending `play` while something is already playing silently stops the previous session and starts the new one. No error is returned.

---

## Message Flow Examples

### User opens app and browses library

```
UI → Backend:  join "library"
Backend → UI:  reply {}
Backend → UI:  push "library:entities" {entities: [...batch 1...]}
Backend → UI:  push "library:entities" {entities: [...batch 2...]}
Backend → UI:  push "library:sync_complete" {}

UI → Backend:  join "playback"
Backend → UI:  reply with state: "idle"
```

### User plays a TV series (resume)

```
UI → Backend:       push "play" {entity_id: "660f9500-..."}
Backend → UI:       reply {action: "resume", season: 2, episode: 3, position: 1200.5}
Backend:            launches MPV, seeks to position
Backend → UI:       push "playback:state_changed" {state: "playing", now_playing: {...}}
Backend → UI:       push "playback:progress" {position: 1202.3, ...}  (every 2s)
...
Backend → UI:       push "playback:state_changed" {state: "idle"}     (MPV closed)
Backend → UI:       push "playback:entity_progress_updated" {...}      (progress saved)
```

### Library updates while UI is connected

```
Backend pipeline completes processing a new movie:
Backend → UI:       push "library:entities" {entities: [{entity + progress}]}

Entity deleted:
Backend → UI:       push "library:entities_removed" {ids: ["uuid-1"]}
```
