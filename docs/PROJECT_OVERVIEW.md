# Project overview

**RLS Career Overhaul Plus** is a plus fork of **RLS Career Overhaul**: BeamNG.drive career mode with saves, economy, jobs, businesses, events, phone apps, and the **RLS West Coast** map, plus local QoL and systems work on top of upstream.

| Item | Value |
|------|--------|
| Upstream (RLS) | https://github.com/RLS-Modding/rls_career_overhaul |
| This fork (Plus) | https://github.com/Yovez/rls_career_overhaul_plus |
| Public version (shipped base) | **2.8.0** (`gameplay/overhaul/version.json`) |
| Target game | BeamNG.drive **0.40.x** (`SUPPORTED_GAME_MINOR_VERSION = 40`) |
| Approx. tree size | ~4.3 GB, ~5,095 files |

## Stack (what you edit)

| Layer | Tech | Role |
|-------|------|------|
| Game extensions (GE) | **Lua** under `lua/ge/extensions/overhaul/` | Career logic, jobs, economy, events, phone, world |
| Shared Lua | `lua/common/overhaul/` | Code usable from GE and vehicle |
| Vehicle | **Lua** under `lua/vehicle/` | Per-vehicle controllers, AI, maintenance, tires, dyno, cargo |
| Data / content | **JSON** under `gameplay/overhaul/` | Manifests, activities, capabilities, economy tables, sites wiring |
| Levels | BeamNG level packs under `levels/` | Map + site JSON (pois, routes, facilities) |
| Vehicles / parts | **JBeam**, `.pc`, meshes, `info_*.json` under `vehicles/` | Career configs, loaners, junkers, cargo props |
| UI (primary) | **Vue 3** under `ui/ui-vue/mods/rls_career_overhaul/` | Career screens, phone, computers, overlays |
| UI (HUD / legacy) | Angular-ish **modModules** + small `overhaulAngular` helpers | Race HUD, dyno HUD, manager, music, Yankem |
| Entry | `scripts/rls_career_overhaul/modScript.lua` | Loads the shell extension manager |
| i18n | JSON under `locales/translations/` | en-US (+ some de_DE cards) |
| Audio | `music/overhaul/` | In-mod music player tracks |

There is **no separate Node build step** in-repo for shipping: BeamNG loads the tree as a VFS mod (release ZIP or unpacked folder in the user `mods` directory). Vue files are consumed by the game’s ui-vue runtime.

## File-type mix (rough)

| Extension | Count (order of magnitude) | Typical use |
|-----------|----------------------------|-------------|
| `.json` | ~1.6k | Manifests, sites, configs, translations, vehicle info |
| `.jbeam` | ~1k | Vehicle / part physics definitions |
| `.lua` | ~800 | Game + vehicle logic |
| `.vue` / `.js` | ~300 / ~200 | Career UI |
| Images / meshes / audio | remainder | Art, levels, vehicles, music |

## What “exists” as product features

High level (see [SYSTEMS_CATALOG.md](SYSTEMS_CATALOG.md) for paths):

- **Career shell:** own career mode, profiles, save/migration, pause home, wallet / logbook
- **Work:** employment shifts, job broker, deliveries (parcel / materials / trailer / vehicle), bus, taxi, repo, police, ambulance, quarry, mining, facility work, Beam Eats, cleanup
- **Businesses:** engine shop, tuning shop, racing team, passive businesses, fleet, skill tree, workshop computer
- **Market:** dealerships, negotiation, marketplace, auctions, loans / credit / bank
- **Garage / property:** inventory, storage, real estate, rentals, fast travel
- **Parts / maintenance:** shopping, engines, dyno, tires, OBD, insurance / roadside repair
- **Events:** freeroam racing (FRE), Dakar, derby, burnout, circuit / competitive track flow, car meets
- **World:** RLS West Coast map, facilities, weather, organizations, dynamic routes
- **Phone:** app shell for logistics, events, real estate, music, journal, etc.

## Licensing (fork-relevant)

- Original RLS-scoped source: **AGPL-3.0-only** + BeamNG additional permission (`licenses/RLS-AGPL-SCOPE.md`)
- BeamNG-derived code: stays **bCDDL 1.1**
- Bundled third parties: tire thermals, forklift assets, fonts, etc. (`THIRD_PARTY_NOTICES.md`)

Preserve notices when editing; do not relicense bCDDL files as AGPL-only.
