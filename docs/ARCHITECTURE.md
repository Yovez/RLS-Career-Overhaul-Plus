# Architecture

How the mod boots and how layers talk to each other.

## Boot sequence

```
BeamNG loads mod
  → scripts/rls_career_overhaul/modScript.lua
      registers input category "RLS Career Overhaul"
      deferred job → extensions.load("overhaul_shell_extensionManager")
  → lua/ge/extensions/overhaul/shell/extensionManager.lua
      discovers shell owners from gameplay/overhaul/career/owners/*.json
      loads scopes (careerCore, services, routes, late, …)
      on career activate → career modules from gameplay/overhaul/career/modules/*.json
  → UI: ui/ui-vue/mods/rls_career_overhaul/index.js
      mounts overlays into stock Vue app, registers routes / phone apps / computer functions
```

Entry script is intentionally thin. All real ownership of load order, unload, and vehicle hooks lives in **`overhaul_shell_extensionManager`**.

Game version gate: minor version **40** (0.40.x). Other minors log unsupported and may refuse career start.

## Lua layers

### 1. Game Engine (GE) extensions: `lua/ge/extensions/overhaul/`

BeamNG extension modules (path → extension name: `overhaul/career/economy/bank` → `overhaul_career_economy_bank`).

| Area | Path | Role |
|------|------|------|
| Shell | `shell/` | Startup, scopes, input actions, teardown |
| Career | `career/` | Economy, garage, logistics, market, businesses, work, save |
| Jobs | `jobs/` | Standalone job activities (bus, quarry, Beam Eats, …) |
| Events | `events/` | FRE, Dakar, derby, burnout, AI racers, track flow |
| Phone | `phone/` | Phone shell + app backends |
| World | `world/` | Maps, facilities, weather, sleep, fuel |
| Avatar | `avatar/` | Walk / enter vehicle, unicycle camera |
| Integration | `integration/` | Patches / bridges to stock or owned services |
| Lib | `lib/` | Shared helpers (not usually career “modules” themselves) |
| UI / vehicles / dev | `ui/`, `vehicles/`, `dev/` | Bridges and tools |

**Lib** (`lib/`) is large (~150 files): activity framework, ledger/finance, logistics helpers, save helpers, platform manifests, lifecycle scopes. Prefer fixing shared behavior here when multiple owners need it.

### 2. Common: `lua/common/overhaul/`

Small shared set (units, tire model, vehicle roles, exact paths, maintenance part categories). Safe to `require` from GE or vehicle.

### 3. Vehicle: `lua/vehicle/`

Runs in the vehicle Lua VM:

- `extensions/overhaul*.lua`: damage, fuel, tires, dyno, cargo, Yankem, maintenance, AI swap helpers
- `overhaul/`: AI planning, maintenance managers, OBD, player controller seam
- `controller/`: dyno ramp / player controller

GE can push vehicle extensions when career / Overhaul is active (`applyCareerVehicleExtensions` on the shell).

## Manifest-driven loading

Two JSON registries under `gameplay/overhaul/career/`:

| Registry | Count (approx.) | Purpose |
|----------|-----------------|---------|
| `owners/*.json` | ~138 | Shell **owners**: which GE module loads in which **scope**, unload policy, optional demand-load / save files |
| `modules/*.json` | ~139 | Career **modules**: ordered list loaded when career is active |

Scopes (shell policy, from `lib/career/manifest.lua`) include among others:

`careerCore`, `testerMenu`, `editor`, `bootManual`, `routes`, `shell`, `services`, `vehicleTools`, `guards`, `settings`, `late`, `world`, `freeroamEvents`, `careerWorld`, `owned`, `children`

Owners declare `scopes: [{ id, order }]`. The extension manager loads each scope’s members in order. Demand scopes load when something needs them (world, FRE, editor, …).

**Rule of thumb when adding a new GE feature:**

1. Implement `lua/ge/extensions/overhaul/.../yourThing.lua`
2. Add an **owner** JSON if it must join the shell
3. Add a **module** JSON if it is a career module (ordered with the rest)
4. Add gameplay JSON under `gameplay/overhaul/` for activities / capabilities / domain data as needed
5. Wire UI in `ui/ui-vue/mods/rls_career_overhaul/` if the player sees screens

## Gameplay data: `gameplay/overhaul/`

Content and policy, not executable Lua. Important buckets:

| Folder | Role |
|--------|------|
| `career/` | Module/owner manifests, career content tables |
| `activities/` | Activity definitions (employment, FRE, bus, …) |
| `capabilities/` | Feature capability flags / session schemas |
| `domains/` | Domain data (e.g. skills, logistics) |
| `economy/`, `finance/`, `insurance/` | Numbers and policies |
| `phone/`, `ui/` | Phone / UI-facing data |
| `save/` | Import paths, aliases for migration |
| `facilities/`, `maps/`, `world/` | World wiring |
| Per-job folders | `bus/`, `taxi/`, `police/`, `delivery/`, … |

Levels add **site JSON** (`*.sites.json`, `careerLocations.json`, routes) under `levels/<map>/`.

## UI architecture

### Primary: Vue mod entry

`ui/ui-vue/mods/rls_career_overhaul/index.js`

- Official BeamNG ui-vue **mod entry** (stock `App.vue` overrides are unreliable on 0.39+)
- Waits for `window.bngVue` / router, mounts overlay host
- Registers Overhaul routes, phone apps, computer functions, business types
- Starts career entry card + pause card hosts

Vue tree (~326 `.vue` files) under:

```
ui/ui-vue/mods/rls_career_overhaul/overhaul/modules/
  activitystart/   career/   pause/   refuel/   vehicleConfig/
```

Career UI is the bulk: bank, business computer, cargo, house, marketplace, phone, profiles, wallet, etc. Bridge to Lua is via BeamNG’s Vue/Lua bridge (`useBridge`, GE extension APIs).

### Secondary: modModules (HUD / tools)

`ui/modModules/`: celebration popup, dyno HUD, freeroam race HUD, FRE summary, overhaul manager, music player, Yankem.

### Legacy / helpers

- `ui/modules/overhaulAngular/`: small shared Angular helpers
- `ui/modules/apps/`: in-game apps (tacho, tire wear, music, top-left)
- `ui/modules/whatsnew/`: release splash assets
- `ui/entrypoints/main/rls_career_overhaul/`: phone tile art / card-game assets

## Cross-cutting patterns

- **Activities**: jobs/events often implement an activity interface + `gameplay/overhaul/activities/*.json`
- **Employment**: shift work funnels through `career/work/employment*` with kind-specific modules
- **Payment Domain / ledger**: Plus Claimed Domain facade in `career/economy/payment.lua` (Wallet + Accounts stored; Spendable derived). Bank automation is a feature of Payment Domain. Helpers under `lib/ledger` / `lib/finance`.
- **Save**: `career/saveSystem.lua`, `saveMigration.lua`, plus `gameplay/overhaul/save/`
- **Optional / soft load**: shell uses `optional()` wrappers so missing pieces do not hard-crash startup

## Mental model for fixes

| Symptom domain | Start looking in |
|----------------|------------------|
| Mod won’t start / wrong game version | `modScript.lua`, `shell/extensionManager.lua` |
| Career load order / missing feature | `career/owners`, `career/modules`, owner scopes |
| Money / XP / difficulty | `career/economy/` (Payment Domain: `payment.lua`, `bank.lua`, Wallet in `playerAttributes*`), `gameplay/overhaul/economy/` |
| A specific job loop | `jobs/<name>/` + matching `activities/*.json` + level sites |
| Phone app | `phone/` + Vue phone catalog under career utils |
| UI layout / screen bug | `ui/ui-vue/mods/rls_career_overhaul/` |
| Vehicle damage / tires / dyno feel | `lua/vehicle/extensions/`, `lua/vehicle/overhaul/` |
| Map POI / facility missing | `levels/<map>/*.sites.json`, `world/facilities` |
