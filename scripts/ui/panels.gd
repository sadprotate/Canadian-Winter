class_name Panels
extends RefCounted
## Small modal panels built on demand: letter, dialogue, sleep, TV, inventory, pause, confirm,
## winter summary, death screen, vehicle help.


static func _dim(parent: Control, alpha := 0.45) -> Control:
	var root := Control.new()
	root.theme = UIKit.theme()
	UIKit.full_rect(root)
	root.process_mode = Node.PROCESS_MODE_ALWAYS
	var d := ColorRect.new()
	d.color = Color(0, 0, 0, alpha)
	UIKit.full_rect(d)
	root.add_child(d)
	parent.add_child(root)
	return root


## Polish 5 §4: the framed photo by the front door, large on screen in its mat and frame, no text.
## Interact or Esc closes it (game_root handles the keys).
static func photo(parent: Control, tex: Texture2D) -> Control:
	var root := _dim(parent, 0.7)
	var center := CenterContainer.new()
	UIKit.full_rect(center)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	var frame := PanelContainer.new()
	frame.name = "Photo"
	var st := UIKit.sb(Color(0.93, 0.91, 0.86), 3, 12, Color(0.42, 0.27, 0.16), 30)
	st.content_margin_top = 30
	st.content_margin_bottom = 30
	frame.add_theme_stylebox_override("panel", st)
	center.add_child(frame)
	var pr := TextureRect.new()
	pr.name = "Print"
	pr.texture = tex
	pr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pr.custom_minimum_size = Vector2(1200, 800)
	frame.add_child(pr)
	return root


static func letter(parent: Control, title: String, body: String, on_close: Callable) -> Control:
	var root := _dim(parent, 0.4)
	var p := UIKit.center_panel(root, Vector2(820, 760))
	p.add_theme_stylebox_override("panel", UIKit.sb(Color(0.97, 0.95, 0.88), 6, 1, Color(0.6, 0.55, 0.45), 40))
	var v := UIKit.vbox(16)
	p.add_child(v)
	v.add_child(UIKit.label(title, 30, Color(0.15, 0.18, 0.3)))
	var l := UIKit.label(body, 21, Color(0.15, 0.15, 0.18))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 740
	l.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(l)
	var b := UIKit.button("Close", func():
		root.queue_free()
		on_close.call(), 22, 200)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(b)
	AudioMgr.play("paper", -4.0)
	return root


## Dialogue: lines = [{speaker, text, choices?:[{text, id}]}]. on_choice(id) for choices; on_done().
static func dialogue(parent: Control, lines: Array, on_choice: Callable, on_done: Callable, on_line: Callable = Callable()) -> Control:
	var root := Control.new()
	root.theme = UIKit.theme()
	UIKit.full_rect(root)
	parent.add_child(root)
	var p := UIKit.panel(UIKit.sb(Color(0.07, 0.09, 0.15, 0.93), 14, 2, UIKit.ACCENT, 26))
	p.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	p.custom_minimum_size = Vector2(1200, 250)
	p.position = Vector2(-600, -300)
	root.add_child(p)
	var v := UIKit.vbox(12)
	p.add_child(v)
	var name_l := UIKit.label("", 26, UIKit.ACCENT)
	v.add_child(name_l)
	var text_l := UIKit.label("", 23, Color.WHITE)
	text_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_l.custom_minimum_size.x = 1140
	v.add_child(text_l)
	var row := UIKit.hbox(12)
	v.add_child(row)
	var state := {"i": 0}
	var show := func(show_ref: Callable) -> void:
		UIKit.clear(row)
		if state["i"] >= lines.size():
			root.queue_free()
			on_done.call()
			return
		var ln: Dictionary = lines[state["i"]]
		name_l.text = ln.get("speaker", "")
		text_l.text = ln.get("text", "")
		if on_line.is_valid():
			on_line.call(ln)
		AudioMgr.play(AudioMgr.variant("neighbor_talk", 3), -6.0)
		if ln.has("choices"):
			for ch in ln["choices"]:
				var cid = ch["id"]
				row.add_child(UIKit.button(ch["text"], func():
					var follow = on_choice.call(cid)
					if follow is Array and not follow.is_empty():
						for k in range(follow.size()):
							lines.insert(state["i"] + 1 + k, follow[k])
					state["i"] += 1
					show_ref.call(show_ref), 21))
		else:
			var b := UIKit.button("Continue  ▸", func():
				state["i"] += 1
				show_ref.call(show_ref), 21)
			row.add_child(b)
			b.call_deferred("grab_focus")
	show.call(show)
	return root


static func sleep(parent: Control, on_pick: Callable, on_cancel: Callable) -> Control:
	var root := _dim(parent, 0.5)
	# Polish 3 §3: just the question and the two choices, centred and sized to its content.
	var center := CenterContainer.new()
	UIKit.full_rect(center)
	root.add_child(center)
	var p := PanelContainer.new()
	p.name = "Dialog"
	var style := UIKit.sb(UIKit.BG, 14, 1, Color(1, 1, 1, 0.08), CONFIRM_PAD)
	style.content_margin_top = CONFIRM_PAD
	style.content_margin_bottom = CONFIRM_PAD
	p.add_theme_stylebox_override("panel", style)
	p.custom_minimum_size.x = 520
	center.add_child(p)
	var v := UIKit.vbox(12)
	p.add_child(v)
	# Polish §12: exactly two choices, and no date, weather or forecast on the sleep screens.
	v.add_child(UIKit.label("Go to sleep?", 34, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER))
	if Game.is_survival() and not Survival.power_on:
		var w := UIKit.label("WARNING: the power is off. The house is losing its heat — you may wake up freezing.", 19, UIKit.BAD, HORIZONTAL_ALIGNMENT_CENTER)
		w.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		w.custom_minimum_size.x = 452
		v.add_child(w)
	v.add_child(UIKit.spacer(6))
	v.add_child(UIKit.button("Sleep until 7:00 a.m.", func():
		root.queue_free()
		on_pick.call(0), 22))
	v.add_child(UIKit.button("Not yet", func():
		root.queue_free()
		on_cancel.call(), 22))
	return root


## Polish 3 §3: the TV weather fills a 16:9 screen (bezel around it) with an even margin, centred
## both ways, in large type: current conditions biggest, then the 3-day forecast (the same
## forecast-with-error entries as before), the latest alert and the city crews' line.
const TV_SCREEN := Vector2(1280, 720)


static func tv(parent: Control, on_close: Callable, jingle := true) -> Control:
	var root := _dim(parent, 0.55)
	var center := CenterContainer.new()
	UIKit.full_rect(center)
	root.add_child(center)
	var col := UIKit.vbox(18)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(col)
	var bezel := PanelContainer.new()
	bezel.name = "TV"
	var bz := UIKit.sb(Color(0.03, 0.03, 0.035, 1.0), 18, 2, Color(0.16, 0.16, 0.18), 22)
	bz.content_margin_top = 22
	bz.content_margin_bottom = 22
	bezel.add_theme_stylebox_override("panel", bz)
	col.add_child(bezel)
	var screen := PanelContainer.new()
	screen.name = "Screen"
	screen.custom_minimum_size = TV_SCREEN
	screen.clip_contents = true
	var sc := UIKit.sb(Color(0.09, 0.2, 0.42, 1.0), 6, 0, Color.TRANSPARENT, 48)
	sc.content_margin_top = 40
	sc.content_margin_bottom = 40
	screen.add_theme_stylebox_override("panel", sc)
	bezel.add_child(screen)
	var v := UIKit.vbox(26)
	v.name = "Content"
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	screen.add_child(v)
	var gold := Color(1, 0.88, 0.38)
	v.add_child(UIKit.label("CHANNEL 6 WEATHER  ·  MAPLE RIDGE", 30, gold, HORIZONTAL_ALIGNMENT_CENTER))
	# Right now: the biggest thing on screen.
	var now := UIKit.hbox(30)
	now.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(now)
	now.add_child(Icons.weather(Weather.condition(), 140))
	var nv := UIKit.vbox(2)
	nv.alignment = BoxContainer.ALIGNMENT_CENTER
	now.add_child(nv)
	nv.add_child(UIKit.label("RIGHT NOW", 24, Color(0.75, 0.84, 1.0)))
	var cur := UIKit.label(Weather.current_summary(), 46, Color.WHITE)
	cur.name = "Now"
	cur.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cur.custom_minimum_size.x = 900
	nv.add_child(cur)
	var rule := ColorRect.new()
	rule.color = Color(1, 1, 1, 0.18)
	rule.custom_minimum_size = Vector2(0, 2)
	v.add_child(rule)
	# The forecast: one card per day.
	var row := UIKit.hbox(24)
	row.name = "Forecast"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	for e in Weather.forecast(3):
		# Polish 5 §8: one line more per card (when the snow starts and ends) in the same screen —
		# a smaller icon (88 → 72 px) and tighter spacing inside the card.
		var csb := UIKit.sb(Color(1, 1, 1, 0.07), 10, 0, Color.TRANSPARENT, 18)
		csb.content_margin_top = 8
		csb.content_margin_bottom = 8
		var card := UIKit.panel(csb)
		card.custom_minimum_size = Vector2(368, 0)
		row.add_child(card)
		var cv := UIKit.vbox(2)
		cv.alignment = BoxContainer.ALIGNMENT_CENTER
		card.add_child(cv)
		# Polish 5 §8: the card's words come from Weather.card_text (the computer shows the same):
		# the strength, the snow as a range, when it should start and end, the high and low.
		var ct := Weather.card_text(e)
		cv.add_child(UIKit.label(ct["date"], 28, gold, HORIZONTAL_ALIGNMENT_CENTER))
		var ic := CenterContainer.new()
		ic.add_child(Icons.weather(e["cond"], 72))
		cv.add_child(ic)
		cv.add_child(UIKit.label(ct["title"], 32, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER))
		if ct["amount"] != "":
			cv.add_child(UIKit.label(ct["amount"], 26, Color(0.75, 0.9, 1.0), HORIZONTAL_ALIGNMENT_CENTER))
		if ct["when"] != "":
			cv.add_child(UIKit.label(ct["when"], 22, Color(0.75, 0.9, 1.0), HORIZONTAL_ALIGNMENT_CENTER))
		cv.add_child(UIKit.label(ct["temps"], 24, Color(0.88, 0.92, 1.0), HORIZONTAL_ALIGNMENT_CENTER))
	if not Weather.alerts.is_empty():
		var a: Dictionary = Weather.alerts[Weather.alerts.size() - 1]
		var al := UIKit.label("Latest alert: " + str(a["text"]), 24, UIKit.WARN, HORIZONTAL_ALIGNMENT_CENTER)
		al.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		al.custom_minimum_size.x = 1100
		v.add_child(al)
	# Polish 5 §11: the next crew day from the schedule ("City crews: Mon 7 a.m.").
	var grader := UIKit.label(Municipal.crew_line(), 26, Color(0.85, 0.9, 1.0), HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(grader)
	# Polish 4 §1: the forecast is revised every game hour. One small line under the last one, in
	# the screen's bottom margin, so the TV's layout and size stay as they were.
	var upd := UIKit.label("Forecast updated %s" % Weather.hour_name(Weather.issued_hour()), 18, Color(0.7, 0.78, 0.92), HORIZONTAL_ALIGNMENT_CENTER)
	upd.name = "Updated"
	upd.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grader.add_child(upd)
	upd.anchor_left = 0.0
	upd.anchor_right = 1.0
	upd.anchor_top = 1.0
	upd.anchor_bottom = 1.0
	upd.offset_top = 2.0
	upd.offset_bottom = 28.0
	var b := UIKit.button("Turn off TV", func():
		root.queue_free()
		on_close.call(), 22, 240)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(b)
	if jingle:
		AudioMgr.play("radio_jingle", -6.0)
	return root


static func inventory(parent: Control) -> Control:
	var root := Control.new()
	root.theme = UIKit.theme()
	UIKit.full_rect(root)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(root)
	var p := UIKit.center_panel(root, Vector2(760, 520))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := UIKit.vbox(10)
	p.add_child(v)
	v.add_child(UIKit.label("Equipment", 30, Color.WHITE))
	for i in range(4):
		var id: String = Game.slots[i]
		var h := UIKit.hbox(12)
		v.add_child(h)
		h.add_child(Icons.tool(id, 48))
		var sel := " ◀" if i == Game.selected else ""
		h.add_child(UIKit.label("%d.  %s%s" % [i + 1, Catalog.tool(StringName(id)).display_name if id != "" else "(empty — bare hands)", sel], 21, Color.WHITE if id != "" else UIKit.MUTED))
	if Game.carried != "":
		v.add_child(UIKit.label("Carrying: %s (%s to drop)" % [Catalog.item_name(StringName(Game.carried)), Settings.action_label("drop")], 20, UIKit.WARN))
	v.add_child(UIKit.label("Utility: %d heating pouch%s  (%s to use)" % [Game.heat_pouches, "" if Game.heat_pouches == 1 else "es", Settings.action_label("use_pouch")], 20, UIKit.MUTED))
	v.add_child(UIKit.label("Keys: %s" % ("pickup truck keys" if Game.flags.get("truck_keys", false) else "none found"), 20, UIKit.MUTED))
	# Polish 5 §13: the equipment you have (the snowshoes come off and go on here, with Interact).
	for line in Equipment.overview_lines():
		v.add_child(UIKit.label(line, 20, Color(0.85, 0.92, 1.0)))
	# Polish 5 §13: the upgrades of the tool in your hands (each item has its own), and clothing.
	var cur := Game.current_tool()
	var ups := []
	var own := ItemUpgrades.summary(cur.id)
	if own != "":
		ups.append(own)
	for id2 in Game.upgrades.keys():
		var u: UpgradeData = Catalog.upgrade(StringName(id2))
		if u and u.item == &"" and u.category == UpgradeData.Category.CLOTHING:
			ups.append(u.display_name)
	var ul := UIKit.label("Upgrades — %s: %s" % [cur.display_name, ", ".join(ups) if not ups.is_empty() else "none"], 20, UIKit.MUTED)
	ul.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ul.custom_minimum_size.x = 700
	v.add_child(ul)
	v.add_child(UIKit.spacer(4))
	var ctl := UIKit.label(ToolController.controls_hint(Game.current_tool()), 19, Color(0.85, 0.92, 1.0))
	ctl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ctl.custom_minimum_size.x = 700
	v.add_child(ctl)
	return root


## Polish 3 §2: the confirmation sizes itself to its content (text wraps at a sensible width),
## sits centred on screen at any resolution, has even padding all round, centred text and a
## centred row of two equal buttons.
const CONFIRM_WRAP_MAX := 620.0
const CONFIRM_WRAP_MIN := 380.0
const CONFIRM_PAD := 34


static func confirm(parent: Control, text: String, yes: String, on_yes: Callable, on_no: Callable = Callable()) -> Control:
	var root := _dim(parent, 0.55)
	var center := CenterContainer.new()
	center.name = "Center"
	UIKit.full_rect(center)
	root.add_child(center)
	var p := PanelContainer.new()
	p.name = "Dialog"
	var style := UIKit.sb(UIKit.BG, 14, 1, Color(1, 1, 1, 0.08), CONFIRM_PAD)
	style.content_margin_top = CONFIRM_PAD
	style.content_margin_bottom = CONFIRM_PAD
	p.add_theme_stylebox_override("panel", style)
	center.add_child(p)
	var v := UIKit.vbox(28)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(v)
	var l := UIKit.label(text, 22, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	l.name = "Message"
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var font := l.get_theme_font("font")
	var one_line := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x if font else CONFIRM_WRAP_MAX
	l.custom_minimum_size.x = clampf(one_line + 8.0, CONFIRM_WRAP_MIN, CONFIRM_WRAP_MAX)
	v.add_child(l)
	var h := UIKit.hbox(20)
	h.name = "Buttons"
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(h)
	var by := UIKit.button(yes, func():
		root.queue_free()
		on_yes.call(), 22, 240)
	var bn := UIKit.button("Cancel", func():
		root.queue_free()
		if on_no.is_valid():
			on_no.call(), 22, 240)
	h.add_child(by)
	h.add_child(bn)
	# Same width for both buttons (the wider label decides).
	var w := maxf(by.get_combined_minimum_size().x, bn.get_combined_minimum_size().x)
	by.custom_minimum_size.x = w
	bn.custom_minimum_size.x = w
	return root


static func pause(parent: Control, on_resume: Callable, on_settings: Callable, on_menu: Callable, on_quit: Callable) -> Control:
	var root := _dim(parent, 0.5)
	var p := UIKit.center_panel(root, Vector2(520, 520))
	var v := UIKit.vbox(16)
	p.add_child(v)
	v.add_child(UIKit.label("PAUSED", 40, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UIKit.label("Winter %d · %s %s" % [Game.year, Clock.date_string(Clock.day_index()), Clock.time_string()], 19, UIKit.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UIKit.spacer(10))
	v.add_child(UIKit.button("RESUME GAME", on_resume, 24))
	v.add_child(UIKit.button("SETTINGS", on_settings, 24))
	v.add_child(UIKit.button("EXIT TO MAIN MENU", on_menu, 24))
	v.add_child(UIKit.button("QUIT TO DESKTOP", on_quit, 24))
	if Game.dirty_since_save:
		v.add_child(UIKit.label("Progress is saved when you sleep.", 17, UIKit.WARN, HORIZONTAL_ALIGNMENT_CENTER))
	return root


static func summary(parent: Control, on_next: Callable) -> Control:
	var root := _dim(parent, 0.7)
	var p := UIKit.center_panel(root, Vector2(1000, 820))
	var v := UIKit.vbox(10)
	p.add_child(v)
	v.add_child(UIKit.label("APRIL 1 — WINTER %d SURVIVED!" % Game.year, 40, Color(1, 0.9, 0.5)))
	var st: Dictionary = Game.stats
	var lines := [
		"Money earned: %s" % UIKit.money(int(st.get("money_earned", 0))),
		"Contracts completed: %d   ·   Service visits: %d" % [int(st.get("contracts_completed", 0)), int(st.get("visits_completed", 0))],
		"Snow moved: %d m³   ·   Snow hauled to the dump: %d m³" % [int(st.get("snow_moved", 0.0)), int(st.get("snow_hauled", 0.0))],
		"Total snowfall this winter: %d cm" % int(st.get("snowfall_cm", 0.0)),
		"Missed deadlines: %d   ·   Hydro bills paid: %d" % [int(st.get("missed_deadlines", 0)), int(st.get("bills_paid", 0))],
		("Reputation: %d / 100   ·   Balance: %s" % [int(Game.reputation), UIKit.money(Game.money)]) if Game.company_name == "" else
			("%s — reputation: %d / 100   ·   Balance: %s" % [Game.company_name, int(Game.reputation), UIKit.money(Game.money)]),
		"Equipment acquired: %s" % (", ".join(st.get("equipment", [])) if not (st.get("equipment", []) as Array).is_empty() else "none"),
	]
	for l in lines:
		var lb := UIKit.label(l, 21, Color.WHITE)
		lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lb.custom_minimum_size.x = 940
		v.add_child(lb)
	v.add_child(UIKit.spacer(8))
	v.add_child(UIKit.label("Renew recurring contracts for next winter:", 22, UIKit.ACCENT))
	var renew := {}
	for c in Contracts.active:
		if c["type"] != "one_time" and c["status"] != "expired" and c["status"] != "lost":
			var cb := CheckBox.new()
			cb.text = "%s — %s / visit" % [c["address"], UIKit.money(c["pay"])]
			cb.button_pressed = true
			renew[int(c["id"])] = cb
			v.add_child(cb)
	if renew.is_empty():
		v.add_child(UIKit.label("(no recurring contracts)", 18, UIKit.MUTED))
	v.add_child(UIKit.label("Next winter will be a little harder. Your money, equipment, vehicles and upgrades carry over.", 18, UIKit.MUTED))
	var b := UIKit.button("BEGIN WINTER %d" % (Game.year + 1), func():
		var ids := []
		for k in renew.keys():
			if (renew[k] as CheckBox).button_pressed:
				ids.append(k)
		root.queue_free()
		on_next.call(ids), 26)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(b)
	return root


static func death(parent: Control) -> Control:
	var root := Control.new()
	UIKit.full_rect(root)
	root.process_mode = Node.PROCESS_MODE_ALWAYS
	parent.add_child(root)
	var white := ColorRect.new()
	white.color = Color(0.9, 0.95, 1.0, 0.0)
	UIKit.full_rect(white)
	root.add_child(white)
	var l := UIKit.shadow_label("You froze to death.", 64, Color(0.15, 0.25, 0.45))
	l.set_anchors_preset(Control.PRESET_CENTER)
	l.position = Vector2(-330, -60)
	l.modulate.a = 0.0
	root.add_child(l)
	var l2 := UIKit.label("Your last sleep save is safe — continue from the main menu.", 24, Color(0.2, 0.3, 0.5))
	l2.set_anchors_preset(Control.PRESET_CENTER)
	l2.position = Vector2(-330, 30)
	l2.modulate.a = 0.0
	root.add_child(l2)
	var tw := root.create_tween()
	tw.tween_property(white, "color:a", 0.95, 2.5)
	tw.parallel().tween_property(l, "modulate:a", 1.0, 2.5)
	tw.tween_property(l2, "modulate:a", 1.0, 1.0)
	return root


static func vehicle_help(parent: Control, v: Node) -> Control:
	var root := Control.new()
	root.theme = UIKit.theme()
	UIKit.full_rect(root)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(root)
	var p := UIKit.panel(UIKit.sb(Color(0.07, 0.09, 0.15, 0.85), 12, 1, UIKit.ACCENT, 18))
	p.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	p.position = Vector2(-520, -200)
	p.custom_minimum_size = Vector2(480, 0)
	root.add_child(p)
	var vb := UIKit.vbox(6)
	p.add_child(vb)
	vb.add_child(UIKit.label(v.data.display_name + " controls", 24, UIKit.ACCENT))
	var lines := ["%s / %s  drive forward / brake & reverse" % [Settings.action_label("veh_accelerate"), Settings.action_label("veh_reverse")],
		"%s / %s  steer" % [Settings.action_label("veh_left"), Settings.action_label("veh_right")],
		"%s  handbrake" % Settings.action_label("veh_brake")]
	if v.data.has_plow:
		lines.append("%s  lower / raise the blade" % Settings.action_label("veh_tool"))
		lines.append("%s / %s  angle the blade" % [Settings.action_label("veh_aim_left"), Settings.action_label("veh_aim_right")])
	if v.data.has_blower:
		lines.append("%s  blower on / off" % Settings.action_label("veh_tool"))
		lines.append("%s / %s  turn the chute" % [Settings.action_label("veh_aim_left"), Settings.action_label("veh_aim_right")])
	if v.data.dump_capacity > 0:
		lines.append("%s  dump the bed (at the Snow Dump lot)" % Settings.action_label("veh_tool"))
	lines.append("Mouse  look around   ·   %s  camera" % Settings.action_label("camera_toggle"))
	lines.append("%s  horn   ·   %s  radio forecast" % [Settings.action_label("veh_horn"), Settings.action_label("veh_radio")])
	lines.append("%s  get out" % Settings.action_label("interact"))
	for l in lines:
		vb.add_child(UIKit.label(l, 19, Color.WHITE))
	var tw := root.create_tween()
	tw.tween_interval(9.0)
	tw.tween_property(root, "modulate:a", 0.0, 1.0)
	tw.tween_callback(root.queue_free)
	return root
