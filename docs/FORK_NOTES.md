# Fork notes

This workspace is **RLS Career Overhaul Plus**, an independent fork of RLS Career Overhaul. We expand systems and ship Plus-only changes for how we want to play. We periodically merge from upstream to stay near public RLS releases. This is **not** a contribution fork for landing work upstream.

## Remotes

| Remote | URL | Purpose |
|--------|-----|---------|
| `upstream` | `https://github.com/RLS-Modding/rls_career_overhaul.git` | Official public RLS repo |
| `origin` | `https://github.com/Yovez/rls_career_overhaul_plus.git` | This Plus fork (publish here) |

Current branch: `main` (ahead of `upstream/main` with Plus commits). Browse: https://github.com/Yovez/rls_career_overhaul_plus

### Pushing to origin

```bash
git push -u origin main
```

GitHub auth: `gh auth login`, or HTTPS with a PAT / credential manager. Do **not** push Plus commits to `upstream`.

## Syncing with upstream

```bash
git fetch upstream
git merge upstream/main
# resolve conflicts, test in-game, then push origin
```

Prefer **merge** over rebase if you already published commits to `origin`, so shared history stays stable. Rebase is fine on private-only branches.

Expect conflicts in:

- `gameplay/overhaul/version.json` / credits / README when they cut releases
- Any file you heavily customized in the same areas they touch (`economy`, `employment`, UI career modules)

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
| `main` | Stable playable fork tip; merge upstream here periodically |
| `upstream-sync` | Temporary branch for messy merges |
| `fix/<topic>` | Individual annoyance fixes |

Keep forks focused per change so upstream merges stay reviewable.

## Docs in this folder

`docs/` is **fork-local**. Upstream does not have it. When merging upstream:

- Keep `docs/` (ours)
- Do not delete upstream `README` / licensing / `.github` without reason
- If upstream later adds a `docs/`, merge carefully

## Changing systems safely

1. Find the system in [SYSTEMS_CATALOG.md](SYSTEMS_CATALOG.md).
2. Prefer data tweaks in `gameplay/overhaul/` when the knob already exists.
3. Keep AGPL / bCDDL notices; update `licenses/RLS-AGPL-SCOPE.md` only when adding new original RLS-scoped files (upstream process; mirror if you redistribute).
4. Test: new career + migrated save if you touch economy or save paths.
5. Log intentional divergences here or in a short `docs/CHANGELOG_FORK.md` when you start shipping meaningful differences (optional; create when needed).

## Known upstream workflow quirks

- Public `main` can include accepted fixes not yet in a release ZIP.
- Maintainers also keep a private **dev** repo; public contributors only PR the public repo.
- Packaging for players is a named release ZIP, not “clone this git repo into mods” (though that works for development).
