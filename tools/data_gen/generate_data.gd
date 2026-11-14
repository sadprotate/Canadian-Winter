extends SceneTree
## Generator for the data .tres files: every tool, vehicle and upgrade profile, and balance.tres.
## Run: godot --headless --path <project> --script res://tools/data_gen/generate_data.gd [-- --out=<dir>]
## It writes into res://data/ unless --out names another folder (res://, user:// or an absolute
## path). It reproduces data/ value for value (polish 6 §1; tests/test_polish6.gd checks it), so a
## change to a data file goes here too. balance.tres holds BalanceData's defaults
## (scripts/data/balance_data.gd), which are kept equal to it. Written into res://data/, 37 of the
## 40 files come out unchanged (line endings aside); balance.tres leaves out the lines equal to their defaults and
## the two heated_*.tres get Godot's own ext_resource ids. Every value stays the same.

const DEFAULT_OUT := "res://data"


func _init() -> void:
	var out := DEFAULT_OUT
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	var failed := generate(out)
	if failed == 0:
		print("Data generated in %s." % out)
	quit(1 if failed > 0 else 0)


## Every data file, by its path under the data folder ("tools/hands.tres", "balance.tres", …).
static func build() -> Dictionary:
	var out := {}
	_tools(out)
	_vehicles(out)
	_upgrades(out)
	_balance(out)
	return out


## Writes every data file into out_dir (its tools/, vehicles/ and upgrades/ folders are made if
## missing). Returns how many files failed to save.
static func generate(out_dir: String) -> int:
	var failed := 0
	var files := build()
	for rel in files.keys():
		var path: String = out_dir.path_join(rel)
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var err := ResourceSaver.save(files[rel], path)
		if err != OK:
			push_error("Failed to save %s (%d)" % [path, err])
			failed += 1
	return failed


static func _tool(out: Dictionary, id: String, name: String, kind: int, tier: int, price: int, desc: String, p: Dictionary) -> void:
	var t := ToolData.new()
	t.id = StringName(id)
	t.display_name = name
	t.kind = kind
	t.tier = tier
	t.price = price
	t.description = desc
	for k in p.keys():
		t.set(k, p[k])
	out["tools/%s.tres" % id] = t


## Tool profiles (polish §3). Every shovel-type tool fills while the primary action is held and
## swept through the snow, throws on release and pushes with the secondary action:
##   capacity (m3) · fill_rate (m3/s) · bite (m cut per pass) · throw_distance (m)
##   (polish 6 §8.2: the six shovel-type tools' capacity and fill rate doubled, bare hands' not;
##   §8.1b, the owner's decision: bare hands' fill rate ×1.3, 0.085 → 0.1105)
##   throw_recovery_s (s: the throw rhythm, polish 6 §8.1; the electric shovel's and the blowers'
##   chute interval)
##   push_width (m) · push_strength (berm m3 at half speed)
## Descriptions name keys as {action} placeholders (polish 5 §2: Settings.with_keys()).
static func _tools(out: Dictionary) -> void:
	var K := ToolData.Kind
	_tool(out, "hands", "Bare Hands", K.HANDS, 0, 0, "Cup your hands and sweep them through the snow, then toss it a metre or two. A weak, short push with flat palms. Slow — but every scoop leaves a dent.",
		{"width": 0.4, "reach": 0.3, "capacity": 0.03, "fill_rate": 0.1105, "bite": 0.26, "sweep_reach": 1.15,
		"cycle_time": 0.5, "throw_distance": 1.8, "throw_recovery_s": 0.5, "throw_angle_deg": 38.0, "scrape_floor": 0.006,
		"push_width": 0.5, "push_strength": 0.035, "engaged_speed_mult": 0.75,
		"primary_color": Color(0.2, 0.2, 0.24), "particle_amount": 6, "action_sound": &"hand_dig"})
	_tool(out, "small_shovel", "Small Snow Shovel", K.SHOVEL, 1, 25, "A short plastic shovel: the all-rounder. Fills fast, throws well, pushes a little.",
		{"width": 0.34, "reach": 0.4, "capacity": 0.1, "fill_rate": 0.26, "bite": 0.4, "sweep_reach": 1.6,
		"cycle_time": 0.4, "throw_distance": 4.2, "throw_recovery_s": 0.7, "throw_angle_deg": 42.0, "scrape_floor": 0.004,
		"push_width": 0.36, "push_strength": 0.09, "engaged_speed_mult": 0.85,
		"primary_color": Color(0.95, 0.47, 0.1), "particle_amount": 10, "action_sound": &"shovel_scoop"})
	_tool(out, "standard_shovel", "Standard Snow Shovel", K.SHOVEL, 2, 35, "Full-size shovel with a metal wear strip. Bigger loads, the longest hand throw.",
		{"width": 0.46, "reach": 0.45, "capacity": 0.13, "fill_rate": 0.32, "bite": 0.5, "sweep_reach": 1.7,
		"cycle_time": 0.42, "throw_distance": 5.2, "throw_recovery_s": 0.7, "throw_angle_deg": 44.0, "scrape_floor": 0.003,
		"push_width": 0.48, "push_strength": 0.14, "engaged_speed_mult": 0.86,
		"primary_color": Color(0.2, 0.45, 0.85), "particle_amount": 14, "action_sound": &"shovel_scoop"})
	_tool(out, "wide_pusher", "Wide Snow Pusher", K.PUSHER, 3, 79, "A 90 cm push blade. A strong pusher: hold {secondary} and walk. It can throw, but only a short, clumsy toss.",
		{"width": 0.9, "reach": 0.3, "capacity": 0.09, "fill_rate": 0.18, "bite": 0.15, "sweep_reach": 1.8,
		"cycle_time": 0.5, "throw_distance": 2.2, "throw_recovery_s": 0.8, "throw_angle_deg": 32.0, "scrape_floor": 0.003,
		"push_width": 0.9, "push_strength": 0.5, "engaged_speed_mult": 0.92,
		"primary_color": Color(0.15, 0.55, 0.3), "particle_amount": 16, "loop_sound": &"push_scrape"})
	_tool(out, "snow_scraper", "Snow Scraper", K.SCRAPER, 4, 145, "Steel-edged blade that pushes hard and scrapes to bare pavement. {tool_angle} angles the blade left/right to windrow snow aside.",
		{"width": 0.75, "reach": 0.3, "capacity": 0.1, "fill_rate": 0.2, "bite": 0.21, "sweep_reach": 1.8,
		"cycle_time": 0.5, "throw_distance": 2.8, "throw_recovery_s": 0.8, "throw_angle_deg": 34.0, "scrape_floor": 0.0,
		"push_width": 0.75, "push_strength": 0.6, "engaged_speed_mult": 0.9,
		"angle_adjustable": true, "max_angle_deg": 30.0, "primary_color": Color(0.85, 0.15, 0.12),
		"particle_amount": 18, "loop_sound": &"push_scrape"})
	_tool(out, "large_scraper", "Large Snow Scraper", K.SCRAPER, 5, 265, "A {width} steel blade on wheels: halfway between a shovel and a pusher. Throws a decent load, pushes very hard. {tool_angle} angles the blade.",
		{"width": 1.0, "reach": 0.3, "capacity": 0.16, "fill_rate": 0.32, "bite": 0.23, "sweep_reach": 1.9,
		"cycle_time": 0.5, "throw_distance": 3.4, "throw_recovery_s": 0.8, "throw_angle_deg": 38.0, "scrape_floor": 0.0,
		"push_width": 1.2, "push_strength": 0.95, "engaged_speed_mult": 0.88,
		"angle_adjustable": true, "max_angle_deg": 30.0, "primary_color": Color(0.9, 0.75, 0.1),
		"particle_amount": 22, "loop_sound": &"push_scrape"})
	_tool(out, "snow_sleigh", "Snow Sleigh", K.SLEIGH, 6, 320, "Big scoop on runners. Loads a huge amount but barely throws — it just tips the load out in front of you. The strongest hand pusher.",
		{"width": 0.8, "reach": 0.45, "capacity": 0.8, "fill_rate": 0.64, "bite": 0.9, "sweep_reach": 1.6,
		"cycle_time": 0.6, "throw_distance": 1.0, "throw_recovery_s": 1.0, "throw_angle_deg": 28.0, "scrape_floor": 0.006,
		"push_width": 0.8, "push_strength": 1.4, "engaged_speed_mult": 0.8,
		"primary_color": Color(0.1, 0.35, 0.75), "particle_amount": 16, "loop_sound": &"push_scrape",
		"action_sound": &"snow_land"})
	_tool(out, "electric_shovel", "Electric Snow Shovel", K.ELECTRIC_SHOVEL, 7, 480, "Battery power shovel. Hold {primary} to chew through snow and toss it ahead automatically; {secondary} pushes.",
		{"width": 0.32, "reach": 0.35, "rate": 0.05, "throw_distance": 5.0, "throw_recovery_s": 0.15, "scrape_floor": 0.004,
		"push_width": 0.34, "push_strength": 0.08,
		"engaged_speed_mult": 0.7, "throw_angle_deg": 38.0, "primary_color": Color(0.15, 0.7, 0.35),
		"particle_amount": 20, "loop_sound": &"electric_motor"})
	_tool(out, "small_blower", "Small Walk-Behind Snowblower", K.WALK_BLOWER, 8, 790, "Single-stage blower. Grab it with {interact}, hold {primary} to run, {veh_aim_left}/{veh_aim_right} to turn the chute.",
		{"width": 0.56, "reach": 0.35, "rate": 0.065, "throw_distance": 8.0, "throw_recovery_s": 0.18, "scrape_floor": 0.008,
		"engaged_speed_mult": 0.42, "throw_angle_deg": 40.0, "uses_slot": false,
		"primary_color": Color(0.85, 0.12, 0.1), "particle_amount": 40, "loop_sound": &"blower_small"})
	_tool(out, "large_blower", "Large Walk-Behind Snowblower", K.WALK_BLOWER, 9, 1690, "Two-stage blower with a wide intake and long throw.",
		{"width": 0.78, "reach": 0.4, "rate": 0.14, "throw_distance": 12.5, "throw_recovery_s": 0.18, "scrape_floor": 0.006,
		"engaged_speed_mult": 0.4, "throw_angle_deg": 42.0, "uses_slot": false,
		"primary_color": Color(0.95, 0.55, 0.05), "particle_amount": 60, "loop_sound": &"blower_large"})


static func _veh(out: Dictionary, id: String, name: String, kind: int, price: int, desc: String, p: Dictionary) -> void:
	var v := VehicleData.new()
	v.id = StringName(id)
	v.display_name = name
	v.kind = kind
	v.price = price
	v.description = desc
	for k in p.keys():
		v.set(k, p[k])
	out["vehicles/%s.tres" % id] = v


static func _vehicles(out: Dictionary) -> void:
	var K := VehicleData.Kind
	_veh(out, "pickup", "Pickup Truck", K.PICKUP, 0, "Your four-wheel-drive pickup. Gets stuck in deep snow.",
		{"max_speed": 15.0, "clearance": 0.3, "traction": 0.55, "length": 5.4, "width": 2.0, "height": 1.9,
		"body_color": Color(0.43, 0.45, 0.48), "engine_sound": &"engine_truck"})
	_veh(out, "pickup_plow", "Pickup Truck with Front Plow", K.PICKUP_PLOW, 3400, "Your pickup fitted with a permanent 2.4 m angling plow.",
		{"max_speed": 14.0, "clearance": 0.34, "traction": 0.62, "length": 6.0, "width": 2.4, "height": 1.9,
		"has_plow": true, "blade_width": 2.4, "blade_capacity": 2.8, "blade_max_angle_deg": 30.0,
		"body_color": Color(0.43, 0.45, 0.48), "engine_sound": &"engine_truck"})
	_veh(out, "atv_blade", "ATV with Blade", K.ATV, 6500, "Nimble quad with a 1.5 m blade. Open seat: no heated cabin.",
		{"max_speed": 11.0, "clearance": 0.26, "traction": 0.75, "length": 2.6, "width": 1.5, "height": 1.2,
		"wheelbase": 1.4, "turn_rate": 2.0, "heated_cabin": false, "has_plow": true, "blade_width": 1.5,
		"blade_capacity": 1.3, "body_color": Color(0.15, 0.35, 0.2), "engine_sound": &"engine_small", "engine_pitch": 1.3})
	_veh(out, "tractor_blade", "Tractor with Snow Blade", K.TRACTOR_BLADE, 14000, "Compact tractor with a heavy 2.4 m blade and heated cab.",
		{"max_speed": 8.5, "clearance": 0.5, "traction": 0.85, "length": 4.2, "width": 2.4, "height": 2.6,
		"wheelbase": 2.0, "turn_rate": 1.6, "has_plow": true, "blade_width": 2.4, "blade_capacity": 4.5,
		"body_color": Color(0.8, 0.12, 0.1), "engine_sound": &"engine_diesel"})
	_veh(out, "tractor_blower", "Tractor with Snowblower", K.TRACTOR_BLOWER, 22000, "Tractor with a front-mounted 2.1 m snowblower. {veh_aim_left}/{veh_aim_right} turns the chute.",
		{"max_speed": 7.5, "clearance": 0.55, "traction": 0.85, "length": 4.4, "width": 2.4, "height": 2.6,
		"wheelbase": 2.0, "turn_rate": 1.5, "has_blower": true, "blower_width": 2.1, "blower_rate": 0.95,
		"blower_throw": 16.0, "body_color": Color(0.15, 0.45, 0.2), "engine_sound": &"engine_diesel"})
	_veh(out, "grader", "Motor Grader", K.GRADER, 48000, "Municipal-style grader with a 3.7 m mid-mounted blade.",
		{"max_speed": 11.0, "clearance": 0.55, "traction": 0.9, "length": 8.5, "width": 2.6, "height": 3.2,
		"wheelbase": 6.0, "turn_rate": 0.9, "has_plow": true, "blade_width": 3.7, "blade_capacity": 9.0,
		"blade_max_angle_deg": 35.0, "blade_floor": 0.01, "body_color": Color(0.95, 0.72, 0.1),
		"engine_sound": &"engine_diesel", "engine_pitch": 0.8})
	_veh(out, "plow_truck", "Large Snowplow Truck", K.PLOW_TRUCK, 65000, "Tandem plow truck with a 3.4 m angling plow.",
		{"max_speed": 15.0, "clearance": 0.48, "traction": 0.85, "length": 8.0, "width": 2.6, "height": 3.3,
		"wheelbase": 4.8, "turn_rate": 1.0, "has_plow": true, "blade_width": 3.4, "blade_capacity": 8.0,
		"body_color": Color(0.95, 0.45, 0.08), "engine_sound": &"engine_diesel", "engine_pitch": 0.75})
	_veh(out, "rotary_blower", "Large Rotary Snowblower", K.ROTARY, 90000, "Huge rotary blower. Eats snowbanks and throws them 25 m.",
		{"max_speed": 6.5, "clearance": 0.8, "traction": 0.95, "length": 7.5, "width": 2.8, "height": 3.4,
		"wheelbase": 4.0, "turn_rate": 0.9, "has_blower": true, "blower_width": 2.7, "blower_rate": 2.4,
		"blower_throw": 25.0, "body_color": Color(0.9, 0.6, 0.08), "engine_sound": &"engine_diesel", "engine_pitch": 0.65})
	_veh(out, "dump_truck", "Snow Dump Truck", K.DUMP_TRUCK, 38000, "Haul snow away. Blow or throw snow into the bed, then dump it at the Snow Dump lot ({veh_tool}).",
		{"max_speed": 13.0, "clearance": 0.42, "traction": 0.8, "length": 8.0, "width": 2.6, "height": 3.2,
		"wheelbase": 4.6, "turn_rate": 1.0, "dump_capacity": 12.0, "body_color": Color(0.2, 0.3, 0.55),
		"engine_sound": &"engine_diesel", "engine_pitch": 0.8})


static func _up(out: Dictionary, id: String, name: String, cat: int, price: int, desc: String, stat: String, value: float, requires := "", pickup := false) -> void:
	var u := UpgradeData.new()
	u.id = StringName(id)
	u.display_name = name
	u.category = cat
	u.price = price
	u.description = desc
	u.stat = StringName(stat)
	u.value = value
	u.requires = StringName(requires)
	u.requires_pickup = pickup
	out["upgrades/%s.tres" % id] = u


## Polish 5 §13: the tool, machine and vehicle upgrades here (and pickup_plow) are no longer sold —
## they are the templates of every item's own levels (ItemUpgrades) — and the clothing became the
## insulated coat (Equipment). All are still loaded for old saves (Catalog).
static func _upgrades(out: Dictionary) -> void:
	var C := UpgradeData.Category
	_up(out, "shovel_capacity_1", "Reinforced Shovel Blades", C.TOOL, 60, "+25% load capacity and fill speed for your hands and every shovel, pusher, scraper and sleigh.", "shovel_capacity", 1.25)
	_up(out, "shovel_capacity_2", "Deep-Scoop Blades", C.TOOL, 160, "+25% more load capacity and fill speed.", "shovel_capacity", 1.25, "shovel_capacity_1")
	_up(out, "throw_1", "Ergonomic Handles", C.TOOL, 80, "+25% throw distance for hands and every shovel-type tool.", "throw_distance", 1.25)
	_up(out, "throw_2", "Pro Throwing Technique", C.TOOL, 190, "+20% more throw distance.", "throw_distance", 1.2, "throw_1")
	_up(out, "blade_width_1", "Blade Extensions", C.TOOL, 120, "+15% push width for every hand tool.", "blade_width", 1.15)
	_up(out, "clear_speed_1", "Ball-Bearing Wheels", C.TOOL, 140, "Push 15% harder and faster with every hand tool.", "push_speed", 1.15)
	_up(out, "blower_intake_1", "Blower Impeller Upgrade", C.MACHINE, 420, "+30% walk-behind blower intake rate.", "blower_rate", 1.3)
	_up(out, "blower_throw_1", "High-Velocity Chute", C.MACHINE, 360, "+30% walk-behind blower throw distance.", "blower_throw", 1.3)
	_up(out, "pickup_plow", "Pickup Front Plow Installation", C.VEHICLE, 3400, "Permanent 2.4 m angling plow for your pickup. Drive the pickup to the store lot to have it installed.", "pickup_plow", 1.0, "", true)
	_up(out, "vehicle_speed_1", "Hydraulic Tune-Up", C.VEHICLE, 1200, "Vehicles clear 20% faster (blade/blower drag reduced).", "vehicle_clear_speed", 1.2)
	_up(out, "vehicle_width_1", "Blade Wing Extensions", C.VEHICLE, 950, "+15% vehicle plow width.", "vehicle_blade_width", 1.15)
	_up(out, "vehicle_blower_1", "Turbo Blower Fan", C.VEHICLE, 1800, "+30% vehicle blower rate and throw.", "vehicle_blower", 1.3)
	_up(out, "clothing_1", "Insulated Work Jacket", C.CLOTHING, 150, "You lose warmth 20% slower outdoors (Survival).", "cold_protection", 0.8)
	_up(out, "clothing_2", "Arctic Parka & Mitts", C.CLOTHING, 420, "You lose warmth another 25% slower (Survival).", "cold_protection", 0.75, "clothing_1")
	_up(out, "weather_pro", "WeatherWise Pro App", C.WEATHER, 90, "3-day forecast with snowfall amounts and timing.", "forecast_days", 3.0)
	_up(out, "weather_radar", "Radar+ Subscription", C.WEATHER, 380, "7-day forecast with hourly detail and early storm warnings.", "forecast_days", 7.0, "weather_pro")
	_up(out, "furnace", "High-Efficiency Furnace", C.PROPERTY, 650, "Your house warms you up 60% faster (Survival).", "house_warm", 1.6)
	_up(out, "tool_rack", "Garage Tool Rack", C.PROPERTY, 90, "A wall rack beside your garage that holds 8 tools.", "tool_rack", 1.0, "", true)
	# Polish 5 §13b: the heated driveway and heated path (Heating).
	_up(out, "heated_driveway", "Heated Driveway", C.PROPERTY, 4200, "Cables under your driveway melt a light snowfall as it lands; a storm is too much for them. Uses power while melting (hydro bill).", "heated_driveway", 1.0)
	_up(out, "heated_path", "Heated Path", C.PROPERTY, 1500, "Cables under your front walk, steps and porch melt a light snowfall as it lands; a storm is too much for them. Uses power while melting (hydro bill).", "heated_path", 1.0)


## balance.tres: BalanceData's defaults, with the values below set explicitly (each equals its
## default; kept as the record of when it changed).
static func _balance(out: Dictionary) -> void:
	var b := BalanceData.new()
	b.box_completion = 0.90          # polish 3: a box completes at 90 % cleared (was 98 %)
	# Polish 4 §1: storm onset and the forecast model.
	b.storm_onset_cm_h = 1.0
	b.storm_onset_mean_frac = 0.5
	b.fc_error_base = 0.06
	b.fc_error_per_day = 0.12        # polish 5 §8: was 0.22
	b.fc_timing_h_per_day = 0.25     # polish 5 §8: was 2.5
	b.fc_temp_error_per_day = 1.6
	b.radio_surprise_horizon_h = 3.0 # polish 5 §8: was 1.0 (the radio's whole window)
	b.forecast_skill = 1.0
	b.min_scoop_hold_s = 0.25        # polish 6 §8.1: a release sooner than this throws nothing
	b.upgrade_hands_capacity_step = 1.75  # polish 6 §8.2: bare hands' capacity levels (the ladder)
	b.pickup_stuck_depth = 0.9       # polish 7 playtest fix 1: was 0.6 (the first morning's ~80 cm held the truck)
	b.garage_rack_slots = 6          # polish 8 §15: the garage's tool rack
	b.garage_snow_melt_per_hour = 0.3  # polish 8 §15: a vehicle's roof snow melts off in the garage
	out["balance.tres"] = b
