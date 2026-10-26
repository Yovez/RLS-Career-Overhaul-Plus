# Directory map

Top-level layout of the mod tree (what belongs where).

```
.
├── art/                  # Shared 3D shapes / overhaul props
├── docs/                 # This fork’s internal documentation (not upstream)
├── gameplay/overhaul/    # JSON content, manifests, activities, economy tables
├── levels/               # Map packs + site/career JSON
├── licenses/             # Full license texts + scope lists
├── locales/translations/ # i18n JSON cards
├── lua/
│   ├── common/overhaul/  # Shared Lua (GE + vehicle)
│   ├── ge/extensions/    # Game-engine extensions (career logic)
│   │   ├── core/input/actions/  # Input action JSON (if present)
│   │   └── overhaul/     # Almost all Overhaul GE code
│   └── vehicle/          # Vehicle VM: controllers, extensions, overhaul/
├── music/overhaul/       # Music player libraries
├── scripts/rls_career_overhaul/
│   └── modScript.lua     # Mod entry: load shell
├── settings/             # Input maps, UI app layout overrides
├── ui/
│   ├── entrypoints/      # Main-menu / phone tile assets
│   ├── images/           # Mod images
│   ├── modModules/       # HUD / manager Angular-style modules
│   ├── modules/          # Apps, Angular helpers, whatsnew
│   └── ui-vue/mods/      # Primary Vue career UI
└── vehicles/             # Career vehicle configs, JBeam, cargo props
```

Root policy / legal (upstream-owned; keep when syncing):

- `README.md`, `CONTRIBUTING.md`, `CREDITS.md`, `SECURITY.md`
- `LICENSE`, `LICENSING.md`, `THIRD_PARTY_NOTICES.md`
- `.github/` — issue / PR templates

## `gameplay/overhaul/` (content)

Declarative data consumed by Lua. Prefer changing **numbers and flags** here before rewriting systems.

Notable subfolders: `activities`, `business`, `capabilities`, `career` (owners + modules), `computer`, `delivery`, `domains`, `economy`, `events`, `facilities`, `finance`, `insurance`, `jobs`, `loaners`, `logistics`, `maps`, `market`, `phone`, `police`, `property`, `repair`, `save`, `settings`, `taxi`, `ui`, `version.json`.

## `lua/ge/extensions/overhaul/` (logic)

See [ARCHITECTURE.md](ARCHITECTURE.md). Rough size: **~760+ Lua files** under GE overhaul, dominated by `career/` then `lib/`, `jobs/`, `events/`.

Extension naming: filesystem path with `/` → `_` and `_` → `__`.

Example: `overhaul/career/economy/bank.lua` → extension `overhaul_career_economy_bank`.

## `ui/ui-vue/mods/rls_career_overhaul/` (UI)

| Path | Role |
|------|------|
| `index.js` | Mod entry / overlay mount |
| `RlsCareerOverlays.vue` / `LazyOverlay.vue` | Overlay hosts |
| `overhaul/registerRoutes.js` | Vue routes |
| `overhaul/modules/career/` | Most screens (views, components, stores, utils) |
| `overhaul/modules/{pause,refuel,vehicleConfig,activitystart}/` | Focused flows |

Sister mod: `ui/ui-vue/mods/rls_tester_menu/` (dev / tester UI).

## `levels/`

| Level | Role |
|-------|------|
| `rls_west_coast/` | Full Overhaul map (terrain `.ter`, sites, facilities, race data, overhaul/) |
| `west_coast_usa/overhaul/` | Overhaul data layered on stock WCU |
| `garage_v2/overhaul/` | Garage map hooks |

Site files (`*.sites.json`) place activities, businesses, police, travel, etc. on the map.

## `vehicles/`

~50 vehicle folders. Mostly **configs** (`info_*.json`, `.pc`) and **JBeam** for career variants (loaners, junk, repo, EMT, cargo, rollers), plus props (`TPUForkableLoads`, trailers, dyno under `common/`). Not a full replacement car pack.

## `settings/`

Custom input maps (`keyboard_rls_career_overhaul.json`, Yankem device maps) and UI app layout originals.

## What is *not* in this repo

- BeamNG engine / stock game files
- Player saves (live under the BeamNG user folder)
- Upstream **private development** repo (maintainers mirror public PRs there; see `CONTRIBUTING.md`)
- A Node/npm package for shipping Vue (game serves / compiles via ui-vue pipeline)
