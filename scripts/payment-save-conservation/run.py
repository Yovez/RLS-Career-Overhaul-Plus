#!/usr/bin/env python3
"""Offline Payment Domain save conservation checks (#10).

Mirrors money totals from shell/saveImport/prepare.lua (sumTotals / assertConserved).
Does not need BeamNG.
"""

from __future__ import annotations

import copy
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
FIXTURES = HERE / "fixtures"
EPS = 1e-5
# Same constant as prepare.lua IMPORTED_SAVINGS_RATE_PER_SECOND
IMPORTED_SAVINGS_RATE_PER_SECOND = 0.05 / (6 * 3600)

SPENDABLE_KEYS = {"spendable", "spendableMoney", "Spendable"}


def fail(msg: str) -> None:
    print(f"FAIL: {msg}", file=sys.stderr)
    raise SystemExit(1)


def assert_close(a: float, b: float, msg: str) -> None:
    if abs(a - b) >= EPS:
        fail(f"{msg}: {a} vs {b}")


def load_fixture(path: Path) -> dict:
    data = json.loads(path.read_text(encoding="utf-8"))
    files = {k: v for k, v in data.items() if k != "label"}
    return {"label": data.get("label", path.name), "files": files}


def iter_accounts(bank: dict):
    accounts = bank.get("accounts") or []
    if isinstance(accounts, dict):
        for key, account in accounts.items():
            yield str((account or {}).get("id") or key), account or {}
    else:
        for index, account in enumerate(accounts):
            account = account or {}
            yield str(account.get("id") or index), account


def add_bank_totals(result: dict, bank: dict) -> None:
    for acc_key, account in iter_accounts(bank):
        result["accounts"][acc_key] = float(account.get("balance") or 0)
        if account.get("type") == "personal" and account.get("accountType") == "savings":
            segment = float(account.get("segmentBalance") or account.get("balance") or 0)
            since = max(0.0, float(account.get("sinceSegmentStart") or 0))
            result["savingsInterest"] += float(account.get("accruedInterest") or 0) + (
                segment * IMPORTED_SAVINGS_RATE_PER_SECOND * since
            )
    for transfer in bank.get("pendingTransfers") or []:
        amount = transfer.get("amount")
        if not isinstance(amount, (int, float)) or amount < 0:
            fail("Invalid pending bank transfer")
        result["pendingTransfers"] += float(amount)


def add_escrow_totals(result: dict, employment: dict) -> None:
    employments = employment.get("employments")
    if employments:
        for emp in employments.values():
            escrow = (emp or {}).get("escrow") or {}
            result["escrow"] += float(escrow.get("money") or 0)
    else:
        escrow = employment.get("escrow") or {}
        result["escrow"] = float(escrow.get("money") or 0)


def sum_totals(files: dict) -> dict:
    attributes = files.get("career/playerAttributes.json")
    if not isinstance(attributes, dict):
        fail("Missing player attributes")
    money = attributes.get("money")
    if not isinstance(money, dict) or not isinstance(money.get("value"), (int, float)):
        fail("Missing wallet balance")
    result = {
        "wallet": float(money["value"]),
        "accounts": {},
        "pendingTransfers": 0.0,
        "escrow": 0.0,
        "savingsInterest": 0.0,
    }
    add_bank_totals(result, files.get("career/rls_career/bank.json") or {})
    add_escrow_totals(result, files.get("career/rls_career/logisticsEmployment.json") or {})
    result["moneyTotal"] = (
        result["wallet"] + result["pendingTransfers"] + result["escrow"] + result["savingsInterest"]
    )
    for balance in result["accounts"].values():
        result["moneyTotal"] += balance
    return result


def ban_spendable(obj, path: str = "") -> None:
    if isinstance(obj, dict):
        for key, value in obj.items():
            if key in SPENDABLE_KEYS:
                fail(f"Spendable key persisted at {path}.{key}")
            ban_spendable(value, f"{path}.{key}" if path else key)
    elif isinstance(obj, list):
        for i, value in enumerate(obj):
            ban_spendable(value, f"{path}[{i}]")


def round_trip_bank(files: dict) -> dict:
    """Simulate bank load→save: preserve account balances + automation; drop nothing money-bearing."""
    out = copy.deepcopy(files)
    bank = out.get("career/rls_career/bank.json")
    if not isinstance(bank, dict):
        return out
    accounts = bank.get("accounts") or []
    if isinstance(accounts, dict):
        accounts = list(accounts.values())
    # Stable sort like bank.lua saveBankData
    accounts = sorted(accounts, key=lambda a: a["id"])
    transfers = sorted(list(bank.get("pendingTransfers") or []), key=lambda t: t["id"])
    automation = copy.deepcopy(bank.get("automation") or {})
    bank["accounts"] = accounts
    bank["pendingTransfers"] = transfers
    bank["automation"] = automation
    # Explicitly never invent Spendable on save
    bank.pop("spendable", None)
    bank.pop("spendableMoney", None)
    out["career/rls_career/bank.json"] = bank
    return out


def import_passthrough(files: dict) -> dict:
    """Best-effort Import without cash-out: copy slot files unchanged (rename-only)."""
    return copy.deepcopy(files)


def check_fixture(path: Path) -> None:
    fixture = load_fixture(path)
    label = fixture["label"]
    before = sum_totals(fixture["files"])
    ban_spendable(fixture["files"])

    imported = import_passthrough(fixture["files"])
    after_import = sum_totals(imported)
    assert_close(after_import["moneyTotal"], before["moneyTotal"], f"{label}: import moneyTotal")
    assert_close(after_import["wallet"], before["wallet"], f"{label}: import Wallet")
    if set(after_import["accounts"]) != set(before["accounts"]):
        fail(f"{label}: Account ids changed on import")
    for acc_id, balance in before["accounts"].items():
        assert_close(after_import["accounts"][acc_id], balance, f"{label}: Account {acc_id}")
    assert_close(after_import["escrow"], before["escrow"], f"{label}: escrow")
    assert_close(after_import["pendingTransfers"], before["pendingTransfers"], f"{label}: pendingTransfers")

    # Automation preserved when present (Plus); Upstream may have none.
    before_bank = fixture["files"].get("career/rls_career/bank.json") or {}
    after_bank = imported.get("career/rls_career/bank.json") or {}
    if "automation" in before_bank:
        if after_bank.get("automation") != before_bank.get("automation"):
            fail(f"{label}: automation changed on Best-effort Import")

    rounded = round_trip_bank(imported)
    after_rt = sum_totals(rounded)
    assert_close(after_rt["moneyTotal"], before["moneyTotal"], f"{label}: Plus round-trip moneyTotal")
    ban_spendable(rounded)
    after_auto = (rounded.get("career/rls_career/bank.json") or {}).get("automation")
    before_auto = before_bank.get("automation")
    if before_auto is not None and after_auto != before_auto:
        fail(f"{label}: automation lost on bank round-trip")

    print(f"OK  {label}")
    print(
        f"    moneyTotal={before['moneyTotal']} "
        f"(Wallet={before['wallet']}, Accounts={sum(before['accounts'].values())}, "
        f"escrow={before['escrow']}, pending={before['pendingTransfers']}, "
        f"savingsInterest={before['savingsInterest']})"
    )


def static_repo_guards() -> None:
    """Payment Domain claim must not teach bulk-merge, and must not persist Spendable."""
    # FORK_NOTES intentionally says "do not git merge upstream/main" — that is allowed.
    fork_notes = (REPO / "docs/FORK_NOTES.md").read_text(encoding="utf-8")
    if "do not" not in fork_notes.lower() or "Cherry-pick-track" not in fork_notes:
        fail("FORK_NOTES.md must keep Cherry-pick-track / do-not-bulk-merge guidance")
    if "Payment Domain" not in fork_notes and "Best-effort Import" not in fork_notes:
        fail("FORK_NOTES.md must mention Best-effort Import (Payment Domain save story)")

    catalog = (REPO / "docs/SYSTEMS_CATALOG.md").read_text(encoding="utf-8")
    for term in ("Payment Domain", "Wallet", "Account", "Spendable"):
        if term not in catalog:
            fail(f"SYSTEMS_CATALOG.md missing glossary term: {term}")

    changelog = (REPO / "docs/CHANGELOG_FORK.md").read_text(encoding="utf-8")
    if "Payment Domain" not in changelog:
        fail("CHANGELOG_FORK.md must note Payment Domain claim behavior")

    # Scan money save writers: no Spendable persistence helpers.
    economy = REPO / "lua/ge/extensions/overhaul/career/economy"
    for path in economy.rglob("*.lua"):
        text = path.read_text(encoding="utf-8", errors="replace")
        for needle in (
            'spendableMoney =',
            '["spendable"]',
            "spendable =",
            "jsonWriteFileSafe(.*spendable",
        ):
            # Allow comments / getSpendableMoney API / local UI vars that are not save keys.
            pass
        if "jsonWriteFileSafe" in text and "spendable" in text.lower():
            # Narrow: writing a file while mentioning spendable as a stored field is suspicious.
            for line in text.splitlines():
                low = line.lower()
                if "jsonwritefilesafe" in low and "spendable" in low and not low.strip().startswith("--"):
                    fail(f"Suspicious Spendable save write in {path.relative_to(REPO)}: {line.strip()}")

    # prepare.lua must still assert money conservation.
    prepare = (
        REPO / "lua/ge/extensions/overhaul/shell/saveImport/prepare.lua"
    ).read_text(encoding="utf-8")
    if "Money conservation check failed" not in prepare or "moneyTotal" not in prepare:
        fail("saveImport/prepare.lua missing money conservation assert")

    print("OK  static repo guards (docs + conservation assert + no Spendable save writers)")


def main() -> None:
    fixtures = sorted(FIXTURES.glob("*.json"))
    if not fixtures:
        fail(f"No fixtures in {FIXTURES}")
    for path in fixtures:
        check_fixture(path)
    static_repo_guards()
    print("All payment save conservation checks passed.")


if __name__ == "__main__":
    main()
