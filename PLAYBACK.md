# Playback Specification

This document specifies MPV integration, watch progress tracking, and resume logic for Freedia Center.

---

## MPV Integration

### Architecture

The backend manages MPV playback. Each active playback session is a dedicated GenServer that:

1. Launches an `mpv` process with `--input-ipc-server=/tmp/freedia-mpv-{session_id}.sock`
2. Connects to the Unix domain socket for JSON IPC
3. Polls playback position at regular intervals
4. Handles MPV lifecycle events (play, pause, seek, end-of-file, quit)
5. Cleans up the socket file and process on termination

The UI never launches MPV directly. It sends a play command to the backend, which manages the full lifecycle.

### MPV JSON IPC Protocol

MPV exposes a JSON-based IPC interface over a Unix domain socket. Communication is newline-delimited JSON.

**Commands (backend → MPV):**

```json
{"command": ["loadfile", "/path/to/video.mkv"]}
{"command": ["set_property", "pause", true]}
{"command": ["set_property", "pause", false]}
{"command": ["seek", 120, "absolute"]}
{"command": ["quit"]}
```

**Property observation (backend → MPV):**

```json
{"command": ["observe_property", 1, "time-pos"]}
{"command": ["observe_property", 2, "duration"]}
{"command": ["observe_property", 3, "pause"]}
{"command": ["observe_property", 4, "eof-reached"]}
```

**Events (MPV → backend):**

```json
{"event": "property-change", "id": 1, "name": "time-pos", "data": 542.3}
{"event": "property-change", "id": 2, "name": "duration", "data": 2844.0}
{"event": "property-change", "id": 3, "name": "pause", "data": false}
{"event": "property-change", "id": 4, "name": "eof-reached", "data": true}
{"event": "end-file", "reason": "eof"}
{"event": "end-file", "reason": "quit"}
{"event": "shutdown"}
```

### Progress Reporting

The backend observes `time-pos` via MPV's property observation mechanism. MPV sends property-change events whenever the value changes (typically every frame, throttled by the IPC socket). The backend:

1. Records position updates to the database at most **every 5 seconds** (debounced — not every frame)
2. Pushes position updates to the UI at most **every 2 seconds** (for progress bar display)
3. Records a final position on any end-of-file or quit event

### MPV Launch Flags

```
mpv --input-ipc-server=/tmp/freedia-mpv-{session_id}.sock
    --fullscreen
    --no-terminal
    --force-window=immediate
    {content_url}
```

Additional flags (e.g. `--sub-file`, `--audio-file`) may be added in the future but are out of scope for the initial implementation.

### Process Lifecycle

```
:idle
    ↓  play command received
:starting        → launch mpv process, connect to IPC socket
    ↓  IPC connected + file loaded
:playing         → observing properties, reporting progress
    ↓  user pauses or MPV pauses
:paused          → progress reporting paused
    ↓  user resumes
:playing
    ↓  end-of-file or quit
:stopped         → final progress recorded, process cleaned up
    ↓
:idle
```

If MPV crashes or the IPC socket disconnects unexpectedly, the GenServer transitions to `:stopped`, records whatever progress was last known, and cleans up.

---

## Watch Progress

### Data Model

Watch progress is tracked per playable item — each movie and each TV episode has at most one progress record.

**Fields:**

| Field | Type | Description |
|-------|------|-------------|
| `id` | UUID | Primary key |
| `entity_id` | UUID (FK → Entity) | The media entity (movie or TV series) |
| `season_number` | integer or nil | Season number for TV episodes; nil for movies |
| `episode_number` | integer or nil | Episode number for TV episodes; nil for movies |
| `position_seconds` | float | Last known playback position in seconds |
| `duration_seconds` | float | Total duration in seconds (from MPV, more accurate than TMDB metadata) |
| `completed` | boolean | Whether the item is considered "fully watched" |
| `last_watched_at` | utc_datetime | Timestamp of the most recent playback session |
| `inserted_at` | utc_datetime | |
| `updated_at` | utc_datetime | |

**Uniqueness:** `(entity_id, season_number, episode_number)` — one progress record per playable item.

For movies: `season_number` and `episode_number` are both nil.
For TV episodes: both are set. Progress is tracked per-episode, not per-season or per-series.

### Completion Threshold

An item is marked `completed: true` when:

- `position_seconds / duration_seconds >= 0.90` (90% of total duration)

This accounts for credits, post-credits scenes, and slight duration mismatches. The threshold is applied automatically when progress is recorded.

Once marked completed, the `completed` flag persists even if the user re-watches part of the episode. It can only be reset by an explicit user action (future feature) or by the resume algorithm when replaying from the beginning.

### Progress Persistence

Progress is written to SQLite by the MPV manager GenServer:

- **During playback:** Every 5 seconds (debounced from MPV's frame-level updates)
- **On pause:** Immediately
- **On stop/end-of-file:** Immediately (final position)
- **On MPV crash:** Last known position (from the most recent 5-second write)

This means at most 5 seconds of progress can be lost if the system crashes.

---

## Resume Algorithm

The resume algorithm is a **pure function**: given an entity and its progress data, it returns what to play and where to start.

### Input

- Entity (with type, seasons, episodes)
- All `WatchProgress` records for that entity

### Output

```
{:resume, content_url, position_seconds}   # resume partially watched item
{:play_next, content_url, 0}               # start next unwatched item from beginning
{:restart, content_url, 0}                 # series complete, restart from S01E01
{:no_playable_content}                     # no content_url available
```

### Algorithm

#### Movies (and MovieSeries entries)

1. If progress exists and `completed == false` → `{:resume, content_url, position_seconds}`
2. If progress exists and `completed == true` → `{:play_next, content_url, 0}` (replay from start)
3. If no progress → `{:play_next, content_url, 0}`

#### TV Series

Episodes are ordered by `(season_number, episode_number)`. The algorithm walks the episode list:

1. **Find the last watched episode** — the episode with the most recent `last_watched_at` among all progress records for this series.

2. **If the last watched episode is not completed** → `{:resume, content_url, position_seconds}` (resume where they left off)

3. **If the last watched episode is completed** → advance to the next episode:
   - Next episode in the same season → `{:play_next, content_url, 0}`
   - No more episodes in this season, but next season exists → first episode of the next season: `{:play_next, content_url, 0}`
   - No more seasons (series complete) → `{:restart, first_episode_content_url, 0}` (restart from S01E01)

4. **If no progress exists for any episode** → `{:play_next, first_episode_content_url, 0}` (start from S01E01)

**Edge cases:**

- Episode has no `content_url` (file missing) → skip to the next episode with a `content_url`
- All remaining episodes lack `content_url` → `{:no_playable_content}`
- Only some seasons have files (gaps) → skip missing seasons, advance to the next available episode

### "Play Series" User Flow

When the user selects "Play" on a TVSeries card in the UI:

1. UI sends `play:series:{entity_id}` to the backend
2. Backend runs the resume algorithm
3. Backend launches MPV with the determined episode and position
4. Backend pushes playback state to the UI (what's playing, progress)

The user doesn't choose an episode — the system picks up where they left off. Explicit episode selection (from the detail view) is a separate action that bypasses the resume algorithm.

---

## Progress Display

### Grid Cards

Each entity card in the grid can show a progress indicator:

- **No progress:** No indicator
- **Partially watched (movie):** Thin progress bar at the bottom of the card showing `position / duration`
- **Completed (movie):** Checkmark or "watched" badge
- **TV Series in progress:** Thin progress bar representing overall series progress (episodes completed / total episodes), plus a text label like "S2 E3" indicating the next episode to watch
- **TV Series complete:** Checkmark or "watched" badge

### Detail View

The detail view shows per-episode progress:

- Each episode row shows a progress bar if partially watched
- Completed episodes show a checkmark
- The "next up" episode is visually highlighted

### Data Flow

Progress data for all entities is sent to the UI as part of the library sync (on connect) and as incremental updates during playback. The UI does not query progress separately — it receives it as part of the entity data stream.
