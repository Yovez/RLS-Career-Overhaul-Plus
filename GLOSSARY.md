# RLS Career Overhaul Plus

Domain language for the Plus career/life-sim fork of RLS Career Overhaul.

## Product

**Plus**:
The independent career/life-sim product built from this repo (`Yovez/RLS-Career-Overhaul-Plus`).
_Avoid_: fork (as identity), mod pack, RLS (when meaning this product)

**Upstream RLS**:
The public RLS Career Overhaul project and its releases (`RLS-Modding/rls_career_overhaul`).
_Avoid_: vanilla, stock Overhaul, original (ambiguous)

**Life Sim**:
Plus’s north-star product: day-to-day money, housing, work, and vehicles feel coherent as one career life.
_Avoid_: full simulator (vague), RLS parity, feature complete

## Upstream relationship

**Cherry-pick-track**:
Plus’s sync policy: read Upstream RLS changes and port only what fits Plus design; do not bulk-merge release branches as the default.
_Avoid_: merge-track, periodically merge upstream, stay in sync (as a goal)

**Glue**:
BeamNG/RLS substrate Plus may keep copying: save plumbing, UI shell, hooks, org/facility wiring — not gameplay loops Plus cares about.
_Avoid_: base systems, infrastructure (too broad), framework

**Claimed Domain**:
A gameplay area Plus has redesigned for Life Sim intent (e.g. stocks/broker, landlord/rentals). Copying Upstream RLS patterns there is temporary debt, not the end state.
_Avoid_: Plus feature, custom system (vague), override

**Must-port**:
Upstream RLS changes that exist mainly so the mod runs on a new BeamNG version; Plus ports these as Glue even under Cherry-pick-track.
_Avoid_: forced merge, version sync (as bulk merge)

**Best-effort Import**:
Plus will try to load an Upstream RLS career save; Claimed Domains may extend or rewrite that save data afterward. Not a promise of schema lockstep.
_Avoid_: save compatibility (as hard guarantee), migration-free, drop-in

## Economy

**Payment Domain**:
The next Claimed Domain: Plus-owned model of player money movement (what can pay for what, and in what order). Bank automation (auto-pay, auto-deposit, sweeps) is a feature of this domain, not a separate Claimed Domain. Employment stays Glue until after Payment Domain and Housing Domain.
_Avoid_: bank (the Upstream RLS module), automation alone, spendable (as the whole domain name)

**Wallet**:
Cash-on-hand held as the player money attribute; not a bank account. In payloads we control, prefer `walletMoney`.
_Avoid_: balance (alone), cash (ambiguous with checking), spendable, playerMoney (as a Wallet field name)

**Account**:
A bank-held balance (checking or savings) distinct from the Wallet.
_Avoid_: wallet, balance (alone)

**Spendable**:
A derived affordability amount for a purchase reason (e.g. Wallet + auto-pay checking); never a stored third balance. In payloads we control, prefer `spendableMoney` — do not label Spendable as `playerMoney` when we own the payload (legacy `playerMoney` may remain only as a deprecated UI alias).
_Avoid_: balance, funds, total money, playerMoney (when we control the payload)

**Housing Domain**:
The Claimed Domain after Payment Domain: owned property, mortgage, and landlord/rentals as one Life Sim housing story.
_Avoid_: real estate (as a vague bucket), property module (implementation)

**Marketplace Domain**:
The Claimed Domain after Housing Domain: buy/sell/rent/negotiate/watches as one Plus market story (not Upstream RLS core plus satellite patches).
_Avoid_: marketplace core, listings (alone)

**Job Broker**:
A Claimed Domain: Plus-owned logistics job-broker UX and routing; Upstream RLS broker changes port only when they Fit Life Sim.
_Avoid_: logistics (whole), employment, freelance board

## Upstream relationship (criteria)

**Fits Life Sim**:
The cherry-pick gate for Upstream RLS gameplay: port only if it improves day-to-day money/housing/work/vehicles coherence, or is required Glue for a Claimed Domain.
_Avoid_: players would miss it, easy merge, parity

**Plus Wins**:
Default when Upstream RLS touches a Claimed Domain: skip their change unless it is Must-port or clearly Fits Life Sim and is deliberately adapted.
_Avoid_: always port then re-Plus, keep up, case-by-case with no default
