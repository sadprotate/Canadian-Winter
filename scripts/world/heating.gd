class_name Heating
extends RefCounted
## Polish 5 §13: what melts snow — the heated pad (equipment, wherever it is put down) and the
## heated driveway and heated path (house upgrades: the player's two boxes). Melting is a world
## rate on the game clock: Clock._systems_advance calls advance(step) on every clock step — the
## frame's step at 1×, every fast-forward substep, every step of a sleep or skip — so it runs
## through the same code at any speed (the 1×/2×/10× equality test covers it).
##
## Each source melts in small slices: its game minutes add up (Economy.heat_acc, saved) until they
## melt QUANTUM of depth, then every cell under it loses up to that much off its top (Snow.melt_rect:
## the one sanctioned loss of snow besides the box snap, kept in the ledger Snow.melted). So a pad
## melts a few times a second at 1× and a heated box every few game minutes, and a cell is never
## re-meshed every frame. A source draws power while it melts: balance.melt_cost_per_m3 for every m³
## it melts adds up in Economy.heat_used (Survival) and goes on the next hydro bill. A power cut
## (Survival.power_on false) stops every source: nothing melts, nothing is billed.

# Polish 6 §2: classes added in polish 5, by path rather than global name, so this script still
# loads when the editor's class cache predates a pull.
const _Equipment := preload("res://scripts/data/equipment.gd")

## Depth (m) a source melts at a time.
const QUANTUM := 0.002
## A slice that melted less than this (m³: a dusting) doesn't light the pad's lamp.
const MIN_RUN := 1e-5

## Game minute each source last melted something (for the pad's lamp; not saved).
static var last_melt: Dictionary = {}


## The sources now: [{id, rects, rate (m of depth per game minute), area (m²), box (the clearing box
## it heats, "" for the pad)}].
static func sources() -> Array:
	var out := []
	var b: BalanceData = Catalog.balance
	if _Equipment.pad_placed():
		out.append({"id": "pad", "rects": [_Equipment.pad_rect()], "rate": b.pad_melt_cm_h / 6000.0,
			"area": _Equipment.PAD_SIZE.x * _Equipment.PAD_SIZE.y, "box": ""})
	if Game.has_upgrade(&"heated_driveway") or Game.has_upgrade(&"heated_path"):
		for kind in ["driveway", "path"]:
			if not Game.has_upgrade(StringName("heated_" + kind)):
				continue
			var box := Boxes.get_box(Boxes.lot_box(Layout.player_lot, kind))
			if box.is_empty():
				continue
			out.append({"id": "heated_" + kind, "rects": box["rects"], "rate": b.heated_melt_cm_h / 6000.0,
				"area": float(box["area"]), "box": box["id"]})
	return out


## The clearing boxes that are heated (measured hourly during skips too, so they complete as they
## melt).
static func box_ids() -> Array:
	var out := []
	for kind in ["driveway", "path"]:
		if Game.has_upgrade(StringName("heated_" + kind)):
			out.append(Boxes.lot_box(Layout.player_lot, kind))
	return out


## One clock step (game minutes) of every source. Called by Clock._systems_advance.
static func advance(step_min: float) -> void:
	if step_min <= 0.0 or not Snow.initialized:
		return
	var src := sources()
	if src.is_empty():
		if not Economy.heat_acc.is_empty():
			Economy.heat_acc.clear()
		return
	var powered := Survival.power_on
	if Economy.heat_acc.size() > src.size():
		# A source that went away (the pad picked up) keeps no minutes.
		var ids := src.map(func(x): return x["id"])
		for k in Economy.heat_acc.keys():
			if not ids.has(k):
				Economy.heat_acc.erase(k)
	for s in src:
		var id: String = s["id"]
		if not powered:
			# A power cut: the cables are cold — nothing melts, nothing is billed.
			Economy.heat_acc.erase(id)
			continue
		var acc := float(Economy.heat_acc.get(id, 0.0)) + step_min
		var amount := acc * float(s["rate"])
		if amount < QUANTUM:
			Economy.heat_acc[id] = acc
			continue
		Economy.heat_acc[id] = 0.0
		var v := 0.0
		for r in s["rects"]:
			v += Snow.melt_rect(r, amount)
		if v > MIN_RUN:
			last_melt[id] = Clock.minutes
		if v > 0.0 and Game.is_survival():
			Economy.heat_used += v * Catalog.balance.melt_cost_per_m3


## Is a source melting right now (it melted within the last few slices)? For the pad's lamp.
static func running(id: String) -> bool:
	if not Survival.power_on or not last_melt.has(id):
		return false
	return Clock.minutes - float(last_melt[id]) <= 3.0


## What each source costs an hour at most, melting at its rate ($), by name — the Bills app's line.
static func hourly_costs() -> Array:
	var out := []
	for s in sources():
		var nm: String = {"pad": "heated pad", "heated_driveway": "heated driveway", "heated_path": "heated path"}.get(s["id"], s["id"])
		out.append([nm, float(s["rate"]) * 60.0 * float(s["area"]) * Catalog.balance.melt_cost_per_m3])
	return out
