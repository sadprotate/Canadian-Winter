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
	out.append({"speaker": "Gerry", "text": "Check the forecast on your TV, the radio or the computer. The city grader comes by every three or four days — the computer shows when. It'll leave a wall of snow across your driveway, mind you."})
	out.append({"speaker": "Gerry", "text": "That's about it. Thanks again, neighbour. Now get home before you freeze — and good luck with the business!"})
	return out


## Polish 5 §4: when Gerry gives you his trail he adds the two ways to move snow, with the keys
## read from the input map; talking to him again during the job repeats it. Spoken on the HUD.
static func snow_tips() -> Array:
	var out := []
	for t in ["Now, two ways to move snow.",
			"Hold [%s] and sweep through the snow to fill your shovel, then let go to throw it. That gets it up over the banks." % Settings.action_label("primary"),
			"Or hold [%s] and walk to push it ahead of you. Quick on a long flat walk, but it piles up in front of you." % Settings.action_label("secondary"),
			"Clear my walk inside the blue line, from the sidewalk up to my door."]:
		out.append({"speaker": "Gerry", "text": t, "tip": true})
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
	out.append("• A contract is lost if its property stays snowed in for more than 48 hours (the clock pauses while a storm is still falling).")
	out.append("• Sleep in your bed to save; you always wake at 7:00 a.m.")
	return out
