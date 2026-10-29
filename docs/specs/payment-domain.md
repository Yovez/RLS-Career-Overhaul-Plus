## Problem Statement

Players cannot trust what they can buy. The Wallet, checking Accounts, and auto-pay rules disagree across screens: a purchase can look unaffordable when checking would cover it, or look affordable when it will not. Plus is building a Life Sim where day-to-day money must feel coherent, but money movement is still a patchwork on Upstream RLS patterns instead of a Claimed Domain.

## Solution

Claim the **Payment Domain**: one Plus-owned model of what can pay for what and in what order. **Wallet** and **Accounts** remain the only stored balances; **Spendable** is always derived for a purchase reason. Every affordability check and debit goes through the payment facade (`canPay`, `pay`, `reward`/`payout`, `getSpendableMoney`). Bank automation (auto-pay, auto-deposit, sweeps) is a feature of this domain, not a separate island. UI that gates on money must match Spendable for the same reason.

Respect ADR-0001 (Cherry-pick-track): Plus Wins on this Claimed Domain; do not reshape Payment to match Upstream RLS.

## User Stories

1. As a player, I want one answer to "can I afford this?", so that shop UI and the actual purchase never disagree.
2. As a player with vehicles auto-pay enabled, I want vehicle purchases to use checking then Wallet, so that I do not have to manually withdraw before every dealership buy.
3. As a player with vehicles auto-pay enabled, I want the dealership list and filters to use Spendable for vehicles, so that cars I can actually buy are not greyed out.
4. As a player with shops auto-pay enabled, I want parts and shop purchases to honor checking the same way vehicles do, so that money rules feel consistent.
5. As a player with auto-pay off for a category, I want that category to debit Wallet only, so that checking stays untouched unless I opted in.
6. As a player, I want Spendable to never appear as a third stored balance, so that bank and Wallet screens stay understandable.
7. As a player, I want Wallet to mean cash-on-hand, so that deposits and "cash in pocket" displays stay truthful.
8. As a player, I want checking and savings to remain Accounts, so that bank balances are distinct from Wallet.
9. As a player viewing the bank, I want to see true Account balances, so that I am not looking at a Spendable fiction.
10. As a player configuring auto-pay, I want exclusive category claims per checking Account, so that two accounts cannot fight over the same spend bucket.
11. As a player, I want spend buckets (shops, vehicles, stocks, fines, insurance, loans, repairs, fuel, services, property, other) to map stably from purchase reasons, so that the right Account pays.
12. As a player buying a vehicle, I want the purchase reason to map to the vehicles bucket, so that vehicles auto-pay applies.
13. As a player buying non-vehicle shop goods, I want the purchase reason to map to shops (not vehicles), so that the wrong auto-pay claim is not used.
14. As a player paying a fine with fines auto-pay on, I want checking to cover it when claimed, so that I am not stranded with cash in the bank.
15. As a player with insufficient Wallet and insufficient auto-pay checking, I want canPay to fail clearly, so that I know I need more money or a transfer.
16. As a player with partial checking coverage, I want pay to split checking first then Wallet, so that auto-pay behaves predictably.
17. As a player receiving rewards, I want credits to land in Wallet (or the chosen Account) and then honor auto-deposit rules, so that income automation still works.
18. As a player with walletFloor auto-deposit, I want surplus above the floor swept to checking, so that cash-on-hand stays intentional.
19. As a player depositing into an Account, I want the UI to use Wallet only, so that I cannot "deposit" Spendable that includes the same checking balance.
20. As a player on the phone Marketplace buy tab, I want affordability to use Spendable for the right reason when auto-pay applies, so that listings match what I can pay.
21. As a player in maintenance or garage flows that gate on money, I want those gates to use Spendable for the matching reason (or Wallet when the reason is cash-only), so that I am not blocked incorrectly.
22. As a player with a sponsored payment, I want sponsors to cover before Account/Wallet debit when applicable, so that existing sponsored flows keep working.
23. As a player with held wages / payout holders, I want payout to still route held wages correctly, so that employment Glue keeps working until Employment is claimed later.
24. As a player importing an Upstream RLS save, I want Best-effort Import: Wallet and Accounts load, automation config preserved when present, so that I am not forced to wipe the career to use Plus money rules.
25. As a player after Payment Domain changes, I want existing Plus saves to keep Wallet, Accounts, and automation without silent money loss, so that claiming the domain does not steal my balance.
26. As a player using stock buys with stocks auto-pay, I want stock purchases to go through the same payment facade, so that stocks do not bypass Payment Domain.
27. As a player, I want loan, insurance, fuel, repair, and property spends to respect their buckets when auto-pay is configured, so that life costs feel bank-integrated.
28. As a developer agent, I want all new money gates to call the payment facade, so that we do not reintroduce wallet-only UI bugs.
29. As a developer agent, I want ledger reasons on pays to remain the source of spend-bucket mapping, so that UI does not invent parallel category logic.
30. As a Plus maintainer, I want Payment Domain treated as Plus Wins under Cherry-pick-track, so that Upstream RLS payment tweaks are not bulk-merged over our model.
31. As a Plus maintainer, I want Must-port BeamNG/Glue payment breaks still portable, so that game updates do not leave Plus unbuildable.
32. As a player with multiple checking Accounts, I want only the claimed auto-pay Account for a bucket to contribute to Spendable, so that Spendable is not the sum of every checking balance.
33. As a player turning auto-pay off, I want Spendable for that reason to equal Wallet immediately, so that configuration changes are visible in affordability.
34. As a player, I want failed pays not to partially consume checking without completing the purchase when the facade rejects the pay, so that money and goods stay consistent.
35. As a player reading financial history, I want Wallet history to remain Wallet ledger truth, so that history is not rewritten as Spendable.
36. As a Life Sim player, I want money rules stable before Housing Domain work, so that rent and mortgage later plug into one debit model.

## Implementation Decisions

- Claim **Payment Domain** as a Plus Claimed Domain (glossary). Bank automation is a **feature of Payment Domain**, not a second Claimed Domain.
- Canonical stored money: **Wallet** + **Accounts** only. **Spendable** is derived: Wallet + auto-pay checking balance for a given reason (via spend bucket / pay claims). Never persist Spendable.
- Single product seam: the payment facade — affordability (`canPay`, `getSpendableMoney`) and mutation (`pay`, `reward`, `payout`). Callers must not invent parallel wallet-only affordance for purchasable flows.
- Debit order for auto-pay money lines: sponsor cover (when applicable) → claimed checking (full or partial) → Wallet remainder. Explicit Account id on pay still means that Account only (no silent Wallet mix unless already defined by the facade).
- Spend buckets and exclusive payClaims remain the auto-pay configuration model; reason → bucket mapping stays authoritative for which claim applies.
- UI that **gates or filters on ability to pay** must use Spendable (or `canPay`) with the correct reason for that flow. UI that **displays cash-on-hand or deposit capacity** must use Wallet (and Account balances for bank screens)—never overwrite Wallet display fields with Spendable in a way that leaks into deposit/transfer UX.
- Shopping payloads may expose both wallet and spendable fields (or equivalent), but must not force consumers to read Wallet when they mean Spendable.
- Save shape: keep Wallet in player attributes and Accounts/automation in bank save data; migrations must conserve total player money (Wallet + Accounts + known escrow/held wages already counted in import checks). Prefer additive clarity over schema churn.
- Employment, loans, credit, stocks remain adjacent: they must **call** Payment Domain for money movement where they spend/reward; they are not redesigned in this claim (Employment stays Glue until after Payment and Housing).
- Upstream RLS: Plus Wins inside Payment Domain. Port only Must-port Glue or changes that Fits Life Sim and are deliberately adapted.
- Docs: align SYSTEMS_CATALOG / fork changelog language with glossary terms (Payment Domain, Spendable, Wallet, Account) when behavior ships.
- Do not expand this claim into Housing Domain or Marketplace Domain redesign (those are later claim order items).

## Testing Decisions

- Good tests assert **external behavior** at the payment facade: given Wallet, Account balances, and auto-pay config, `canPay` / `getSpendableMoney` / `pay` outcomes match the Life Sim rules. Do not assert internal helper structure or UI component internals as the source of truth.
- Prefer the **highest seam**: payment facade functions. Add the fewest new seams possible; do not introduce a second affordability API.
- Cover at least: auto-pay on with enough checking; auto-pay on with split checking+Wallet; auto-pay off (Wallet only); wrong bucket not using another category's claim; Spendable never exceeding Wallet + claimed checking; deposit-facing Wallet not equal to Spendable when auto-pay checking is large.
- Integration expectation for UI: any money gate fixed in this work should be checked against the same reason's `getSpendableMoney`/`canPay` (manual in-game acceptance where Vue cannot be unit-tested easily).
- Prior art: no dedicated economy/payment automated suite today; beamTest is only provider plumbing. Prefer small, focused Lua-level tests at the facade if the repo can host them; otherwise document a reproducible in-game checklist on the issue and keep facade behavior centralized so tests can land later.
- Regression focus: vehicle purchase with vehicles auto-pay (the known insufficient-funds / Spendable mismatch class of bugs).

## Out of Scope

- Housing Domain claim (mortgage + landlord + property as one story).
- Marketplace Domain claim (full buy/sell/rent/negotiate redesign).
- Employment Claimed Domain redesign.
- Stock market / broker policy redesign (beyond routing buys/sells through Payment Domain).
- Loans/credit product redesign.
- Bulk merge from Upstream RLS or merge-track workflow changes (already decided in ADR-0001 / FORK_NOTES).
- Rebranding Plus away from RLS naming.
- Inventing a stored unified balance that collapses Wallet and checking.

## Further Notes

- Glossary: GLOSSARY.md. Architecture: docs/adr/0001-cherry-pick-track.md, docs/FORK_NOTES.md.
- Claim order after this: Housing Domain → Marketplace Domain. Job Broker is already Claimed.
- Known pain: some UIs still read Wallet-only or conflate Spendable into playerAttributes.money; fixing that class of bugs is in scope when those UIs are payment gates.
- Seams confirmed with maintainer: payment facade primary; automation config + reason→bucket supporting; Housing/Marketplace/employment redesign out.
