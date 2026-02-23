# Freedia Center — Specifications

This repository (`freedia-center/specifications`) is the **authoritative source** for all cross-component specifications in the Freedia Center project. Every component repository references these documents.

## Data Model Foundation

All entity data in this project is grounded in [schema.org](https://schema.org) vocabulary, serialised as [JSON-LD](https://json-ld.org/). This is the most important design constraint in the system.

Entity field names (`name`, `datePublished`, `contentUrl`, `containsSeason`, `episodeNumber`, etc.) are **schema.org property names** — not arbitrary identifiers. Entity types (`Movie`, `TVSeries`, `VideoGame`, `ImageObject`, `PropertyValue`, etc.) are **schema.org classes**. Before adding any new field or type, check schema.org for an existing match and use its canonical name.

Read `DATA-FORMAT.md` before writing any code that reads or writes entity data.

## Documents

| File | Contents |
|------|---------|
| [`COMPONENTS.md`](COMPONENTS.md) | System architecture: backend, UI client, WebSocket communication |
| [`API.md`](API.md) | Phoenix Channels WebSocket API: topics, messages, schemas |
| [`PLAYBACK.md`](PLAYBACK.md) | MPV integration, watch progress model, resume algorithm |
| [`DATA-FORMAT.md`](DATA-FORMAT.md) | JSON schema for entity data (channel messages) and `config.json` |
| [`IMAGE-CACHING.md`](IMAGE-CACHING.md) | Image caching spec and directory conventions |
| [`TESTING.md`](TESTING.md) | Automated and manual testing guide for both components |

## Related Repositories

Component repositories are sibling directories locally and part of the [freedia-center](https://github.com/freedia-center) GitHub organization.

| Repository | Local path | Description |
|------------|------------|-------------|
| `freedia-center/user-interface` | `../user-interface` | Rust/GPUI rendering client (active) |
| `freedia-center/media-manager` | `../media-manager` | Backend: media library, playback, watch progress (active) |

## How to Use These Specs

- **Reading:** Use these documents to understand data contracts before touching any code that reads or writes entity data (channel messages), `config.json`, or `data/images/`.
- **Writing:** When a format decision changes, update the relevant spec here first, then update any affected component code and its `CLAUDE.md`.
- **Cross-references:** Specs reference each other by filename (e.g. `DATA-FORMAT.md` links to `IMAGE-CACHING.md`). Component `CLAUDE.md` files link here by GitHub URL.

### Reading the Specs

- **Before writing any code that touches the WebSocket API** (channels, messages, join replies), read `API.md` in full.
- **Before writing any playback, resume, or watch progress code**, read `PLAYBACK.md` in full.
- **Before writing any code that serializes entities** (for channel pushes), read `DATA-FORMAT.md` in full.
- **Before writing any image download or storage code**, read `IMAGE-CACHING.md` in full.
- **When adding a new entity field or type**, check [schema.org](https://schema.org) first. Use the canonical schema.org property name if one fits. Only introduce a non-schema.org field if there is no reasonable match, and document the reason in `DATA-FORMAT.md`.
- Field names (`name`, `datePublished`, `contentUrl`, `containsSeason`, etc.) and type names (`Movie`, `TVSeries`, `VideoGame`, `ImageObject`, `PropertyValue`) are schema.org identifiers — do not rename them.

### Working with the Specs

- **Specs are the authoritative contract.** The user-interface team (and future agents) learn what this app produces by reading the specs. When in doubt about a field name, message format, or behavior, the spec wins over the implementation.
- `API.md` specifies every channel topic, every client message, every server push, and every reply schema. The Rust UI implements its WebSocket client from this document — any deviation breaks the UI.
- `PLAYBACK.md` specifies the MPV launch flags, IPC protocol, progress persistence intervals, and resume algorithm. Both the backend implementation and the UI's playback state display derive from this spec.
- `DATA-FORMAT.md` specifies the JSON written by the media-manager. Follow field names and structure exactly.
- `IMAGE-CACHING.md` specifies the exact `contentUrl` path format (`images/{uuid}/{role}.{ext}`), image roles, and remote URL patterns for each source (TMDB, Steam). Follow these precisely — the user-interface uses them verbatim.
- `COMPONENTS.md` describes the overall system architecture and which component owns what. Refer to it when designing new features that affect the integration boundary.

### Keeping the Specs Updated

When a contract changes — a new channel message, a new field, a new entity type, a changed image role, a new API endpoint — **update the spec first**, then update the implementation:

1. Edit the relevant file in this repository (e.g. `API.md`).
2. If no existing spec covers the change, **create a new spec file** and add it to the Documents table above and to `COMPONENTS.md`.
3. Update the component implementation to match.
4. Note in `COMPONENTS.md` or the relevant spec if the change affects the other component, so its `CLAUDE.md` can be updated too.

Never let an implementation drift ahead of the spec. Never add a backend-to-UI contract (WebSocket message, file format, IPC protocol) without a spec documenting it.

Any .md documentation created for this project should be kept up to date.

---

## Version Control (Jujutsu)

All repositories in freedia-center use **JJ (Jujutsu)** — never use raw `git` commands.

- After completing a feature, set a change description: `jj describe -m "type: short description"`
- Use conventional commit style matching existing history (e.g. `feat:`, `fix:`, `refactor:`). Keep it concise and high-level.
- If follow-up amendments are needed for the same feature and the change hasn't been pushed to remote, amend the existing change rather than creating a new one.
- When starting an unrelated feature, create a new change with `jj new` and describe it accordingly.
- Adjust the description over time as the scope of the change becomes clearer.

## Plans

Implementation plans live in `plans/` (within each component repo) and are prefixed with a unique incrementing number (e.g. `001-animate-menu-bar.md`, `002-add-search.md`). The number ensures ordering and prevents naming collisions. Each plan must be **self-contained** — it must include all context required to execute fully in a new session, without relying on the conversation history from the session where the planning was done.

Always write the plan and save it before asking to execute. DO NOT AUTO EXECUTE AN IMPLEMENTATION PLAN AFTER SAVING THE PLAN. STOP AND REQUEST PERMISSION BEFORE EXECUTION.

Every implementation plan must include a **Smoke Tests** section identifying which stable contracts are affected and what tests to add (per the component's Testing Strategy). If the plan introduces no testable contracts, state that explicitly. Plans without a testing section are incomplete.

## Documentation Policy

- **Code structure IS documentation.** Ash resources define schemas; don't repeat field tables in markdown. `mix.exs` lists dependencies; don't duplicate that in docs.
- **`@moduledoc` / doc comments are for what a module does and why.** Algorithm descriptions, API details, and design rationale belong in code, not markdown.
- **CLAUDE.md is for agent behavior rules:** conventions, constraints, do/don't lists. Not architecture narrative.
- **Specifications are for cross-component contracts.** Anything one component needs to know about another goes here.
