# Systems catalog

Where major player-facing systems live. Paths are relative to repo root unless noted. GE = `lua/ge/extensions/overhaul/`.

## Career core

| System | GE / Lua | Data / UI |
|--------|----------|-----------|
| Career host | `career/career.lua` | Vue career modules, pause/entry hosts |
| Save / slots | `career/saveSystem.lua`, `career/start/` | `gameplay/overhaul/save/` |
| Save migration | `career/saveMigration.lua` | import JSON under `save/` |
| Starting modes | `career/startingModes/` | `gameplay/overhaul/startingModes/` |
| Challenge modes | `career/challengeModes*` | capabilities e.g. `challengeLoans.json` |
| Permissions / guide | `career/permissions.lua`, `career/guide/` | phone guide tile |
| Progression / milestones / skills | `career/progression/` | `domains/careerSkills/`, locales milestones |

## Economy & finance

Glossary: **Payment Domain**, **Wallet**, **Account**, **Spendable** — see root `GLOSSARY.md`. Payment Domain is a Plus **Claimed Domain** (Plus Wins / Cherry-pick-track; do not bulk-merge Upstream RLS over it).

| System | GE | Notes |
|--------|-----|-------|
| **Payment Domain** (**Claimed Domain**, **fork**) | `career/economy/payment.lua` (+ `payment/`) | Plus-owned affordability and debit facade: `canPay`, `getSpendableMoney`, `pay`, `reward` / `payout`. Bank automation is a **feature of this domain**, not a separate Claimed Domain. Employment held-wage holders stay Glue until Employment is claimed. |
| **Wallet** | `career/economy/playerAttributes.lua` | Cash-on-hand (`money` attribute); save `career/playerAttributes.json`. Not a bank Account. Deposit capacity and cash-on-hand UI must use Wallet, never Spendable. |
| **Account** (bank) | `career/economy/bank.lua` | Checking/savings balances distinct from Wallet; Vue bank modals; save `career/rls_career/bank.json` (Accounts, pending transfers, transactions, automation). |
| **Spendable** (derived) | `payment.getSpendableMoney` / `bank.getSpendableMoney` | Affordability for a purchase reason: Wallet + claimed auto-pay checking for that reason’s spend bucket. **Never persisted** as a third balance. |
| Bank automation (Payment Domain feature, **fork**) | `career/economy/bank/automation.lua` | Auto-pay by spend bucket (checking then Wallet), auto-deposit, balance sweeps, checking auto-invest (broker or tickers); UI on `PhoneBankAccount` / `BankAutomationPanel.vue`. Embedded under `bank.json` → `automation`. |
| Stock market (**fork**) | `career/economy/stockMarket.lua` | Phone Stock Market; sector quotes + dividends; manual 0%; broker buy-only (balanced) with 5% sell fee on withdraw; save `economy.stockMarket`. Buys/deposits call Payment Domain (`stocks` bucket). |
| Loans / credit | `career/economy/loans.lua`, `credit.lua` | Call Payment Domain for money movement; not redesigned by the Payment claim. |
| Global economy / heat | `globalEconomy.lua`, `activityHeat.lua` | Hooks stock quotes each economy tick |
| Difficulty / XP / economy adjusters | `difficultyMode.lua`, `*AdjusterPolicy.lua`, `economyAdjuster.lua` | |
| Player attributes / skills XP | `playerAttributes*` | Includes Wallet; other attributes unchanged by Payment Domain |
| Cheats / pause time | `cheats.lua`, `pauseTime.lua` | |
| Ledger / finance helpers | `lib/ledger/`, `lib/finance/` | UI wallet tile + history (Wallet ledger truth, not Spendable) |
| Best-effort Import / money conservation | `shell/saveImport/` (`prepare.lua` `sumTotals` / `assertConserved`) | Import conserves Wallet + Accounts + pending transfers + known employment escrow (+ savings interest in the import check). Offline verify: `scripts/payment-save-conservation/`. |

Gameplay numbers: `gameplay/overhaul/economy/` (incl. `stocks.json`), `finance/`.

## Work, logistics, deliveries

| System | Location | Notes |
|--------|----------|-------|
| Employment (shifts) | `career/work/employment*` | Kinds: parcel, materials, trailer, vehicle, police, repo, roleplay, … |
| Equipment rental | `career/work/equipmentRental.lua` | |
| Job broker / cargo screen | `career/logistics/broker*`, `cargoScreen*` | phone logistics apps |
| Cargo generation / progress | `career/logistics/generator*`, `progress*` | |
| Material / owner-op contracts | `materialContractManager*`, `ownerOpContracts*` | |
| Loaners / vehicle transfer / tasks | `loanerVehicles*`, `vehicleTransfer*`, `vehicleTasks*` | |
| Delivery activities | `gameplay/overhaul/delivery/`, `activities/cargoDelivery.json` etc. | |
| Job Broker route / GPS (**fork**) | `career/logistics/broker.lua` (`autoRoute`, `pruneStaleStops`, preference `autoApplyGps`); UI Route tab in `BrokerRoutePlan.vue` | Skips pickup waypoints once loads are collected; any logistics collect (parcel/trailer/cars/material/…) auto-adds delivery stops, merges same locations, sorts, and sets GPS |
| Job Broker post-delivery open (**fork**) | `tryOpenBrokerAfterDelivery` + `progress.getLastDropOffFacId`; preference `autoOpenBrokerOnDelivery` | After rewards popup, opens Job Broker scoped to the drop-off facility when any unlocked loads are available |
| Job Broker delivery-type filters (**fork**) | `phoneBrokerStore` `mods` filter + `BrokerFilters.vue` chips | Filter offers by timed / post / precious / large / hazardous / fluid / dry bulk / supplies / plain |

Standalone job packages under `jobs/`:

| Job | Path |
|-----|------|
| Bus | `jobs/bus/` |
| Beam Eats | `jobs/beamEats/` |
| Ambulance / paramedic | `jobs/ambulance/` |
| Cleanup club | `jobs/cleanupClub/` |
| Facility work | `jobs/facilityWork/` |
| Mining haul | `jobs/miningHaul/` |
| Quarry | `jobs/quarry/` |
| Card games | `jobs/cardGames/` |

Taxi / repo / police / offroad recovery also have gameplay folders (`taxi/`, `repo/`, `police/`, `offroadRecovery/`) and related career/work or integration code. Phone tiles under `ui/entrypoints/.../tiles/` mirror many of these.

## Businesses

| Business | GE path |
|----------|---------|
| Manager / tabs / skill tree | `career/business/manager.lua`, `tabRegistry.lua`, `skillTree.lua` |
| Business computer | `career/business/computer*` |
| Engine shop | `career/business/engineShop*` |
| Tuning shop | `career/business/tuningShop/` |
| Racing team | `career/business/racingTeam/` |
| Passive business | `career/business/passive*` |
| Fleet | `career/business/fleet*` |
| Part customization / inventory | `partCustomization*`, `partInventory*` |
| Vehicle tuning (business) | `vehicleTuning.lua` |

Vue: `.../career/components/businessComputer/` (+ type-specific tabs).

## Garage, property, market

| System | GE |
|--------|-----|
| Garage manager / inventory / computer | `career/garage/*` |
| Property / mortgage / rentals / real estate | `career/garage/property*` |
| Landlord property rentals (**fork**) | `property/propertyLandlord.lua` + Real Estate Listings UI | List owned garages for rent; NPC tenant offers/leases; capacity/primary/sale locks |
| Studio rentals | `career/garage/studioRentals*` |
| Fast / quick travel | `fastTravel`, `quickTravel` |
| Dealership / shopping / stock | `career/market/vehicleShopping*` |
| Marketplace | `career/market/marketplace*` |
| Vehicle rentals (**fork**) | `market/vehicleRentals.lua` + `PhoneMarketplaceRentals.vue` | Rent out owned vehicles from Marketplace Sell → Rentals; typed daily rate + guidance; prepaid terms + return damage |
| Phone Marketplace filter / sort (**fork**) | `usePhoneMarketplaceFilters.js` + `PhoneMarketplace.vue` | Buy-tab Filter / Sort for private listings (price, year, miles, make, deal quality, etc.) |
| Marketplace listing watches (**fork**) | `marketplace/listingWatches.lua` + `PhoneMarketplaceWatches.vue` | Persist type/brand/model watches; notify `marketplace.listingWatch` and deep-link to `phone-marketplace-vehicle` |
| Auction | `career/market/auction*` |
| Test drive / valuation | `testDrive*`, `valueCalculator*` |

## Parts, maintenance, repair

| System | GE / vehicle |
|--------|----------------|
| Part shopping / engines / packages | `career/parts/` |
| Dyno session | `career/parts/dyno/` + vehicle `overhaulDyno*` |
| Tuning / performance | `career/parts/tuning*`, `vehiclePerformance*` |
| Maintenance / fuel / tires (career) | `career/maintenance/` |
| Vehicle maintenance / failures | `lua/vehicle/overhaul/maintenance/` |
| Tires (incl. third-party integration) | `lua/vehicle/extensions/overhaulTires.lua` |
| Insurance / roadside repair | `career/repair/insurance*`, `roadsideRepair*` |
| OBD | vehicle `overhaulObdScanner` / `overhaul/obd/` |

## Events & racing

| System | Path |
|--------|------|
| FRE (freeroam events) host / race / offers | `events/fre/`, `events/freConfig.lua` |
| Sanctioned racing | `events/fre/sanctionedRacing*` |
| Dakar | `events/dakar*` |
| Derby | `events/derby/` |
| Burnout | `events/burnout.lua` |
| Circuit / competitive track flow | `circuitRaceAi.lua`, `competitiveTrackFlow*` |
| AI racers | `events/aiRacers*` |
| Checkpoints / assets | `checkpointManager.lua`, `activeAssets.lua` |
| Event host session | `events/host/` |

HUD: `ui/modModules/overhaulFreeroamRaceHud`, `overhaulFreSummary`. Level race data under `levels/rls_west_coast/race_data*` / dragstrips / competitiveRace.

## Social / side activities

| System | Path |
|--------|------|
| Car meets | `career/carmeets/` |
| Presence activities | `gameplay/overhaul/presenceActivities/` |
| Sponsored services | `gameplay/overhaul/sponsoredServices/` |

## Phone & meta UI

| Piece | Path |
|-------|------|
| Phone shell | `phone/phone.lua` |
| Apps (FRE, logistics, minimap, real estate, time, …) | `phone/apps/` |
| Music player | `phone/musicPlayer*` + `ui/modModules/rlsMusicPlayer` |
| Travel journal | `phone/travelJournal.lua` |
| Vue phone catalog / shell state | `ui/ui-vue/.../career/utils/phoneAppCatalog.js`, `phoneShellState.js` |

## World & maps

| Piece | Path |
|-------|------|
| Maps / level proxy | `world/maps.lua`, `levelProxy.lua` |
| Facilities | `world/facilities*` |
| Weather / sleep / fuel | `world/weather*`, `sleep.lua`, `fuel/` |
| Organizations | `world/organizations.lua` |
| Dynamic routes | `world/dynamicRoutes.lua` |
| Clear levels helper | `world/clearLevels.lua` |

Shipped levels:

- `levels/rls_west_coast/`: primary Overhaul map (terrain + sites + overhaul data)
- `levels/west_coast_usa/overhaul/`: overlays for stock WCU
- `levels/garage_v2/overhaul/`: garage level hooks

## Avatar & vehicle tooling

| Piece | Path |
|-------|------|
| Walk enter vehicle | `avatar/walkEnterVehicle*` |
| Unicycle camera | `avatar/unicycleCamera.lua` |
| Overhaul AI | `lua/vehicle/extensions/overhaulAi.lua` + `lua/vehicle/overhaul/ai/` |
| Yankem | vehicle `overhaulYankem` + `ui/modModules/rlsYankem` |
| Cargo containers / damage / fuel | matching `lua/vehicle/extensions/overhaul*` |

## Dev / tester

| Piece | Path |
|-------|------|
| Dev console / editor routes / FRE editor | `dev/` |
| Tester menu | owner `overhaul_dev_testerMenu` + `ui/ui-vue/mods/rls_tester_menu/` |
| Dev key / capabilities | `capabilities/devKey.json`, `developerSettings.json` |

## Integration layer

`integration/`: bridges to stock BeamNG services, owned services, taxi patches, vanilla service wrappers. Touch carefully; easy to break stock coexistence.
