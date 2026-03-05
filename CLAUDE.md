# Contrib — Agent Instructions

## Plans

Implementation plans live in `plans/` (within each component repo) and are prefixed with a unique incrementing number (e.g. `001-animate-menu-bar.md`, `002-add-search.md`). The number ensures ordering and prevents naming collisions. Each plan must be **self-contained** — it must include all context required to execute fully in a new session, without relying on the conversation history from the session where the planning was done.

Always write the plan and save it before asking to execute. DO NOT AUTO EXECUTE AN IMPLEMENTATION PLAN AFTER SAVING THE PLAN. STOP AND REQUEST PERMISSION BEFORE EXECUTION.

Every implementation plan must include a **Smoke Tests** section identifying which stable contracts are affected and what tests to add (per the component's Testing Strategy). If the plan introduces no testable contracts, state that explicitly. Plans without a testing section are incomplete.

## Documentation Policy

- **Code structure IS documentation.** Ash resources define schemas; don't repeat field tables in markdown. `mix.exs` lists dependencies; don't duplicate that in docs.
- **`@moduledoc` / doc comments are for what a module does and why.** Algorithm descriptions, API details, and design rationale belong in code, not markdown.
- **CLAUDE.md is for agent behavior rules:** conventions, constraints, do/don't lists. Not architecture narrative.
- **Specifications are for cross-component contracts.** Anything one component needs to know about another goes in `backend/specs/`.
- **Cross-repo links must use full GitHub URLs.** Each component is a separate GitHub repo. Relative `../` links break on GitHub's web UI. Use `https://github.com/media-centaur/<repo>/blob/main/<path>` (files) or `.../tree/main/<path>` (directories).
