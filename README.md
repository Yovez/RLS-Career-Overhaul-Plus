# RLS Career Overhaul Plus

**RLS Career Overhaul Plus** is an independent, free, open-source fork of [RLS Career Overhaul](https://github.com/RLS-Modding/rls_career_overhaul). You still get the full Overhaul career: jobs, deliveries, businesses, racing, phone, RLS West Coast, and the rest. On top of that, Plus adds its own QoL, routing, and system expansions.

This project is **not** a contribution fork for upstream RLS. We maintain Plus ourselves and change systems the way we want to play. We still pull from upstream now and then so Plus can stay close to public RLS releases, then keep building from there.

**Base:** RLS Career Overhaul **v2.8.0** · BeamNG.drive **0.40.x**

[This repository](https://github.com/Yovez/rls_career_overhaul_plus) · [Upstream RLS](https://github.com/RLS-Modding/rls_career_overhaul) · [Plus changelog](docs/CHANGELOG_FORK.md) · [Fork notes](docs/FORK_NOTES.md)

![RLS West Coast](ui/modules/whatsnew/2.8.0_public/west-coast.jpg)

## Credits and relationship to RLS

**RLS Career Overhaul** was created and is maintained by **[RLS Modding](https://github.com/RLS-Modding)** and their contributors. Plus only exists because of that work. Full upstream credits live in [CREDITS.md](CREDITS.md) and the [upstream contributors graph](https://github.com/RLS-Modding/rls_career_overhaul/graphs/contributors).

Plus is maintained by **[Yovez](https://github.com/Yovez)** as a separate project. It is **not affiliated with RLS Modding**, and it is not affiliated with BeamNG GmbH. If something is broken in base Overhaul, report it upstream. If something is wrong in a Plus-only change, report it here.

## Free and open source

Plus stays **free** and **open source**. No paid edition, no features locked behind a storefront, and no plan to close the source. Licensing follows upstream:

- Original RLS-scoped source: **AGPLv3-only** with the BeamNG additional permission ([license scope](licenses/RLS-AGPL-SCOPE.md), [LICENSE](LICENSE)).
- BeamNG-derived and third-party material: their existing licenses ([Licensing](LICENSING.md), [third-party notices](THIRD_PARTY_NOTICES.md)).

If you redistribute Plus, keep attribution, license texts, and source obligations.

## What Plus is for

- A playable career on current public RLS, with Plus improvements on top.
- Expanding systems (routing, logistics QoL, phone behaviour, and more over time) without waiting on upstream design.
- Occasional merges or cherry-picks from [upstream](https://github.com/RLS-Modding/rls_career_overhaul) so we pick up public-release fixes and content, then re-apply Plus changes as needed.

What it is **not**:

- A staging ground for pull requests into RLS Modding’s repo.
- A claim on the RLS name, brand, or official releases. Use upstream if you want stock Overhaul.

Tracked Plus differences: [docs/CHANGELOG_FORK.md](docs/CHANGELOG_FORK.md).

## Your career (from Overhaul)

Overhaul has its own career mode, saves, and RLS West Coast map. Start a new career or import an older RLS career as a separate copy, keeping the original save.

- **Jobs and deliveries:** Job Broker, My Loads, parcels, materials, fluids, and vehicles.
- **Shifts and passengers:** Employers, taxis, buses, recovery, quarry, and facility work.
- **Cars and garages:** Dealerships, storage, Marketplace, auctions.
- **Workshops and businesses:** Engines, tuning, fleets, business finances.
- **Racing and events:** Drag, circuit, rally, drift, crawling, and more.
- **Police and insurance:** Pursuits, fines, coverage, and repairs.
- **Money and progression:** Wallet, Logbook History, skills.

Available jobs, facilities, and events depend on map, equipment, and progress.

## Install

**Players (when a Plus release ZIP exists):** install like any BeamNG mod. Put the ZIP in your user folder’s `mods` directory, disable other Overhaul copies (including unpacked ones), enable Plus, and restart.

**Developers / this tree:** see [docs/FORK_NOTES.md](docs/FORK_NOTES.md) for the unpacked junction workflow used while developing Plus.

Always back up saves before updating. Prefer one Overhaul content root at a time.

## Help and bug reports

- **Plus-only behaviour** (routing, phone parking brake, fork docs, and similar): open an issue on [Yovez/rls_career_overhaul_plus](https://github.com/Yovez/rls_career_overhaul_plus/issues).
- **Base Overhaul / map / save issues** that also happen without Plus changes: use [upstream troubleshooting](https://github.com/RLS-Modding/rls_career_overhaul/wiki/Troubleshooting) and [upstream issues](https://github.com/RLS-Modding/rls_career_overhaul/issues).

Include BeamNG version, whether you are on Plus or stock RLS, map versions, new vs migrated save, steps to reproduce, and `beamng.log` when useful.

## Contributing to Plus

Improvements aimed at **this** fork are welcome (issues and PRs against this repository). Please do **not** treat Plus as the path to land changes in official RLS. Open those against [RLS-Modding/rls_career_overhaul](https://github.com/RLS-Modding/rls_career_overhaul) if that is your goal.

Security reports for this fork: use GitHub private vulnerability reporting on this repository when available, or contact the Plus maintainer. Upstream’s [SECURITY.md](SECURITY.md) still applies to stock Overhaul.

## Syncing with upstream

```bash
git fetch upstream
git merge upstream/main
# resolve conflicts, re-test Plus behaviour, then push origin
```

Details: [docs/FORK_NOTES.md](docs/FORK_NOTES.md).

## Licensing (summary)

Original RLS source listed in the [license scope](licenses/RLS-AGPL-SCOPE.md) is AGPLv3-only with a BeamNG additional permission. BeamNG-derived files and included components retain their applicable licenses. See [Licensing](LICENSING.md) and [third-party notices](THIRD_PARTY_NOTICES.md).
