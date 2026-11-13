# Contracts: how your equipment counts

This doc covers only how the player's equipment counts for the contract board: the size of the
listings it posts and the street lock. The rest of contracts (bidding, tiers, due times, boxes) is
not described here yet.

## What it does for the player

- The board posts residential jobs no bigger than your best equipment clears in a day (7 a.m. to
  9 p.m.). With hand tools and shovels it posts small jobs; better tools and machines raise the cap.
- Your own truck, the pickup with its plow that a new game starts with, counts as hand tools here: it
  doesn't make the day-one listings bigger.
- At the City tier, street sections also need "a plow or a blower vehicle". Your truck's plow counts,
  so street sections open on reputation alone. Sidewalk sections need only the reputation.

## How it works

- `Contracts.equipment_capability()` gives your best equipment level:
  - 3: a vehicle with a plow or a blower in `Game.vehicles`, except the pickup with its plow
    (`VehicleData.Kind.PICKUP_PLOW`, the starting truck), which counts as hand tools.
  - 2: a small or large blower you own.
  - 1: a wide pusher, a snow scraper or large scraper, the sleigh or the electric shovel.
  - 0: hands and shovels.
  A vehicle counts whether or not its keys have been found.
- `EQUIP_RATE` (m³ per real second at a human pace, one entry per level) scales the residential cap:
  `res_cap_m3() = listing_res_max_m3 × EQUIP_RATE[capability] / EQUIP_RATE[0]`.
  `_generate_listings` posts no residential job bigger than that.
- `listing_needs_vehicle(l)`: a street section (`target` starting `road:`) when `Game.vehicles` has no
  vehicle with `has_plow` or `has_blower`. This check is separate from the capability: the starting
  truck's plow satisfies it. `listing_lock_text` shows "Needs reputation N" first (above your tier),
  then "Needs a plow or a blower vehicle". `place_bid` refuses a locked listing.
- Edge cases:
  - An older save with the plain pickup has no plow vehicle: its street sections stay locked until it
    gets one, as before.
  - An older save whose pickup had the front plow fitted holds a `pickup_plow` too. Like the starting
    truck, it counts as hand tools for listing size and opens street sections.
  - The dump truck has neither a plow nor a blower: it counts for nothing.

## Where it lives

- `scripts/autoload/contracts.gd`: `EQUIP_RATE`, `equipment_capability()`, `res_cap_m3()`,
  `listing_needs_vehicle()`, `listing_lock_text()`, `listing_locked()`, `_generate_listings()`.
- `scripts/ui/computer_ui.gd`: the board shows the lock line in place of the bid controls.
- `tests/contract_bench.gd`: the pacing bench gives a good player the plow truck (`plow_truck`) at the
  City tier.

## Connects to

- `Game.vehicles` (ids → `Catalog.vehicle()` → `VehicleData.has_plow`, `has_blower`, `kind`),
  `Game.owns_tool()`.
- Balance: `listing_res_max_m3`, `rep_tier_thresholds`.
- Vehicles: see [vehicles.md](vehicles.md) for the starting truck.

## How to test

- `--only=polish7 --test=test_s10_starting_truck_and_contracts`: capability 0 with the starting
  truck; day one's listings are the same as with no vehicle; a street section isn't vehicle-locked
  with it, and is without it.
- `--only=polish5 --test=test_s10b_street_needs_a_vehicle`: no vehicle locks a street section (board
  and `place_bid`); the starting truck opens it at capability 0; the plow truck opens it at 3.
- `--only=polish5 --test=test_s10_paths_first`: no residential listing over the cap with the starting
  gear.

## Decisions

- Round 5 §10a: listing size follows the best equipment (`EQUIP_RATE`), measured with the contract
  bench.
- Round 5 §10b: street sections need a plow or a blower vehicle as well as the City tier.
- Round 7 §10: the truck starts with its plow. It counts as hand tools for listing size, so day one
  doesn't change, but it satisfies the street requirement.

## Known issues

- None known.
