# Testing Guide

This document covers how to test the Freedia Center system — both automated tests and manual testing procedures for independent and integrated verification.

---

## Automated Tests

### Backend (media-manager)

```bash
cd media-manager
mix test                      # run all tests (excludes :external by default)
mix test --only external      # run TMDB integration tests (requires network)
mix precommit                 # compile --warnings-as-errors, format, test
```

**Test organization:**

Tests are organized by domain, mirroring the application's module structure. Each test file covers one bounded context or integration seam:

| Path | What it covers |
|------|---------------|
| `test/media_manager/library/entity_test.exs` | Entity CRUD, UUID stability, round-trip reads |
| `test/media_manager/library/watched_file_test.exs` | WatchedFile detection, search, metadata fetch |
| `test/media_manager/library/watch_progress_test.exs` | WatchProgress upsert, auto-completion, idempotency |
| `test/media_manager/serializer_test.exs` | Serializer output shape, DATA-FORMAT.md compliance, MovieSeries handling |
| `test/media_manager_web/channels/library_channel_test.exs` | Library channel join reply shape, entity push shapes, JSON string keys |
| `test/media_manager_web/channels/playback_channel_test.exs` | Playback channel join reply shape, PubSub push shapes, JSON string keys |

Tests that require external network access (TMDB API) are tagged `@tag :external` and excluded from the default test run.

### Frontend (user-interface)

```bash
cd user-interface
cargo test                        # run all tests
cargo clippy -- -D warnings       # lint
cargo fmt --check                 # format check
```

**Test organization:**

| Module | What it covers |
|--------|---------------|
| `backend::dispatch` | Message classification for every API.md message type with realistic payloads |
| `backend::commands` | Outgoing command serialization (play, pause, stop, seek, heartbeat) |
| `backend::protocol` | Phoenix Channels wire protocol encode/decode |
| `data::progress` | WatchProgress fraction and completion calculations |

---

## Testing the Backend Independently

### Using wscat

Connect to the WebSocket endpoint directly to inspect join replies and server pushes.

**Install:**
```bash
npm install -g wscat
```

**Connect:**
```bash
wscat -c 'ws://localhost:4000/socket/websocket?vsn=2.0.0'
```

**Join the library channel:**
```json
["1","1","library","phx_join",{}]
```

The server replies with the full entity list:
```json
["1","1","library","phx_reply",{"status":"ok","response":{"entities":[...]}}]
```

**Join the playback channel:**
```json
["2","2","playback","phx_join",{}]
```

**Send a heartbeat (required every 30s to keep the connection alive):**
```json
[null,"99","phoenix","heartbeat",{}]
```

### Using IEx

Start the server in an interactive shell to simulate events:

```bash
cd media-manager
iex -S mix phx.server
```

**Simulate a library update** (triggers `entity_added`/`entity_updated` pushes to connected clients):
```elixir
Phoenix.PubSub.broadcast(MediaManager.PubSub, "library:updates", {:entities_changed, ["entity-uuid-here"]})
```

**Simulate a playback state change:**
```elixir
Phoenix.PubSub.broadcast(MediaManager.PubSub, "playback:events", {:playback_state_changed, :playing, %{
  entity_id: "entity-uuid",
  entity_name: "Test Movie",
  season_number: nil,
  episode_number: nil,
  content_url: "/media/movies/test.mkv",
  position_seconds: 0.0,
  duration_seconds: 7200.0
}})
```

**Simulate a progress tick:**
```elixir
Phoenix.PubSub.broadcast(MediaManager.PubSub, "playback:events", {:playback_progress, %{
  position_seconds: 120.5,
  duration_seconds: 7200.0
}})
```

---

## Testing the Frontend Independently

### Without a backend

```bash
cd user-interface
cargo run
```

The UI starts with an empty library and attempts to connect to the backend. When the backend is unavailable, the UI displays a "Backend unavailable" connection status and retries with exponential backoff (1s, 2s, 4s, ... up to 30s). There is no file-based fallback — the library populates only after a successful WebSocket connection and `library` channel join.

---

## Integration Testing

### Full stack test

1. **Start the backend:**
   ```bash
   cd media-manager
   mix phx.server
   ```

2. **Start the frontend:**
   ```bash
   cd user-interface
   cargo run
   ```

3. **Verify the connection:**
   - The UI should show the media library (or an empty library if no entities exist)
   - Connection status should indicate "Connected"

4. **Verify live updates:**
   - Drop a video file into a configured `watch_dir`
   - The pipeline processes it (detection → search → metadata → images)
   - The UI receives a `library:entity_added` push and displays the new entity

5. **Verify playback (requires MPV installed):**
   - Select an entity in the UI and trigger play
   - The backend launches MPV and pushes `playback:state_changed`
   - Progress ticks appear every 2 seconds
   - Closing MPV triggers `playback:state_changed` with `state: "idle"`
