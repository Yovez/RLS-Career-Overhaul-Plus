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
- **Landlord property + vehicle rentals:** Own Real Estate properties can be listed for rent (NPC offers, full rent negotiation chat, fixed/dynamic/upfront leases, locked garage while occupied). Marketplace Sell → Rentals (and Offers inbox) for vehicle rent-outs with daily-rate negotiation, typed asking rent/daily rate (market shown as reference + price guidance), prepaid 1–7 sim days, deposit, return damage never improves (totaled tanks integrity). Payouts use `payment.reward`/`pay` so bank auto-deposit/auto-pay apply. Mortgage payments continue while rented out.
- **Bank automation + Stock Market:** Personal Checking/Savings automation (auto-pay by spend category with wallet fallback and exclusive category claims, auto-deposit by income bucket/floor, balance sweep/top-up rules, checking **auto-invest** into broker cash or selected tickers) on the bank account screen. New Finance phone app **Stock Market** (Markets / Portfolio / Broker): curated org tickers priced from `globalEconomy` sector indices each tick; dividends (manual reinvest/wallet/checking; broker → holding pool); manual trades free; managed broker is dump-and-forget buy-and-hold (balanced allocator, no auto-sell, 5% fee only on withdrawal sells) with amount withdraw + fee preview / withdraw all. Stock buys/broker deposits honor bank auto-pay category `stocks`.
- **Marketplace listing alerts:** Watch a body style (type), brand, or model from the Marketplace Alerts tab (or vehicle detail). When a matching private listing appears, the Marketplace app notifies you; tapping opens that listing in the phone app. Deep links use flat route fields + model-key resolve (shop ids are reused); adding a watch only scans that watch so older brand/type alerts do not re-fire.
- **Phone Marketplace filter / sort:** Buy tab now has Filter (affordable, negotiable, under market, price / year / miles, make chips) and Sort (price, year, mileage, deal quality, name, distance) like Real Estate.
- **Broker empty board while markets show hundreds:** Facility scope from a prior open (e.g. post-delivery) stuck in the store and filtered the list to one pickup with no loads, while market tiles still counted the full board. Scope now clears on a normal open / Markets tab / Reset filters, with a clearer All pickups control.
- **Trailers ignore garage car slots:** Owned trailers stay in your garage inventory but no longer consume capacity, so a 1-car starter garage can hold a pickup plus a trailer. Purchase / delivery slot checks treat trailers the same way.
- **Route home (Real Estate):** Toolbar one-tap GPS to your primary owned garage on this map; if you own several and have no primary yet, a picker sets primary and routes. **Choose…** reopens the picker.
- **Broker locked tab level:** Locked loads showed Logistics level 1 because access used the short domain path `logistics` instead of `careerSkills-logistics` (where real XP lives). Progress bar now uses have/need toward the unlock level.
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
