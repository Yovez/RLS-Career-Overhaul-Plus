# Plus changelog

Divergences in **RLS Career Overhaul Plus** (`Yovez/RLS-Career-Overhaul-Plus`) from upstream RLS Career Overhaul. Newest first.

## Unreleased

### Install / workflow
- Prefer **unpacked** mod at `E:\BeamMP\current\mods\unpacked\rls_career_overhaul` (junction to this repo). Disable competing Overhaul zips; no re-zip for every Lua/UI tweak.
- Keep this file + `docs/` fork-local when merging upstream.

### Upstream cherry-picks
- **#496:** Nil-safe vehicle performance after loaner/police shifts (big map / pause crash). Cash jobs require cash-capable loaners; bank-truck configs declare cash capacity.
- **#495:** Taxi passenger-leg timing uses simulation `dt` (`rideElapsed`) so pause/menu time does not tank pace bonuses. Includes owned-car wheel data display fix from the same PR.
- Skipped **#428** (vanilla `gameplay/taxi.lua`); Overhaul taxi path is covered by #495.

### Local fixes
- **Phone applies parking brake:** Opening the career phone sets the player vehicle parking brake when the vehicle exposes one (skipped while walking).
- **Timed route after mid-trip collect:** `validStopOrder` treated every in-transit delivery as invalid once pickup pins were pruned, so `optimizeStops` never applied and GPS kept the old untimed order after picking up timed loads. Delivery stops with no remaining pickup pin are treated as already collected.
- **Smarter auto-route:** Delivery pins unblock when any job on them is loaded (merged stops); pickups get a short distance bias so a ready drop across the street beats another pickup farther away. Timed loads are always routed before non-timed ones; within timed stops, nearer-to-late deadlines win via a distance/urgency score.
- **Resume route on load:** After cargo/trailer restore settles, Job Broker rebuilds deliveries if needed and auto-applies GPS (same path as post-collect routing).
- **Hitch restore:** Longer coupler wait + second hitch attempt on session reload so trailers are less likely to load unattached.
- **#468 loaner cut stacking:** Parcel and vehicle delivery breakdowns apply only the largest loaner money cut when multiple orgs supplied gear; each org still gets reputation.
- **#489 gamepad phone focus (partial, 2.8.0):** Homescreen / dock / search icons accept A via `ok.asMouse`; focus first icon when opening the phone on a controller. Full 2.7.x patch script not applied wholesale (2.8.0 already has scoped phone nav).
- **Trailer deliver cleanup:** On trailer drop-off, force-uncouple (coupler break + trailerReg clear), park on the bay if the hitch sticks, then delete the loaner so it does not stay attached to the truck.
- **Job Broker routing:** Skip collected pickups; auto-add/sort/GPS deliveries on any logistics collect; merge same-location stops; optional auto-open broker after delivery with type filters.

## Notes
- Upstream issue/PR numbers are references only; patches may differ from eventual upstream merges.
- After `git fetch upstream`, prefer cherry-pick of small fixes over waiting for the next release ZIP.
