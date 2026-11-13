# Polish 7 — playtest fix 2: pushed snow tumbles instead of spiking

Brief: `docs/polish7/PLAYTEST_FIX_2.md`.

## Measured first

**How.** A probe (not committed) drove the pickup with its plow, blade down (`set_blade`, as its Down
key does) and straight, at full throttle along Maple Street (x 6 → east, the middle of the street at
z 83) through level snow laid on the street and its sidewalks. The opening case is a new game's truck
from where it is parked. Fun mode, seed 2024, the clock stopped, a clear sky, relaxation by tile
count (`relax_usec = 0`, the tests' setting), `push_rng` reseeded: every run is the same. Every frame
it read the player-moved (`soft`) snow from 8 m behind the blade to 12 m ahead and 6 m to each side.

- **Top:** the deepest player-moved cell.
- **Over the step:** the most a player-moved cell's loose snow stands above `moved_repose` (0.19 m)
  over a neighbour it could slide onto (not a building, a completed box from outside, the guarded
  strip, the street from the property side: the relaxation's walls).
- **Pile:** the player-moved snow standing more than 5 cm above the level snow, from the blade's face
  on: its length and width, and its volume above the level snow (carried).
- **Spill:** the player-moved snow above the level behind the face and past the blade's ends.
- **Stopped:** braked 1 s after the blade reached the distance, the blade still down.
- **Left:** then the blade raised, backed off 1 s, out of the truck, the guard run out, the snow
  settled (`relax_until_stable`).

**Before the fix** (`HEAD` before this commit):

| push | top while pushing | stopped | left | largest step | over the step | pile stopped (long × wide, carried) | spill | speed once steady |
|---|---|---|---|---|---|---|---|---|
| 20 cm, 25 m | 1.89 m | 1.66 m | | 0.52 m | 0.33 m | 2.0 × 3.8 m | 6.5 m³ | |
| 20 cm, 50 m | 1.92 m | 1.66 m | | 0.59 m | 0.40 m | 2.0 × 3.8 m | 14.7 m³ | |
| 20 cm, 100 m | 1.93 m | 1.69 m | 1.15 m | 0.59 m | 0.38 m | 2.0 × 4.0 m, 3.3 m³ | 31.0 m³ | 28.0 km/h |
| 30 cm, 50 m | 2.16 m | 1.94 m | 1.32 m | 0.59 m | 0.42 m | 2.3 × 4.0 m, 4.2 m³ | 21.8 m³ | 20.9 km/h |
| 30 cm, 100 m | 2.19 m | 1.92 m | 1.32 m | 0.63 m | 0.45 m | 2.3 × 4.0 m, 4.2 m³ | 45.8 m³ | 20.9 km/h |
| 40 cm, 25 m | 2.43 m | 2.15 m | | 0.64 m | 0.45 m | 2.3 × 4.5 m | 12.9 m³ | |
| 40 cm, 50 m | 2.51 m | 2.15 m | | 0.65 m | 0.46 m | 2.3 × 4.5 m | 28.3 m³ | |
| 40 cm, 100 m | 2.51 m | 2.15 m | 1.48 m | 0.67 m | 0.49 m | 2.3 × 4.5 m, 5.0 m³ | 59.0 m³ | 15.7 km/h |
| opening, 15 m | 4.11 m | 2.72 m | 1.99 m | 0.84 m | 0.66 m | 2.8 × 5.3 m, 9.2 m³ | 15.4 m³ | 8.4 km/h (15 m in 10.2 s) |

The other plows, 40 m of 30 cm: the ATV 1.41 m (0.16 m over the step, 12.4 km/h), the tractor
2.16 m (0.41 m, 20.3 km/h), the plow truck 3.44 m (0.82 m, 35.2 km/h), the grader 3.03 m (0.63 m,
25.6 km/h). Hand pushes (RMB, walking, 8 s): bare hands and the standard shovel in 15 cm, the wide
pusher in 15 and 30 cm, the large scraper and the sleigh in 30 cm: tops 0.47–1.08 m, at most 5 cm
over the step. The wide pusher stalled in 30 cm after 2.0 m.

**What makes the spike: the deposit.**
- Each frame `blade_push` lifts the band behind the face, which as the blade advances is the front
  row of its own pile (up to about 2 m deep), and drops it 0.26–1.06 m ahead: back onto the pile.
- The relaxation moves 45 % of a step's excess per pass, a tile at a time, and can't keep up. Cells
  stand 0.4–0.5 m over the step at 0.5–0.7 m ahead of the face (0.66 m in the opening, 0.82 m for the
  plow truck), on 85–95 % of the frames.
- **Not the ceiling:** the pile never comes near 6 m. **Not the guard:** it only holds the pile's back
  face against the blade, which is right. **Not the renderer:** the heightfield itself has the steps.
- **In the opening, also the curb.** The relaxation treats the curb as a wall from the property side,
  so the pile's snow on the last driveway cells stacks there (4.1 m) until the blade itself reaches the
  curb and casts it over.

**The brief's reading of the code:**
- **The deposit:** right, with two corrections. The band is the frame's advance + 0.1 m, so the berm
  ahead isn't lifted until the face has passed over it. And the snow doesn't all stay in a 1 m strip:
  the pile in front is 2.0–2.3 m long and 4–4.5 m wide, and the relaxation spills about two thirds of
  everything collected past the blade's ends into ridges.
- **The settling:** right that the relaxation can't keep up and the blade refills the pile every
  frame. But the pile doesn't climb toward 6 m: on level snow it stops growing within 10–20 m (the
  spill off the ends balances the intake), at a top of 1.9–2.5 m. What the player sees is the
  ragged, spiky shape of that pile, not a pile that keeps growing. The pile is the same after 25, 50
  and 100 m.
- **The berm drag:** right that it reads only 0.65 m ahead of the face. But before the fix the spike
  stood inside that reach (0.5–0.7 m), so the drag did read most of it (1.8–3.0 m³ at 30 cm, a drag of
  0.47–0.71).

## The owner's call

With the roll in place the pile comes out as a steady mound at the moved-snow slope: about 1.3–1.7 m
tall on 20–40 cm, the same after 50 m and 100 m, the rest in the ridges. The brief expected about
blade height (the pickup's blade is 0.83 m) and a pile longer and wider after 100 m. Asked with the
numbers, the owner chose to **keep it as built**. So the tests check that the pile never spikes, stays
under its measured height, and is the same size (not taller) after 100 m as after 50 m.

## What changed

**`Snow.blade_push` → `Snow._roll`** (`scripts/autoload/snow_sim.gd`):
- Each band share lands on its target cell as before, and then **rolls**. Whatever would make the cell
  stand more than `moved_repose` above its lowest open neighbour goes on to that neighbour, and on
  down the pile by steepest descent (at most `ROLL_STEPS` = 48 cells). It all happens in the same op,
  so the pile's shape no longer depends on the relaxation keeping up.
- Ties between equal neighbours go to the one furthest ahead of the blade, then the one furthest out,
  so a pile forms the same whichever way the blade faces.
- **Walls** are the relaxation's: buildings, a completed box from outside, off the map. Two more:
  - the blade, meaning the cells behind its face across its width;
  - the guarded strip behind the face. Ahead of the face the guard's box doesn't stop the roll: the
    box can reach past an angled blade's face or a diagonal heading.
- **The curb:** the roll is part of the push, so it stops at the curb only where the push does
  (`player_rule`). Every plow and hand tool carries its snow over the curb (round 5 §3), and its pile
  now tumbles over it too. The relaxation still treats the curb as a wall.
- **The ceiling** still caps every cell. What finds no room (or no way down) stays in front of the
  blade, as before (`kept`).
- **Volume:** what each 32-bit cell actually stores is counted, so the targets get exactly what the
  source gives up. A store that rounds up past what is left is redone a step lower, so the source is
  never overdrawn. The source's own subtraction still rounds once, as before.
- **Draws and marks:** no random draws: `push_rng` stays one draw per moved cell. Every cell the snow
  rolls onto is marked `soft`.
- **Chunks:** the roll brings each chunk it enters up to date before writing to it.
- **`tumble`** (default true): the pickup's shove passes false. Its snow lands as before, so its
  driving rules (round 5 §12, fix 1) don't change.
- **`berm_reach`** (default 0.65 m, as before): see the drag.

**The plows' berm drag** (`scripts/vehicles/vehicle.gd`, `Snow.blade_push`). `berm` is now:
- all the snow across the blade within `BERM_FACE` (0.65 m) of its face, as before;
- plus, out to `berm_reach`, the pushed (player-moved, loose) snow there.

The push and the back-drag pass `berm_reach(hw)` = `BERM_REACH_BASE` (0.5) + `BERM_REACH_PER_HW`
(0.6) × the blade's half-width:
- 0.95 m for the ATV;
- 1.22 m for the pickup and the tractor;
- 1.52 m for the plow truck;
- 1.61 m for the grader.

Hand pushes keep 0.65 m.

The push itself works on the same cells as before the fix, and marks and queues the same area for the
relaxation. Only the reading reaches further, over its own rectangle, where a plow's `berm_reach`
passes the push's. This is the review's refinement, made after the fix was first pushed (see Review).

## After

The same probe on the fix as first pushed (`e31ffff`; fun, seed 2024, relaxation by tile count). The
review's refinement after it leaves every plow's op bit-identical. The hand pushes were measured
again on the final code with a second probe (see Hand pushes); they differ from this table only by
that probe's start and timing.

- **Over the step, in front:** the most a cell from 0.25 m behind the face on stood over the step,
  with the relaxation running. With it off, the op leaves none (the first test).
- For the angled blades the probe looks along the truck, not the blade, so it also counts snow held
  against the blade's own cut. The tests scan along the face: at most 2.4 cm there.

| push | top while pushing | stopped | left | over the step, in front | pile stopped (long × wide, carried) | spill | speed once steady |
|---|---|---|---|---|---|---|---|
| pickup, 20 cm, 25 m | 1.33 m | 1.25 m | 1.04 m | 0.002 m | 2.3 × 4.0 m, 3.1 m³ | 6.9 m³ | 26.8 km/h |
| pickup, 20 cm, 50 m | 1.34 m | 1.28 m | 1.03 m | 0.002 m | 2.3 × 4.0 m, 3.1 m³ | 15.4 m³ | 26.5 km/h |
| pickup, 20 cm, 100 m | 1.34 m | 1.28 m | 1.04 m | 0.005 m | 2.3 × 4.0 m, 3.2 m³ | 32.2 m³ | 26.5 km/h |
| pickup, 30 cm, 50 m | 1.57 m | 1.50 m | 1.22 m | 0.004 m | 2.3 × 4.5 m, 4.1 m³ | 22.3 m³ | 19.4 km/h |
| pickup, 30 cm, 100 m | 1.58 m | 1.51 m | 1.23 m | 0.004 m | 2.5 × 4.3 m, 4.1 m³ | 46.8 m³ | 19.4 km/h |
| pickup, 40 cm, 25 m | 1.78 m | 1.73 m | 1.35 m | 0.009 m | 2.8 × 4.8 m, 5.0 m³ | 13.2 m³ | 14.7 km/h |
| pickup, 40 cm, 50 m | 1.78 m | 1.73 m | 1.37 m | 0.009 m | 2.8 × 4.5 m, 5.0 m³ | 29.3 m³ | 14.5 km/h |
| pickup, 40 cm, 100 m | 1.79 m | 1.74 m | 1.37 m | 0.009 m | 2.8 × 4.5 m, 5.0 m³ | 61.5 m³ | 14.5 km/h |
| opening, 15 m | 2.27 m | 2.19 m | 1.80 m | 0.012 m | 3.0 × 5.5 m, 9.6 m³ | 16.1 m³ | 7.6 km/h (15 m in 11.3 s) |
| ATV, 30 cm, 40 m | 1.22 m | 1.15 m | 0.95 m | 0.001 m | 2.0 × 2.8 m, 1.6 m³ | 10.2 m³ | 11.7 km/h |
| tractor, 30 cm, 40 m | 1.57 m | 1.52 m | 1.24 m | 0.003 m | 2.5 × 4.5 m, 4.1 m³ | 17.5 m³ | 19.3 km/h |
| plow truck, 30 cm, 40 m | 1.90 m | 1.85 m | 1.48 m | 0.004 m | 3.0 × 5.5 m, 7.9 m³ | 25.1 m³ | 34.0 km/h |
| grader, 30 cm, 40 m | 1.91 m | 1.86 m | 1.48 m | 0.005 m | 3.0 × 6.0 m, 8.0 m³ | 24.5 m³ | 23.4 km/h |
| pickup, blade angled 30°, 30 cm, 40 m | 1.21 m | 1.11 m | 0.94 m | (see below) | 1.7 × 3.0 m, 1.4 m³ | 10.4 m³ | 19.2 km/h |
| plow truck, blade angled −30°, 30 cm, 40 m | 1.47 m | 1.43 m | 1.15 m | (see below) | 2.0 × 4.0 m, 2.5 m³ | 17.4 m³ | 36.4 km/h |
| pickup, driving 30° across the school's lot, 30 cm, 30 m | 1.47 m | 1.43 m | 1.13 m | 0.009 m | 2.2 × 4.3 m, 3.5 m³ | 12.4 m³ | 20.0 km/h |

| hand push | walked in 8 s | speed (last two thirds) | top while pushing | over the step, in front | left |
|---|---|---|---|---|---|
| bare hands, 15 cm | 2.8 m | 0.30 m/s | 0.44 m | 0.0000 m | 0.34 m |
| standard shovel, 15 cm | 17.0 m | 2.12 m/s | 0.46 m | 0.0000 m | 0.34 m |
| wide pusher, 15 cm | 21.3 m | 2.64 m/s | 0.69 m | 0.0000 m | 0.51 m |
| wide pusher, 30 cm | 15.2 m | 1.88 m/s | 0.95 m | 0.0003 m | 0.72 m |
| large scraper, 30 cm | 22.4 m | 2.81 m/s | 0.96 m | 0.0002 m | 0.74 m |
| snow sleigh, 30 cm | 23.3 m | 2.96 m/s | 0.96 m | 0.0005 m | 0.72 m |

- **No spikes.** In front of every blade, no cell stood more than 1.2 cm over the step while pushing,
  against 0.16–0.82 m before.
- **The pile.** It stops growing within 10–20 m, the same as before the fix, but lower:
  - 1.3 m, 1.6 m and 1.8 m for 20, 30 and 40 cm, against 1.9, 2.2 and 2.5 m before;
  - 2.3 m in the opening, against 4.1 m.
  - It carries the same load: 3.1, 4.1 and 5.0 m³.
  - After 25, 50 and 100 m it is the same mound, 2.3–2.8 m long and 4–4.8 m wide. The ridges grow
    with the distance: about two thirds of the snow.
- **Settled** (the blade raised, the truck backed off): 1.0, 1.2 and 1.4 m, against 1.15, 1.32 and
  1.48 m before. That is one rounded mound, and every cell is at the step.
- **Hand pushes.** None of them leaves anything over the step. Before, the large scraper had 3.6 cm
  and the sleigh 4.9 cm. The tops are much the same as before (0.41–0.96 m, against 0.47–1.08 m).
  - Their walking speed is within 1–14 % of before; they read 0.65 m as before.
  - The exception is the wide pusher in 30 cm: 15.3 m against 2.0 m. Before, the pile against it rose
    above the hips and the wading rule stopped the player; now it tumbles away (see the Issues in
    STATUS.md).
- **Volume:** conserved in every case to 2e-5 m³ (the opening) or better.


## The drag

The brief: the plow's berm drag must still slow the truck as its load grows, and a long push may not
get easier. With the roll the pile holds the same load as before (4.2 m³ at 30 cm), but lower and
further from the face, where a 0.65 m reading misses it. Read only to 0.65 m, every plow pushed
faster than before:
- the pickup at 30 cm: 26.2 km/h instead of 20.9;
- the plow truck: 43.7 km/h instead of 35.2.

Mean speed once the pile has formed, at full throttle, blade down and straight (the same probe):

| push | before the fix | the roll, 0.65 m reading | final |
|---|---|---|---|
| pickup, 20 cm | 28.0 km/h | 33.9 | 26.5 (−5 %) |
| pickup, 30 cm | 20.9 km/h | 26.2 | 19.4 (−7 %) |
| pickup, 40 cm | 15.7 km/h | 20.3 | 14.5 (−8 %) |
| pickup, the opening's first 15 m | 10.2 s | 8.7 s | 11.3 s (+11 %) |
| ATV, 30 cm | 12.4 km/h | 13.5 | 11.7 (−6 %) |
| tractor, 30 cm | 20.3 km/h | 22.8 | 19.3 (−5 %) |
| plow truck, 30 cm | 35.2 km/h | 43.7 | 34.0 (−3 %) |
| grader, 30 cm | 25.6 km/h | 30.0 | 23.4 (−9 %) |

How the reading was chosen:
- **A longer full-depth reach** (1.0 m, 1.3 m, then 0.6 + 0.4 × the half-width) needed a different
  length for every plow. It also read more of the untouched snow ahead. In the opening's 80 cm that
  slowed the very start, before any pile exists, below the scripted plow-out's give-up speed: fix 1's
  blade-down plow-out took 2 passes and 20.4 s instead of 1 and 8.9 s.
- **Counting only the pushed snow past 0.65 m** reads the pile and leaves the start as it was. The
  reach still has to grow with the blade (a wider blade's pile is bigger).
- The reach was set from each plow's break-even speed (measured at two reaches each): about 0.8 m for
  the ATV, 1.19 m for the pickup, 1.30 m for the grader, 1.41 m for the plow truck. The rule is at or
  beyond every one of them.
- No single rule matches every plow exactly: their old drag depended on how high each one's spike
  stood (the fast plow truck's 0.82 m, the ATV's 0.16 m). So every plow is now 3–9 % slower on a long
  straight push than before the fix, and none is faster.
- The speed moves in steps with the reach, because the reading counts whole 25 cm cell rows.

## Hand pushes

RMB held, walking east along Maple Street for 8 s from x = 20 m, looking 30° down (the probe, as
`test_pf2_every_blade_tumbles` but longer; speed after the first third). Both columns were measured
again with the same probe after the review's refinement. Hand pushes read their berm to 0.65 m, as
before; only the roll is new for them.

| tool, snow | walked, before → after | speed, before → after | top while pushing, before → after | over the step, before → after |
|---|---|---|---|---|
| bare hands, 15 cm | 2.9 → 2.9 m | 0.31 → 0.32 m/s | 0.47 → 0.41 m | 0 → 0 |
| standard shovel, 15 cm | 16.7 → 16.9 m | 2.09 → 2.11 m/s | 0.47 → 0.47 m | 0 → 0 |
| wide pusher, 15 cm | 20.2 → 21.3 m | 2.49 → 2.63 m/s | 0.78 → 0.70 m | 5 mm → 0 |
| wide pusher, 30 cm | 2.0 → 15.3 m | 0 → 1.88 m/s | 0.98 → 0.95 m | 3 mm → 0.3 mm |
| large scraper, 30 cm | 20.0 → 22.6 m | 2.50 → 2.85 m/s | 1.07 → 0.96 m | 3.6 cm → 0.3 mm |
| snow sleigh, 30 cm | 22.8 → 23.3 m | 2.89 → 2.96 m/s | 1.08 → 0.95 m | 4.9 cm → 0.1 mm |

- **Most tools** walk at about the same speed: bare hands, the standard shovel and the sleigh within
  3 %.
- **A little faster:** the wide pusher in 15 cm (+6 %) and the large scraper (+14 %). Their pile now
  lies a little further out than the 0.65 m they read.
- **The big change** is the wide pusher in 30 cm.
  - Before, its pile stood above the hips right in front of it after 2 m, and the wading rule stopped
    the player. Its own drag was no stronger: 0.45 against 0.49 now.
  - Now the pile tumbles away, and the player keeps pushing at 1.9 m/s.
- This fix doesn't change how hand pushes are read, because the brief asks that only of the plow.
  It is noted for the owner (`STATUS.md`, Issues) and in `PLAYTEST.md` item 23.

## Tests

New, in `tests/test_polish7.gd`, the "Playtest fix 2" group (`--only=polish7 --test=test_pf2_`, 4
tests, all pass):

- **`test_pf2_the_push_alone_never_spikes`: the op on its own, with no relaxation between steps.**
  - Four blades, 5 cm steps along 15 m of 30 cm: a plow (2.4 m, cast 0.6 m) straight and angled 30°, a
    hand tool (0.9 m, 0.38 m), and the plow back-dragging.
  - The guard is set as the vehicles set it.
  - After every step, no player-moved cell stands over the moved-snow step above a neighbour it could
    roll onto (at most 1e-7 m; the bound is 1e-6 m).
  - One `push_rng` draw per moved cell; the volume exact.
- **`test_pf2_long_pushes_tumble`: the done-when test.** The pickup with its plow pushes 50 m and
  100 m of 30 cm, blade down with its key, straight.
  - Every frame, from 1.5 m behind the blade (inside its guarded strip) to 12 m ahead: no cell over
    the step by more than `PF2_SPIKE` (3 cm). The most was 1.0 cm.
  - The top stays under `PF2_TOP` (1.7 m): 1.54–1.56 m while pushing, 1.50–1.52 m stopped, 1.22 m
    settled.
  - One mound, 2.5 × 4.5 m; once settled, every cell at the step.
  - No faster than before the fix: 19.8–19.9 km/h over the second half, against 20.9.
  - The volume conserved to 4e-7 m³.
  - The mound after 100 m is the same as after 50 m, not taller. The tops are within `PF2_SAME`
    (5 cm, where the truck stops on the grid): 1.52 m against 1.50 m stopped, 1.22 m against 1.22 m
    settled.
- **`test_pf2_the_opening`:** 15 m out of a new game's driveway, blade down, over the curb.
  - 3 seeds in both modes, all alike: 11.3 s.
  - At most 1.2 cm over the step; the top 2.27 m (under `PF2_TOP_OPENING`, 2.6 m).
  - Settled at the step; the volume conserved to 1.3e-5 m³.
- **`test_pf2_every_blade_tumbles`.** Every frame within 3 cm of the step, settled at the step, the
  volume exact:
  - every plow, 30 m of 30 cm. Tops: the pickup 1.54 m, the ATV 1.20 m, the tractor 1.55 m, the plow
    truck 1.85 m, the grader 1.88 m;
  - the pickup and the plow truck angled with their keys: 1.23 m and 1.39 m;
  - hand pushes for 5 s: bare hands and the standard shovel in 15 cm, the wide pusher in 30 cm;
  - back-drag for 3 s.

`PF2_SPIKE` is 3 cm because the relaxation still moves snow one edge at a time and rounds the tops.
The op itself leaves nothing over the step (the first test). In play a cell can be a little over the
step until the relaxation's next pass: 1.5 cm at most with a straight blade, 2.4 cm with the pickup's
blade angled. Before the fix the pile stood up to 0.45 m over it, 0.82 m for the plow truck.

The checks stop 1.5 m behind the blade, inside the strip its guard holds (2 m). Further back, the
edge of the lane it cut stands steep for a moment once the guard has passed, until the relaxation
settles it. That was the same before the fix (0.35–0.48 m over the step there, before and after),
and every test checks the whole path once settled.

What else the change touches, all run on the final code and all passing:

| suite | tests | what it covers |
|---|---|---|
| polish7 `test_pf1_` | 7 | fix 1's plow-out and run-ups |
| polish7 `test_s11_` | 8 | blade keys, back-drag |
| polish7 `test_s10_` | 6 | the plowed truck, its shove |
| polish5 `test_s12_` | 6 | the pickups in snow, banks, bogging, volume |
| polish5 `test_s11_grader_pass_unchanged` | 1 | the city's grader, unchanged |
| polish5 `s3_` | 6 | buildings as walls, the road rule removed |
| polish6 `test_s9_` | 5 | the spread band, marks, one draw per cell, settled piles |
| polish6 `test_s3_blade` | 1 | `push_rng`'s own stream |
| snow (whole suite) | 13 | conservation, `test_blade_push_*`, repose, the ceiling |
| gameplay `plow` | 2 | `test_vehicle_plow_and_stuck_pickup`, `test_plow_pushes_yard_snow_onto_road` |
| gameplay `push` | 3 | pushing over the curb, a mound conserving volume |
| gameplay `truck_keys` | 1 | the keys end to end, the windrow, plowing |
| gameplay `wading` | 2 | wading and the hip rule |
| systems `test_snow_ceiling_at_lamp_height` | 1 | a push against the 6 m ceiling |
| polish3 `test_no_snow_inside_the_houses` | 1 | pushes beside houses |
| polish5 `test_s13b_melting_ledger` | 1 | pushes onto the heated driveway, the ledger |

Notes on those runs:
- **Fix 1's scripted blade-down plow-out** is still 1 pass, now 9.8 s (8.9 s before this fix).
- **Fix 1's blade-up run-ups** are unchanged (5 pushes, 42.6 s), because the shove keeps its
  placement.
- **§11's garage-door drag** still slows the reverse: 15.1 km/h against 17.2 bare. The truck is
  never stuck by its own pile.

The parse check is clean. The full suite wasn't run (the round's rule for a playtest fix): CI runs it
on the PR.

## Performance

`perf.tscn`'s two plow scenarios, "hand push (RMB) in deep snow" and "plow truck pushing a berm",
before (HEAD's snow and vehicle code) and after (this fix).
- The PC was in use by other programs during these runs (about 60 % CPU from other apps). A full run
  first measured the plow scenario's frame at 14.4 ms average before the fix, and a later one at 7.2.
- So the comparison runs them back to back. A new `--only=plow` option (the world, idle outdoors, the
  blizzard + shovelling that sets them up, then the two scenarios) runs three pairs of before and
  after, alternated.
- The medians:

| scenario | | before | after |
|---|---|---|---|
| plow truck pushing a berm | frame avg / p95 | 7.09 / 11.30 ms | 8.04 / 13.30 ms |
| | relaxation p95 | 2.69 ms | 3.16 ms |
| | chunk mesh p95 | 5.42 ms | 5.86 ms |
| hand push (RMB) in deep snow | frame avg / p95 | 8.42 / 15.62 ms | 8.60 / 16.00 ms |
| | relaxation p95 | 8 µs | 8 µs |
| | chunk mesh p95 | 9.33 ms | 9.60 ms |

- **The brief's budgets**, relaxation within 2.5 ms and chunk rebuilds within 3.5 ms a frame, aren't
  met on this PC, before or after: the plow scenario was at 2.69 ms and 5.42 ms before the fix.
- **The fix adds about 0.5 ms to each** for the plow truck, the widest blade. Both counters stop at
  their budgets (`relax_usec`, `mesh_usec`) and finish the tile or chunk they're on, so their p95 sits
  just over the budget.
- **The roll's own cost shows in the frame time**, inside the push (physics): about 1 ms more on
  average, 2 ms at p95, for the plow truck. Hand pushes: 0.2 ms more.
- **One `Snow.blade_push` call**, timed on its own (no world, 30 cm of level snow, 60 m, median over
  1,800–6,000 calls):

| blade | before | after |
|---|---|---|
| the pickup's plow (2.4 m) | 61 µs | 264–273 µs |
| the plow truck (3.4 m) | 175 µs | 1,048–1,053 µs |
| the wide pusher (0.9 m) | 22 µs | 27–29 µs |

  The walk down the pile is most of it: each share of a lifted cell rolls 4–10 cells. Writing the
  roll's loop out and skipping the chunk sync cut 10–20 % without changing any result. Merging the
  shares that land on the same cell would save more, but it would change where the snow lands, so
  it was left out.
- **Other full-run scenarios after the fix** (the same machine, not compared pair by pair):
  - the pickup shoving deep snow (blade up: the shove doesn't roll): 7.6 ms average;
  - the 4 m map with a major event: 19.6 ms;
  - heating in a storm: 9.1 ms.

## Screenshots

`docs/polish7/shots/pf2-long-push/`, taken with `tests/shot.gd --long_push=50 --unlock=1 --hour=12
--weather=0 --fixed-fps 60`. The pickup with its plow pushes 50 m of 30 cm along Maple Street, blade
down, then brakes and holds.

- `before_50m_driving_camera.jpg` (HEAD's code): the pile's ragged top sticks up over the truck's cab
  (1.82 m in front of the blade).
- `after_50m_driving_camera.jpg` (this fix): the pile stays below the cab's roof (1.46 m), and the
  ridges it rolled off run along both sides of the lane.

The brief asked for the view from the driver's seat. The truck's cab view (its camera key) sits inside
the cab's own box: before and after it shows only the cab's inside, a dark wall across the windshield,
and not the pile. Both shots were taken that way and not kept. These two use the game's driving
camera behind the truck, the view the game drives with. Six images were taken in all (2 kept): the
2-shot limit was exceeded to find that out.

## Review

A review workflow ran four readers over the roll (conservation, walls and callers, the project's
rules, performance) against an earlier draft. Every finding was checked against the code here, and
these were fixed:
- **The guard's box as a wall.** The guard is a box aligned with the map, built along the travel
  direction, so with an angled blade or a diagonal heading it reaches past the face, into the cells
  where the blade drops its snow. A share there could find no open neighbour and stack to the ceiling.
  Now the guard is a wall for the roll only behind the face. The op-level test covers a 30° blade,
  and the tests cover angled pushes in play (the probe: a diagonal run across the school's lot, top
  1.46 m).
- **The curb as a wall** for the roll, which left the opening's 3.3 m stack against the curb. Now
  gated on `player_rule`.
- **The pickup's shove** rolled too, so its snow could roll into the truck's own path and change the
  bog and bank rules. It now passes `tumble = false`.
- **Ties broken in world-axis order**, which made a pile pushed east differ from one pushed north. Now
  broken in the blade's frame.
- **A source cell overdrawn by a 32-bit rounding** (about 1e-7 m below its floor). Now a store that
  rounds up is redone a step lower, and the comment says what is exact and what rounds.
- **Writing into a chunk blade_push hadn't synced** (a long roll near a chunk edge). The roll now syncs
  each chunk it enters.
- **A share at the 6 m ceiling** with no way down walked all 48 steps for nothing. It now stops there
  (kept, as before).
- **The per-step cost.** The roll now:
  - carries each cell's position along the blade from step to step;
  - keeps its bounds in locals;
  - tests the guard only behind the face;
  - writes its four neighbours out;
  - skips the chunk sync inside the cells `blade_push` has just synced.

  The results are identical: six probe cases, 59 output lines, matched line for line before and after.
  The calls are 10–20 % cheaper (see Performance).
- **The back-drag comment** said the dragged snow lands clear of the front wheels. It now says the pile
  tumbles on toward them.
- **The perf report** shows the frame time, not only the snow counters, which are capped by their
  own budgets.

### After the push: the design judge's refinement and three more speed checks

The workflow also had three designs for the plows' drag reading drafted and judged. The judge picked
the one built here: all the snow within 0.65 m, plus only the pushed snow out to `berm_reach`. It
suggested one refinement and three more speed checks, made after `e31ffff` was pushed.

**The refinement.** `e31ffff` had widened the whole rectangle `blade_push` works on to fit the longer
reading. For the plows that changed nothing: their rectangle already held it. For small blades (hand
tools) it also made the area marked dirty and queued for the relaxation about a cell larger on each
side, so their result after relaxing differed from before the fix by more than the roll. The push now
keeps the pre-fix rectangle (the push, the dirty and relaxed area, the sync). The reading has its own
rectangle, wider only where a plow's `berm_reach` passes the push's.

Checked with a probe of the op alone: 300 steps of 5 cm along 30 cm of level snow, at 0°, 30° and
135°, with and without the relaxation running between steps. Each run's snow arrays, the relaxation
queue and the returned `moved`/`berm`/`kept` were compared across three versions of the code:
- **With the roll off** (`tumble = false`), against the code before the fix: identical in all 48 runs
  (bare hands, the standard shovel, the wide pusher, the shove's arm, the ATV, the pickup, the pickup
  with the plow width upgrade, the grader). The only difference is the plows' `berm`, the intended
  reading.
- **Against `e31ffff`:** every plow and the shove are identical. The hand tools differ: `e31ffff`
  queued a larger area, and with the relaxation running that changed how much they moved over the
  300 steps by up to 7 %.
- In play (the hand-push probe above) the difference doesn't show at that probe's precision: `e31ffff`
  and the final code walk the same distances.

A second review (three readers, read-only: the bounds and edges of the map; the chunk sync and the
roll; every caller against the code before the fix) found nothing.

**The speed checks** (mean speed over the second half, full throttle, blade down and straight; the
same `_pf2_push` as the tests; the code before the fix against the final code):

| push | before the fix | final | top while pushing, before → final |
|---|---|---|---|
| plow truck, 20 cm, 100 m | 39.6 km/h | 39.1 (−1 %) | 2.81 → 1.61 m |
| pickup, 30 cm, 50 m, driving east | 20.9 km/h | 19.9 (−5 %) | 2.19 → 1.54 m |
| pickup, 30 cm, 50 m, driving west | 20.9 km/h | 19.8 (−5 %) | 2.11 → 1.55 m |
| pickup with the plow width upgrade, 30 cm, 50 m | 18.0 km/h | **15.1 (−16 %)** | 2.50 → 1.72 m |
| plow truck with the plow width upgrade, 30 cm, 50 m | 28.1 km/h | 26.6 (−5 %) | 3.81 → 2.01 m |

- No plow got easier; a pile pushed west matches one pushed east. Every run was spike-free (at most
  1.8 cm over the step while pushing, against 0.44–1.01 m before) with the volume exact.
- **The pickup with the plow width upgrade is 16 % slower** than before the fix, outside the 3–9 % of
  the plows' base blades. Its wider blade builds a bigger pile (1.72 m). A shorter reach barely
  changes it: taking the reach from the base width (1.22 m instead of 1.33 m) gives 15.4 km/h for the
  pickup (still −14 %), and 28.9 km/h for the plow truck, 3 % faster than before, which the brief
  rules out. So the drag is left as it is, and this is
  noted for the owner (`STATUS.md`, Issues) and in `PLAYTEST.md` item 19.
- These were measured with a probe, not added as tests.

Tests run on the final code: polish7 `test_pf2_` (4), `test_pf1_` (7), `test_s11_` (8), `test_s10_`
(6); polish6 `test_s9_` (5), `test_s3_blade`; polish5 `test_s11_grader_pass_unchanged`, `s3_` (6),
`test_s12_` (6), `test_s13b_melting_ledger`; the snow suite (13); gameplay `push` (3), `plow` (2),
`wading` (2): all pass. Parse check: 92 scripts, 0 errors. Perf wasn't rerun: the plows' op is
bit-identical, and a hand push now relaxes the same area as before the fix.

