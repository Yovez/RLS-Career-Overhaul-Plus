# Fork notes

This workspace is **Plus** (RLS Career Overhaul Plus), an independent Life Sim product built from Upstream RLS. We expand and redesign Claimed Domains for how we want to play. Sync policy is **Cherry-pick-track** (see [ADR-0001](adr/0001-cherry-pick-track.md) and [GLOSSARY.md](../GLOSSARY.md)). This is **not** a contribution fork for landing work upstream.

## Remotes

| Remote | URL | Purpose |
|--------|-----|---------|
| `upstream` | `https://github.com/RLS-Modding/rls_career_overhaul.git` | Official public RLS repo |
| `origin` | `https://github.com/Yovez/RLS-Career-Overhaul-Plus.git` | Plus (standalone publish repo, not in RLS fork network) |
| `old-fork` | `https://github.com/Yovez/rls_career_overhaul_plus.git` | Previous GitHub fork (archive/redirect only) |

Current branch: `main` (ahead of `upstream/main` with Plus commits). Browse: https://github.com/Yovez/RLS-Career-Overhaul-Plus

### Pushing to origin

```bash
git push -u origin main
```

GitHub auth: `gh auth login`, or HTTPS with a PAT / credential manager. Do **not** push Plus commits to `upstream`.

## Syncing with Upstream RLS

Default: **do not** `git merge upstream/main`.

```bash
git fetch upstream
# Inspect: upstream commits / release notes / diff for paths you care about
git log HEAD..upstream/main --oneline
git diff HEAD...upstream/main -- path/of/interest
# Port only what Must-port or Fits Life Sim (often as a cherry-pick or manual patch)
git cherry-pick <upstream-commit>
# test in-game, then push origin
```

Rules of thumb:

- **Must-port**: BeamNG version / API / UI shell breaks from Upstream RLS → port as Glue.
- **Fits Life Sim**: gameplay ports only if they improve day-to-day money/housing/work/vehicles coherence, or are required Glue for a Claimed Domain.
- **Plus Wins**: if Upstream RLS touches a Claimed Domain, skip by default unless Must-port or a deliberate adapted port. **Payment Domain is Claimed** — never instruct agents or maintainers to bulk-merge Upstream RLS bank/payment/automation over Plus’s facade.
- **Best-effort Import**: Upstream RLS saves may load; Claimed Domains can extend or rewrite save data. For money: import keeps **Wallet** (`playerAttributes.json`) and **Accounts** / automation (`bank.json`) when present; `shell/saveImport/prepare.lua` asserts conservation of Wallet + Accounts + pending transfers + known employment escrow (held wages) before finishing a slot. **Spendable** is never stored, so import cannot invent or drop a third balance. Offline verify: `scripts/payment-save-conservation/`.

Claim order (redesign, not endless patches): **Payment Domain** → **Housing Domain** → **Marketplace Domain**. Employment stays Glue until after Payment and Housing. Job Broker is already Claimed. Do not expand Payment Domain work into Housing or Marketplace redesign.

Rare bulk merge is allowed only as an exception (e.g. overwhelming Must-port surface), on a throwaway branch — not the default workflow.

Expect friction in:

- `gameplay/overhaul/version.json` / credits / README when they cut releases
- Claimed or heavily customized paths (`economy`, landlord/rentals, broker, phone career UI)

## Dev install (BeamNG)

This profile uses **unpacked** live edit (no re-zip loop):

| Path | Role |
|------|------|
| `E:\BeamNG RLS` | Git working tree (this repo) |
| `E:\BeamMP\current\mods\unpacked\rls_career_overhaul` | Junction → repo |
| `rls_career_overhaul_v2.8.0.zip.disabled` | Upstream release kept disabled |
| `rls_career_overhaul_fork.zip` | **Do not use** while unpacked is active (remove or rename `.disabled`) |

1. Ensure only one Overhaul content root is enabled (unpacked junction).
2. Restart BeamNG after Lua/extension changes; Vue often needs restart too on 0.40.
3. Target game: **0.40.x**.

Recreate the junction (Admin cmd if needed):

```bat
mklink /J "E:\BeamMP\current\mods\unpacked\rls_career_overhaul" "E:\BeamNG RLS"
```

Do not ship from a dirty mix of two Overhaul versions in the same profile.

## Branching suggestion

| Branch | Use |
|--------|-----|
| `main` | Stable playable Plus tip |
| `upstream-port/<topic>` | Inspect/port a specific Upstream RLS change |
| `fix/<topic>` | Individual Plus fixes or Claimed Domain work |

Keep ports focused per change so review stays small.

## Docs in this folder

`docs/` is **Plus-local**. Upstream does not have it. When porting Upstream RLS:

- Keep `docs/` (ours)
- Do not delete upstream `README` / licensing / `.github` without reason
- If upstream later adds a `docs/`, port carefully

## Changing systems safely

1. Find the system in [SYSTEMS_CATALOG.md](SYSTEMS_CATALOG.md). Prefer glossary terms from [GLOSSARY.md](../GLOSSARY.md).
2. Prefer data tweaks in `gameplay/overhaul/` when the knob already exists — unless the area is a Claimed Domain you are redesigning.
3. Keep AGPL / bCDDL notices; update `licenses/RLS-AGPL-SCOPE.md` only when adding new original RLS-scoped files (upstream process; mirror if you redistribute).
4. Test: new career + Best-effort Import of an older save if you touch economy or save paths. For Payment Domain / money paths, also run `python scripts/payment-save-conservation/run.py` and confirm Wallet + Accounts (+ known escrow) still conserve.
5. Log intentional divergences in `docs/CHANGELOG_FORK.md`.

## Known upstream workflow quirks

- Public `main` can include accepted fixes not yet in a release ZIP.
- Maintainers also keep a private **dev** repo; public contributors only PR the public repo.
- Packaging for players is a named release ZIP, not “clone this git repo into mods” (though that works for development).
