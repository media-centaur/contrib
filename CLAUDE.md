# Freedia Center — Specifications

This repository (`freedia-center/specifications`) is the **authoritative source** for all cross-component specifications in the Freedia Center project. Every component repository references these documents.

## Data Model Foundation

All entity data in this project is grounded in [schema.org](https://schema.org) vocabulary, serialised as [JSON-LD](https://json-ld.org/). This is the most important design constraint in the system.

Entity field names (`name`, `datePublished`, `contentUrl`, `containsSeason`, `episodeNumber`, etc.) are **schema.org property names** — not arbitrary identifiers. Entity types (`Movie`, `TVSeries`, `VideoGame`, `ImageObject`, `PropertyValue`, etc.) are **schema.org classes**. Before adding any new field or type, check schema.org for an existing match and use its canonical name.

Read `DATA-FORMAT.md` before writing any code that reads or writes entity data.

## Documents

| File | Contents |
|------|---------|
| [`DATA-FORMAT.md`](DATA-FORMAT.md) | JSON schema for `media.json` and `config.json` |
| [`IMAGE-CACHING.md`](IMAGE-CACHING.md) | Image caching spec and directory conventions |
| [`COMPONENTS.md`](COMPONENTS.md) | How system components relate and integrate |

## Related Repositories

Component repositories are sibling directories locally and part of the [freedia-center](https://github.com/freedia-center) GitHub organization.

| Repository | Local path | Description |
|------------|------------|-------------|
| `freedia-center/user-interface` | `../user-interface` | Rust/GPUI media browser (active) |
| `freedia-center/manager` | `../manager` | Metadata scraper and image downloader (planned) |

## How to Use These Specs

- **Reading:** Use these documents to understand data contracts before touching any code that reads or writes `media.json`, `config.json`, or `data/images/`.
- **Writing:** When a format decision changes, update the relevant spec here first, then update any affected component code and its `CLAUDE.md`.
- **Cross-references:** Specs reference each other by filename (e.g. `DATA-FORMAT.md` links to `IMAGE-CACHING.md`). Component `CLAUDE.md` files link here by GitHub URL.
