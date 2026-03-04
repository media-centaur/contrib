# Testing Guide

This document covers manual testing procedures for independent and integrated verification of the Media Centaur system.

For automated test organization, commands, and strategy, see each component's `CLAUDE.md`:
- **Backend:** `backend/CLAUDE.md` → Testing Strategy section
- **Frontend:** `frontend/CLAUDE.md`

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

The server replies with `phx_reply` then streams `library:entities` batches followed by `library:sync_complete`.

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
cd backend
iex -S mix phx.server
```

**Simulate a library update** (triggers entity pushes to connected clients):
```elixir
Phoenix.PubSub.broadcast(MediaCentaur.PubSub, "library:updates", {:entities_changed, ["entity-uuid-here"]})
```

**Simulate a playback state change:**
```elixir
Phoenix.PubSub.broadcast(MediaCentaur.PubSub, "playback:events", {:playback_state_changed, :playing, %{
  entity_id: "entity-uuid",
  entity_name: "Test Movie",
  season_number: nil,
  episode_number: nil,
  content_url: "/media/movies/test.mkv",
  position_seconds: 0.0,
  duration_seconds: 7200.0
}})
```

**Simulate an entity progress update:**
```elixir
Phoenix.PubSub.broadcast(MediaCentaur.PubSub, "playback:events",
  {:entity_progress_updated, "entity-uuid", %{
    current_episode: nil,
    episode_position_seconds: 120.5,
    episode_duration_seconds: 7200.0,
    episodes_completed: 0,
    episodes_total: 1
  }, %{"action" => "resume", "name" => "Test", "positionSeconds" => 120.5, "durationSeconds" => 7200.0}, nil,
  DateTime.utc_now()})
```

---

## Testing the Frontend Independently

### Without a backend

```bash
cd frontend
cargo run
```

The UI starts with an empty library and attempts to connect to the backend. When the backend is unavailable, the UI displays a "Backend unavailable" connection status and retries with exponential backoff (1s, 2s, 4s, ... up to 30s). There is no file-based fallback — the library populates only after a successful WebSocket connection and `library` channel join.

---

## Integration Testing

### Full stack test

1. **Start the backend:**
   ```bash
   cd backend
   mix phx.server
   ```

2. **Start the frontend:**
   ```bash
   cd frontend
   cargo run
   ```

3. **Verify the connection:**
   - The UI should show the media library (or an empty library if no entities exist)
   - Connection status should indicate "Connected"

4. **Verify live updates:**
   - Drop a video file into a configured `watch_dir`
   - The pipeline processes it (detection → search → metadata → images)
   - The UI receives a `library:entities` push and displays the new entity

5. **Verify playback (requires MPV installed):**
   - Select an entity in the UI and trigger play
   - The backend launches MPV and pushes `playback:state_changed`
   - Entity progress updates appear on each DB save (~60s interval, and on pause/stop/EOF)
   - Closing MPV triggers `playback:state_changed` with `state: "idle"`
