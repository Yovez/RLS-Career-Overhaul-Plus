# Payment facade contract (#2 / #9)

Offline checks for the Payment Domain facade seam: `canPay`, `getSpendableMoney`, `getWalletMoney`, `pay`, `reward`.

Covers auto-pay on/off, checking-then-Wallet split, wrong spend bucket, Spendable derived-only, rejected split pay with no partial checking debit, and Wallet-truth deposit capacity (`getWalletMoney` ≠ Spendable when auto-pay checking is large; transfer pay stays Wallet ledger).

## Run (no BeamNG)

From this directory:

```bash
npm install
node run.mjs
```

Requires Node.js. Uses [fengari](https://github.com/fengari-lua/fengari) to load real `lua/ge/extensions/overhaul/career/economy/payment.lua` against stubbed bank/wallet/sponsor deps.

Exit `0` = all cases passed.
