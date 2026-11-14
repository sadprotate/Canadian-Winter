class_name HelpText
extends RefCounted
## The neighbor's explanations (Part 19.9), reused by the computer Help app.


static func explanation(survival: bool) -> Array:
	var out := []
	out.append({"speaker": "Gerry", "text": "There — sit by the fire a minute. You were turning blue out there!"})
	if survival:
		out.append({"speaker": "Gerry", "text": "Listen, the cold is no joke this winter. You've seen it creep up on you out there — keep an eye on your warmth at the bottom of the screen."})
		out.append({"speaker": "Gerry", "text": "Outside you cool down — faster when it's bitterly cold, windy, or in a blizzard. Warm up at home by the heat, in a heated truck cab, or crack one of those heating pouches."})
	else:
		out.append({"speaker": "Gerry", "text": "Cold winter, eh? Good thing you're a tough one. Dress warm and enjoy the snow."})
	out.append({"speaker": "Gerry", "text": "Now, come look at my computer. Everything for the business goes through one of these: ordering equipment, finding work, the forecast, paying your bills. You've got one at home too — I've set it up for you, so it's unlocked now."})
	out.append({"speaker": "Gerry", "text": "Need a tool or a machine? Order it on the computer from Northern Supply Co. at %s. They put your order out in their parking lot — you have to go pick it up yourself. They're open 7 in the morning till 9 at night." % Layout.building_by_id("store")["address"]})
	out.append({"speaker": "Gerry", "text": "You can buy upgrades there too: bigger shovel blades, better throws, warmer jackets, even a fancy weather app."})
	out.append({"speaker": "Gerry", "text": "The contract board lists people who need snow cleared. You put in a bid; other outfits bid too, so price it right. Jobs near your other clients are easier to win. Some are one-time, some want you all winter, every time it snows."})
	if survival:
		out.append({"speaker": "Gerry", "text": "And pay your hydro bill on the computer before the 15th — that letter in your mailbox. Miss it and they cut the power at midnight, and your house goes cold in a day."})
	out.append({"speaker": "Gerry", "text": "Check the forecast on your TV, the radio or the computer. The city grader comes by every Monday and Friday, with a crew for the sidewalks — the computer shows when. It'll leave a wall of snow across your driveway, mind you."})
	out.append({"speaker": "Gerry", "text": "That's about it. Thanks again, neighbour. Now get home before you freeze — and good luck with the business!"})
	return out


## Polish 5 §4: when Gerry gives you his trail he adds the two ways to move snow, with the keys
## read from the input map; talking to him again during the job repeats it. Spoken on the HUD.
## Polish 8 §17: with hints on he says only the first line and the rest opens as the hint
## "gerry_snow" (the same wording); with hints off he says them all, as before.
static func snow_tips() -> Array:
	var out := []
	for t in ["Now, two ways to move snow.",
			"Hold [%s] and sweep through the snow to fill your shovel, then let go to throw it. That gets it up over the banks." % Settings.action_label("primary"),
			"Or hold [%s] and walk to push it ahead of you. Quick on a long flat walk, but it piles up in front of you." % Settings.action_label("secondary"),
			"Clear my walk inside the blue line, from the sidewalk up to my door."]:
		out.append({"speaker": "Gerry", "text": t, "tip": true})
	return out


# -----------------------------------------------------------------------------
# Polish 8 §17: the hints (the hint panel). A hint is {title, pages}; every key in it is an
# {action} placeholder, filled with Settings.with_keys() when it shows, so a rebind shows at once.
# The wording is what these tips said before (Gerry's, the first-drive panel's, the pickup
# notifications'), split into pages where long. Every hint's content is also in the Help app.
# -----------------------------------------------------------------------------

## Gerry's how-to at the job beat: scoop and throw, push, the outlined trail.
const GERRY_SNOW := {"title": "Two ways to move snow", "pages": [
	"Hold [{primary}] and sweep through the snow to fill your shovel, then let go to throw it. That gets it up over the banks.",
	"Or hold [{secondary}] and walk to push it ahead of you. Quick on a long flat walk, but it piles up in front of you.",
	"Clear my walk inside the blue line, from the sidewalk up to my door."]}


## The hint ids of the first pickups, one per kind of tool ("tool_shovel", "tool_walk_blower", …).
static func tool_hint_id(kind: int) -> String:
	return "tool_" + str(ToolData.Kind.keys()[kind]).to_lower()


## The hint id of a vehicle kind's first drive ("vehicle_pickup_plow", …).
static func vehicle_hint_id(kind: int) -> String:
	return "vehicle_" + str(VehicleData.Kind.keys()[kind]).to_lower()


## The first-drive hint of a vehicle: driving, the blade keys and back-drag (a plow), the blower
## (a blower), the bed (the dump truck). The first-drive panel's lines (polish 7 §11), as pages.
static func vehicle_hint(display_name: String, has_plow: bool, has_blower: bool, dumps: bool) -> Dictionary:
	var pages := ["\n".join(["{veh_accelerate} / {veh_reverse}  drive forward / brake & reverse",
		"{veh_left} / {veh_right}  steer",
		"{veh_brake}  handbrake",
		"Mouse  look around   ·   {camera_toggle}  camera",
		"{veh_horn}  horn   ·   {veh_radio}  radio forecast",
		"{interact}  get out"])]
	if has_plow:
		pages.append("\n".join(["{veh_tool}  lower / raise the blade",
			"{veh_blade_up} / {veh_blade_down}  raise / lower the blade",
			"{veh_aim_left} / {veh_aim_right}  angle the blade"]))
		pages.append("{veh_reverse}, blade down  drag the snow back")
	if has_blower:
		pages.append("\n".join(["{veh_tool}  blower on / off",
			"{veh_aim_left} / {veh_aim_right}  turn the chute"]))
	if dumps:
		pages.append("{veh_tool}  dump the bed (at the Snow Dump lot)")
	return {"title": display_name + " controls", "pages": pages}


## The first pickup of a kind of tool: the shovel's found-it sentence, the blower's grab line, and
## the one-line controls reminder (ToolController.controls_hint) for the others, one line per key.
static func tool_hint(kind: int, display_name: String, angle_adjustable: bool) -> Dictionary:
	var page := ""
	match kind:
		ToolData.Kind.SHOVEL:
			page = "Hold {primary} and sweep it through the snow to fill it, release to throw, hold {secondary} to push."
		ToolData.Kind.ELECTRIC_SHOVEL:
			page = "Hold {primary}: chew through snow and throw it where you aim\nHold {secondary}: push"
		ToolData.Kind.WALK_BLOWER:
			page = "Hold {primary} to run, {veh_aim_left} / {veh_aim_right} to turn the chute, {interact} to let go."
		_:
			page = "Hold {primary} and sweep: scoop\nRelease: throw\nHold {secondary}: push"
			if angle_adjustable:
				page += "\n{tool_angle}: angle the blade"
	return {"title": display_name, "pages": [page]}


## A hint by id (empty if unknown). Vehicle and tool hints need their data: the vehicle or tool
## (VehicleData / ToolData) that opened them, or the first of that kind in the catalogue.
static func hint(id: String, data: Resource = null) -> Dictionary:
	if id == "gerry_snow":
		return GERRY_SNOW.duplicate(true)
	if id.begins_with("vehicle_"):
		var vd := data as VehicleData
		if vd == null:
			for v in Catalog.vehicles.values():
				if vehicle_hint_id(int((v as VehicleData).kind)) == id:
					vd = v
					break
		if vd != null:
			return vehicle_hint(vd.display_name, vd.has_plow, vd.has_blower, vd.dump_capacity > 0)
	if id.begins_with("tool_"):
		var td := data as ToolData
		if td == null:
			for t in Catalog.tools.values():
				if tool_hint_id(int((t as ToolData).kind)) == id:
					td = t
					break
		if td != null:
			return tool_hint(int(td.kind), td.display_name, td.angle_adjustable)
	return {}


## Every hint's content for the Help app: [title, text] with the keys bound now. The vehicles'
## hints are one entry holding every line (driving, the blade, back-drag, the blower, the bed).
static func hint_help() -> Array:
	var out := []
	var add := func(h: Dictionary) -> void:
		var pages := []
		for p in h["pages"]:
			pages.append(Settings.with_keys(str(p)))
		out.append([Settings.with_keys(str(h["title"])), "\n".join(pages)])
	add.call(GERRY_SNOW)
	add.call(vehicle_hint("Vehicles", true, true, true))
	var kinds := {}
	for t in Catalog.tools.values():
		var td := t as ToolData
		if td.kind == ToolData.Kind.HANDS or kinds.has(td.kind):
			continue
		kinds[td.kind] = true
		add.call(tool_hint(int(td.kind), td.display_name, td.angle_adjustable))
	return out


## Polish 5 §4: Gerry's last line, after the heat and the computer — skipped (and not repeated when
## you talk to him again) once the truck keys are found.
static func keys_line() -> Dictionary:
	return {"speaker": "Gerry", "text": "Oh, by the way: before the storm I saw something shining under the tree on your front lawn. Your truck keys, maybe?", "unless_flag": "truck_keys"}


static func lines(survival: bool) -> Array:
	var out := []
	for e in explanation(survival):
		out.append("• " + str(e["text"]))
	out.append("• Hands and every shovel, pusher, scraper or sleigh: HOLD %s and sweep the crosshair through the snow to fill your hands or blade — deep snow fills fast. RELEASE to throw it where you face (look down for a short drop). The landing ring turns amber when the throw would land back in the box you're clearing. Snow thrown at a building drops at the foot of its wall; the street takes snow like anywhere else." % Settings.action_label("primary"))
	out.append("• HOLD %s and walk to push snow ahead of you into a pile. Pushers, scrapers and the sleigh push far more than shovels; scrapers angle their blade with %s." % [Settings.action_label("secondary"), Settings.action_label("tool_angle")])
	out.append("• Snow up to your hips can be waded through (slowly). Anything taller is a wall — dig through it.")
	out.append("• Every driveway, path, sidewalk, parking lot and street section is a clearing box. While you work in one, a light outline shows its edges — throw the snow outside it. Clear 90% of a box and it snaps to bare ground. New snow reopens it.")
	out.append("• Wading through deep snow treads a trench; walking back along it is easier. Look straight down to scoop the snow at your own feet.")
	out.append("• The truck needs its keys (buried in your front lawn) and room to drive: dig the snow from around the wheels and clear the driveway. It tells you what's in the way.")
	# Polish 5 §10: due times (was the 48-hour snowed-in rule).
	out.append("• Bid on the contract board until 9 p.m.; the lowest bid wins at 9:01 p.m. A job you win is due by 9 p.m. the next day; a recurring or city visit by 9 p.m. the day after the snow stops. A storm adds a day, once. Miss it and you lose reputation and the pay.")
	out.append("• Sleep in your bed to save; you always wake at 7:00 a.m.")
	# Polish 5 §9: the day length from the clock, the key from the input map.
	out.append("• A day lasts %d minutes of play. %s or the 1× / 2× / 10× buttons by the clock speed it up on foot, indoors and at the computer; it drops back to 1× when something needs you." % [int(Clock.REAL_MIN_PER_DAY), Settings.action_label("fast_forward")])
	return out
