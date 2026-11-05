# Polish round 5 — status

**Where this file comes from.** The round-5 coordinator kept its status notes in the Claude project
(`claude/POLISH_ROUND_5_STATUS.md`), never in the repo, and that file isn't on the owner's PC. This
copy was rebuilt in polish round 6 §1 from three sources: the open items the round-6 brief copied
from those notes (`docs/polish6/POLISH_ROUND_6_PROMPT.md` §1 and §3), the git history
(`15be65a..1b38f4a`) and the section reports in `docs/polish5/report/`. It records what the brief
records, not the original's wording. If the original turns up, it replaces this file.

The brief is `docs/polish5/POLISH_ROUND_5_PROMPT.md`.

## Where the round ended

- **Merged:** §0–§13, as PR #1 (`1b38f4a`, "Merge polish round 5 §0–§13 (#1)").
- **Never started:** §14 (cold nights), §15 (the garage), §16 (the commercial property) and §17
  (finish). Nothing was lost from them. Round 6 does §14–§16 in its Part 3 and round 5's §17 list
  in its Part 4.
- **Baseline tag:** `polish5-baseline` = `15be65a` ("Initial Canadian Winter Godot project"). The
  push was refused (403) in round 5. Polish 6 §1 created the tag locally; pushing it waits for the
  owner.
- **Baseline logs** (tests, perf, depth, grind) were on a VM that's gone and aren't rebuilt. Round
  6's baseline is `1b38f4a` (`docs/polish6/baseline/`). The weather truth the suite checks is in the
  repo (`tests/fixtures/polish5/weather_truth_baseline.json`).

## Sections

| § | Title | Commit | Report |
|---|---|---|---|
| — | CI: import, parse check and test suite on every PR; the polish-5 brief | `747f03a` | |
| — | The `.uid` files for five scripts that had none | `86580fc` | |
| §0 | Baseline: fixtures, run-log driver, HANDOFF in the repo | `2e77d41` | `report/s0.md` |
| §1 | Project hygiene: new logo, clean logs | `d1b3d15` | `report/s1.md` |
| §2 | Controls: G/F/H keys, settings migration, press rate limit | `76b8f7f` | `report/s2.md` |
| §3 | House walls, no snow work from inside, throws stop at buildings, road rule removed, money plant | `2bd1701` | `report/s3.md` |
| §4 | Door line, Gerry's snow tips and keys line, photo fixed | `d4295ac` | `report/s4.md` |
| §5 | House and building numbers, addresses on the map | `e3d67e6` | `report/s5.md` |
| §6 | Tool models and icons | `26b3666` | `report/s6.md` |
| §7 | The computer | `a5b903d` | `report/s7.md` |
| §8 | Weather in sync | `b7800a0` | `report/s8.md` |
| §9 | Time | `f809fdc` | `report/s9.md` |
| §10a | Contracts: tiers, bidding and deadlines | `4f6768a` | `report/s10a.md` |
| §10b | Contracts: outlines, map and HUD line | `659b671` | `report/s10b.md` |
| §11 | City crews on Mondays and Fridays | `ca28cc1` | `report/s11.md` |
| §12 | The pickup truck in snow (fix: `423b9b6`, deterministic deep-snow stop) | `4f1b15b` | `report/s12.md` |
| §13a | Upgrades per item | `edd95e4` | `report/s13a.md` |
| §13b | Equipment, heated driveway and path, melting | `ef8e0e5` | `report/s13b.md` |
| §14–§17 | Cold nights, the garage, the commercial property, finish | not started | |

## Left behind by the PR (round 6 §1)

- `tools/data_gen/generate_data.gd` + `.uid`: only on the owner's PC (the old unanchored
  `.gitignore` rule `data_*/` hid them until round 5 §1 anchored it). Committed in polish 6 §1,
  updated to reproduce `data/` value for value, with a test.
- `export_presets.cfg` (Windows Desktop): only on the owner's PC. Committed in polish 6 §1 with a
  relative export path.
- The tag `polish5-baseline`: see above.
- These status notes: this file.

## Open items

Carried into round 6 §3, where they are worked:

- The fast-forward control covers the map's column letters A–B
  (`shots/10-contracts/after_map.jpg`).
- The computer's Weather app at 11:14 a.m. showed "Light snow … from about 10 a.m." under a clear
  sky (`shots/09-time/after_computer_10x.jpg`): a today card whose start time has passed without
  snow should move to the new expected start. The TV (and round 6's phone radar) to be checked
  against it.
- The large scraper's store text says "1.2 m blade"; the blade is 1.0 m.
- Tools lying on the ground float 0.5–0.95 m, the opening's buried shovel included.
- **Settling isn't saved** (the most important for play-testing): a game saved right after a sleep
  reloads with unsettled street-edge banks (5–6 m cliffs in the mid-winter fixture) that collapse
  along the street at the first nearby snow work, leaving ~1 m lanes.
- `Snow.blade_push` jitters with the global `randf()`.
- The pickup with plow (blade up) and the dump truck are worse in deep snow than the plain pickup.
