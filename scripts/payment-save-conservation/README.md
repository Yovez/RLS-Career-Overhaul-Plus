# Payment Domain save conservation (#10)

Offline checks that Best-effort Import and Plus save round-trips conserve **Wallet** + **Accounts** (+ known escrow / pending transfers / savings interest), and that **Spendable** is never stored.

Mirrors the importer totals in `lua/ge/extensions/overhaul/shell/saveImport/prepare.lua` (`sumTotals` / `assertConserved`).

## What is conserved

| Stored | Path |
|--------|------|
| Wallet | `career/playerAttributes.json` → `money.value` |
| Accounts | `career/rls_career/bank.json` → `accounts[].balance` |
| Pending business transfers | `bank.json` → `pendingTransfers[].amount` |
| Employment escrow / held wages | `career/rls_career/logisticsEmployment.json` |
| Automation config (not money) | `bank.json` → `automation` |

**Spendable** is derived at runtime (Wallet + claimed auto-pay checking for a reason) and must not appear in those files.

## Run (no BeamNG)

From this directory:

```bash
python run.py
```

Requires Python 3. Exit `0` = all cases passed.
