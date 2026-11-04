class_name HUD
extends Control
## In-game HUD (Part 22). Top-left: winter year, date, time. Top-right: weather.
## Bottom-left: money and (Survival) warmth. Bottom-right: four tool slots. Centre: crosshair + prompts.

var world: Node
var date_l: Label
var time_l: Label
var clock_panel: PanelContainer   # polish 5 §9: the fast-forward control sits beside it
var weather_icon: Icons
var weather_l: Label
var temp_l: Label
var money_l: Label
var warmth_box: VBoxContainer
var warmth_bar: ProgressBar
var warmth_l: Label
var alert_l: Label
var slots: Array = []
var slot_icons: Array = []
var slot_keys: Array = []
var tool_name_l: Label
var hotbar: Control
var charge_bar: ProgressBar
var crosshair: Control
var prompt_l: Label
var hint_l: Label
var contract_panel: PanelContainer
var contract_l: Label
var contract_bar: ProgressBar
var vehicle_l: Label
var notif_box: VBoxContainer
var subtitle_l: Label
var subtitle_box: PanelContainer
var speech_box: PanelContainer
var speech_name: Label
var speech_text: Label
var speech_hint: Label
var objective_box: PanelContainer
var objective_l: Label
var _subtitle_t := 0.0
var frost: ColorRect
var frost_mat: ShaderMaterial
var perf_l: Label
var pouch_l: Label
var _t := 0.0
var _last_money := -1
var _shiver: AudioStreamPlayer
var _heart: AudioStreamPlayer


func _ready() -> void:
	theme = UIKit.theme()
	UIKit.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_frost()
	# Top-left: date/time
	var tl := UIKit.panel(UIKit.sb(Color(0.07, 0.09, 0.15, 0.6), 12, 0, Color.TRANSPARENT, 14))
	tl.position = Vector2(24, 20)
	add_child(tl)
	clock_panel = tl
	var tlv := UIKit.vbox(0)
	tl.add_child(tlv)
	date_l = UIKit.shadow_label("", 20, UIKit.MUTED)
	time_l = UIKit.shadow_label("", 36, Color.WHITE)
	tlv.add_child(date_l)
	tlv.add_child(time_l)
	# Top-right: weather
	var top_right := UIKit.panel(UIKit.sb(Color(0.07, 0.09, 0.15, 0.6), 12, 0, Color.TRANSPARENT, 14))
	top_right.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	top_right.custom_minimum_size = Vector2(306, 0)
	# Pinned to the right edge and growing leftward, so "-14 °C (feels -29)" never runs off-screen.
	top_right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	top_right.offset_right = -20.0
	top_right.offset_left = -326.0
	top_right.offset_top = 20.0
	add_child(top_right)
	var trh := UIKit.hbox(12)
	top_right.add_child(trh)
	weather_icon = Icons.weather(0, 64)
	trh.add_child(weather_icon)
	var trv := UIKit.vbox(0)
	trh.add_child(trv)
	weather_l = UIKit.shadow_label("", 20, UIKit.MUTED)
	temp_l = UIKit.shadow_label("", 32, Color.WHITE)
	trv.add_child(weather_l)
	trv.add_child(temp_l)
	# Bottom-left: money + warmth
	var bl := UIKit.vbox(6)
	bl.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	bl.position = Vector2(24, -170)
	add_child(bl)
	alert_l = UIKit.shadow_label("", 20, UIKit.WARN)
	bl.add_child(alert_l)
	money_l = UIKit.shadow_label("$0", 40, Color(0.75, 1.0, 0.75))
	bl.add_child(money_l)
	warmth_box = UIKit.vbox(2)
	bl.add_child(warmth_box)
	warmth_l = UIKit.shadow_label("Warmth", 18, UIKit.MUTED)
	warmth_box.add_child(warmth_l)
	warmth_bar = UIKit.progress(1.0, Color(1.0, 0.6, 0.3), 16)
	warmth_bar.custom_minimum_size = Vector2(260, 16)
	warmth_box.add_child(warmth_bar)
	pouch_l = UIKit.shadow_label("", 16, UIKit.MUTED)
	warmth_box.add_child(pouch_l)
	# Bottom-right: hotbar
	var hb := UIKit.vbox(6)
	hb.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	hb.position = Vector2(-470, -150)
	add_child(hb)
	hotbar = hb
	tool_name_l = UIKit.shadow_label("", 20, Color.WHITE, )
	tool_name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tool_name_l.custom_minimum_size.x = 440
	hb.add_child(tool_name_l)
	var row := UIKit.hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_END
	hb.add_child(row)
	for i in range(4):
		var p := UIKit.panel(UIKit.sb(Color(0.07, 0.09, 0.15, 0.65), 10, 2, Color(1, 1, 1, 0.12), 6))
		p.custom_minimum_size = Vector2(98, 86)
		row.add_child(p)
		var ov := Control.new()
		p.add_child(ov)
		var ic := Icons.tool("", 70)
		ic.position = Vector2(8, 2)
		ov.add_child(ic)
		var key := UIKit.shadow_label(str(i + 1), 16, UIKit.MUTED)
		key.position = Vector2(-2, -4)
		ov.add_child(key)
		slots.append(p)
		slot_icons.append(ic)
		slot_keys.append(key)
	charge_bar = UIKit.progress(0.0, Color(0.6, 0.85, 1.0), 8)
	charge_bar.custom_minimum_size = Vector2(422, 8)
	hb.add_child(charge_bar)
	# Centre: crosshair + prompt + hint
	crosshair = Control.new()
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.draw.connect(_draw_crosshair)
	add_child(crosshair)
	prompt_l = UIKit.shadow_label("", 24, Color.WHITE)
	prompt_l.set_anchors_preset(Control.PRESET_CENTER)
	prompt_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_l.position = Vector2(-400, 30)
	prompt_l.custom_minimum_size = Vector2(800, 0)
	add_child(prompt_l)
	hint_l = UIKit.shadow_label("", 22, UIKit.WARN)
	hint_l.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_l.position = Vector2(-500, -230)
	hint_l.custom_minimum_size = Vector2(1000, 0)
	add_child(hint_l)
	vehicle_l = UIKit.shadow_label("", 22, Color.WHITE)
	vehicle_l.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	vehicle_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vehicle_l.position = Vector2(-600, -60)
	vehicle_l.custom_minimum_size = Vector2(1200, 0)
	add_child(vehicle_l)
	# Contract progress (only near an active zone)
	contract_panel = UIKit.panel(UIKit.sb(Color(0.07, 0.09, 0.15, 0.75), 10, 1, UIKit.ACCENT, 12))
	contract_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	contract_panel.position = Vector2(-260, 20)
	contract_panel.custom_minimum_size = Vector2(520, 0)
	add_child(contract_panel)
	var cv := UIKit.vbox(4)
	contract_panel.add_child(cv)
	contract_l = UIKit.label("", 19)
	cv.add_child(contract_l)
	contract_bar = UIKit.progress(0.0, UIKit.ACCENT, 14)
	cv.add_child(contract_bar)
	contract_panel.visible = false
	# Notifications
	notif_box = UIKit.vbox(6)
	notif_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	notif_box.position = Vector2(-330, 110)
	notif_box.custom_minimum_size = Vector2(660, 0)
	add_child(notif_box)
	# Subtitles (radio forecast, story lines): centred above the hotbar, wrapped, on a soft dark
	# backing so every line stays readable by day and at night (polish 3 §3).
	subtitle_box = UIKit.panel(UIKit.sb(Color(0.03, 0.04, 0.08, 0.55), 10, 0, Color.TRANSPARENT, 20))
	subtitle_box.name = "SubtitleBox"
	subtitle_box.anchor_left = 0.5
	subtitle_box.anchor_right = 0.5
	subtitle_box.anchor_top = 1.0
	subtitle_box.anchor_bottom = 1.0
	subtitle_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	subtitle_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	subtitle_box.offset_top = -250.0
	subtitle_box.offset_bottom = -250.0
	subtitle_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	subtitle_box.visible = false
	add_child(subtitle_box)
	subtitle_l = UIKit.shadow_label("", 26, Color(1, 1, 0.9))
	subtitle_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle_box.add_child(subtitle_l)
	# Someone speaking (Gerry after the trail): a box above the hotbar that does not block the
	# game — you keep walking while it's up; Interact moves on to the next line (polish 3 §4).
	speech_box = UIKit.panel(UIKit.sb(Color(0.07, 0.09, 0.15, 0.88), 14, 2, UIKit.ACCENT, 24))
	speech_box.name = "SpeechBox"
	speech_box.anchor_left = 0.5
	speech_box.anchor_right = 0.5
	speech_box.anchor_top = 1.0
	speech_box.anchor_bottom = 1.0
	speech_box.offset_left = -560.0
	speech_box.offset_right = 560.0
	speech_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	speech_box.offset_top = -420.0
	speech_box.offset_bottom = -240.0
	speech_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	speech_box.visible = false
	add_child(speech_box)
	var sv := UIKit.vbox(8)
	speech_box.add_child(sv)
	speech_name = UIKit.label("", 24, UIKit.ACCENT)
	sv.add_child(speech_name)
	speech_text = UIKit.label("", 23, Color.WHITE)
	speech_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	speech_text.custom_minimum_size.x = 1060
	sv.add_child(speech_text)
	speech_hint = UIKit.label("", 17, UIKit.MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	sv.add_child(speech_hint)
	# Current objective (tutorial), under the clock.
	objective_box = UIKit.panel(UIKit.sb(Color(0.07, 0.09, 0.15, 0.6), 10, 0, Color.TRANSPARENT, 14))
	objective_box.position = Vector2(20, 112)
	objective_box.visible = false
	add_child(objective_box)
	objective_l = UIKit.label("", 19, Color(1.0, 0.92, 0.75))
	objective_box.add_child(objective_l)
	perf_l = UIKit.shadow_label("", 16, Color(0.7, 1.0, 0.7))
	perf_l.position = Vector2(24, 130)
	add_child(perf_l)
	# Audio cold warnings (Part 17.5): shivering, then a heartbeat near critical freezing.
	_shiver = AudioStreamPlayer.new()
	_shiver.bus = "SFX"
	_shiver.stream = AudioMgr.stream("shiver")
	_shiver.volume_db = -80.0
	add_child(_shiver)
	_heart = AudioStreamPlayer.new()
	_heart.bus = "SFX"
	_heart.stream = AudioMgr.stream("heartbeat")
	_heart.volume_db = -80.0
	add_child(_heart)
	Notify.posted.connect(_on_notify)
	Game.inventory_changed.connect(_refresh_slots)
	_refresh_slots()


func _build_frost() -> void:
	frost = ColorRect.new()
	UIKit.full_rect(frost)
	frost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frost_mat = ShaderMaterial.new()
	frost_mat.shader = load("res://shaders/frost_overlay.gdshader")
	frost.material = frost_mat
	frost_mat.set_shader_parameter("amount", 0.0)
	frost.visible = false
	add_child(frost)


func _draw_crosshair() -> void:
	var c := Vector2.ZERO
	crosshair.draw_circle(c, 3.0, Color(1, 1, 1, 0.85))
	crosshair.draw_arc(c, 9.0, 0, TAU, 24, Color(1, 1, 1, 0.25), 1.5, true)


func _on_notify(text: String, kind: int) -> void:
	if not Settings.get_value("gameplay", "show_notifications", true):
		return
	var col: Color = [Color.WHITE, UIKit.GOOD, UIKit.WARN, UIKit.BAD][clampi(kind, 0, 3)]
	var p := UIKit.panel(UIKit.sb(Color(0.07, 0.09, 0.15, 0.82), 10, 0, Color.TRANSPARENT, 12))
	var l := UIKit.label(text, 20, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 620
	p.add_child(l)
	notif_box.add_child(p)
	if kind == Notify.GOOD:
		AudioMgr.ui("ui_money" if text.begins_with("Payment") else "ui_notify")
	elif kind == Notify.WARN or kind == Notify.BAD:
		AudioMgr.ui("ui_alert")
	else:
		AudioMgr.ui("ui_notify")
	# Polish 3 (found at baseline): queue_free() leaves the child in place until the end of the
	# frame, so a burst of more than five notifications in one frame (a long F1 jump, a bad night's
	# sleep) looped here forever and ran out of memory. Count only the ones still showing.
	var live := []
	for c in notif_box.get_children():
		if not c.is_queued_for_deletion():
			live.append(c)
	while live.size() > 5:
		var old: Control = live.pop_front()
		old.visible = false
		old.queue_free()
	var tw := p.create_tween()
	tw.tween_interval(5.5)
	tw.tween_property(p, "modulate:a", 0.0, 0.8)
	tw.tween_callback(p.queue_free)


const SUBTITLE_MAX_W := 1100.0


## Show a spoken line (speaker, text); empty text hides the box. `more` shows the "next" hint.
func say(speaker: String, text: String, more := false) -> void:
	speech_box.visible = text != ""
	speech_name.text = speaker
	speech_text.text = text
	var key := Settings.action_label("interact")
	speech_hint.text = ("[%s] next ▸" % key) if more else ("[%s] ▸" % key)


func set_objective(text: String) -> void:
	if objective_l.text != text:
		objective_l.text = text
		objective_box.visible = text != ""
		objective_box.reset_size()


func subtitle(text: String, seconds := 3.0) -> void:
	subtitle_l.text = text
	_subtitle_t = seconds
	var font := subtitle_l.get_theme_font("font")
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x if font else SUBTITLE_MAX_W
	subtitle_l.custom_minimum_size.x = clampf(w + 10.0, 120.0, SUBTITLE_MAX_W)
	subtitle_box.visible = text != ""
	_fit_subtitle()
	call_deferred("_fit_subtitle")


## Keep the subtitle box snug around its text and centred above the bottom edge.
func _fit_subtitle() -> void:
	var ms := subtitle_box.get_combined_minimum_size()
	subtitle_box.offset_left = -ms.x * 0.5
	subtitle_box.offset_right = ms.x * 0.5
	subtitle_box.offset_top = -250.0 - ms.y
	subtitle_box.offset_bottom = -250.0


func _refresh_slots() -> void:
	for i in range(4):
		var id: String = Game.slots[i]
		(slot_icons[i] as Icons).set_tool(id)
		var sel := i == Game.selected and Game.carried == ""
		# An empty slot means bare hands; show the mitten clearly only on the selected one so a
		# row of empty slots doesn't read as four pairs of gloves.
		(slot_icons[i] as Control).modulate.a = 1.0 if (id != "" or sel) else 0.35
		(slots[i] as PanelContainer).add_theme_stylebox_override("panel", UIKit.sb(Color(0.07, 0.09, 0.15, 0.65 if not sel else 0.85), 10, 3 if sel else 2, UIKit.ACCENT if sel else Color(1, 1, 1, 0.12), 6))
	if Game.carried != "":
		tool_name_l.text = "Carrying: %s  (%s to drop)" % [Catalog.item_name(StringName(Game.carried)), Settings.action_label("drop")]
	else:
		var id2: String = Game.slots[Game.selected]
		tool_name_l.text = "Bare hands" if id2 == "" else Catalog.tool(StringName(id2)).display_name


func _process(delta: float) -> void:
	_t -= delta
	_subtitle_t -= delta
	if _subtitle_t <= 0.0 and subtitle_l.text != "":
		subtitle_l.text = ""
		subtitle_box.visible = false
	var player: Player = Game.player
	# Prompt / hint
	if player:
		var show_prompts: bool = Settings.get_value("gameplay", "show_prompts", true)
		prompt_l.text = player.focus_prompt if show_prompts and player.state != "vehicle" else ""
		var hint := ""
		if player.tools:
			hint = player.tools.hint
		if player.machine and player.machine.hint != "":
			hint = player.machine.hint
		if player.vehicle and player.vehicle.status_text != "":
			hint = player.vehicle.status_text
		hint_l.text = hint
		crosshair.visible = player.state != "vehicle"
		# Polish 4 §3: while a hand tool is scooping or loaded, the indicator on the snow shows
		# where the snow comes from and goes; the screen-centre dot fades (back for prompts).
		var tool_busy: bool = player.tools != null and player.tools.ind_state in ["pickup", "landing"] and player.focus_prompt == ""
		crosshair.modulate.a = move_toward(crosshair.modulate.a, 0.15 if tool_busy else 1.0, delta * 4.0)
		# The hand-tool hotbar means nothing while driving (the vehicle line takes over).
		hotbar.visible = player.state != "vehicle"
		vehicle_l.text = player.vehicle.hud_text() if player.vehicle else ""
		# Load in the hands / on the blade (the 3D mound is the main feedback; this backs it up).
		var tc: ToolController = player.tools
		charge_bar.value = tc.load / maxf(tc._capacity(), 0.0001) if tc.load > 0.0 else 0.0
		charge_bar.visible = charge_bar.value > 0.0 and player.state == "foot"
	if _t > 0.0:
		return
	_t = 0.2
	var day := Clock.day_index()
	date_l.text = "Winter %d  ·  %s %s" % [Game.year, Clock.weekday(day, Game.year), Clock.date_string(day)]
	time_l.text = Clock.time_string()
	var cond := Weather.condition()
	var is_night: bool = world.is_night() if world and world.has_method("is_night") else false
	weather_icon.set_weather(cond, is_night)
	weather_l.text = Weather.NAMES[cond]
	temp_l.text = "%d °C  (feels %d)" % [int(round(Weather.temperature())), int(round(Weather.wind_chill()))]
	if Game.money != _last_money:
		_last_money = Game.money
		money_l.text = UIKit.money(Game.money)
	# Survival
	var surv := Survival.enabled()
	warmth_box.visible = surv
	var alerts := []
	if Game.is_survival():
		if not Survival.power_on:
			alerts.append("⚡ POWER OUT — pay the hydro bill on your computer")
		else:
			for bl in Economy.unpaid_bills():
				var due: int = bl["due_day"]
				if due - day <= 3:
					alerts.append("Hydro bill $%d due %s" % [bl["amount"], Clock.date_string(due, true)])
	if Weather.condition() == Weather.C.BLIZZARD:
		alerts.append("BLIZZARD")
	for c in Contracts.active:
		var left: float = Contracts.hours_left(c)
		if left <= Catalog.balance.contract_warn_hours:
			# Polish 5 §10: the due time (was the snowed-in hours left).
			alerts.append("⚠ %s: due %s — %d h left" % [c["address"], Contracts.due_text(c), int(ceil(maxf(left, 0.0)))])
	alert_l.text = "\n".join(alerts)
	if surv:
		var w := Survival.warmth
		warmth_bar.value = w / 100.0
		var st := Survival.state()
		var col: Color = [Color(1.0, 0.7, 0.35), Color(0.9, 0.8, 0.5), Color(0.6, 0.8, 1.0), Color(0.45, 0.65, 1.0), Color(0.75, 0.85, 1.0), Color.WHITE][st]
		warmth_bar.add_theme_stylebox_override("fill", UIKit.sb(col, 6, 0, Color.TRANSPARENT, 0))
		var trend := ""
		# Polish 5 §9: the arrows follow the rate as felt — warmth per real minute.
		var felt := Survival.per_real_minute(Survival.last_rate)
		if felt > TREND_PER_REAL_MIN:
			trend = "  ▲ warming"
		elif felt < -TREND_PER_REAL_MIN:
			trend = "  ▼"
		warmth_l.text = "Warmth: %s%s" % [Survival.STATE_NAMES[st], trend]
		pouch_l.text = "Heating pouches: %d (%s)" % [Game.heat_pouches, Settings.action_label("use_pouch")] if Game.heat_pouches > 0 else ""
		var cold := clampf((45.0 - w) / 45.0, 0.0, 1.0)
		frost_mat.set_shader_parameter("amount", cold)
		frost_mat.set_shader_parameter("pulse", 1.0 if w < 15.0 else 0.0)
		frost.visible = cold > 0.001
		_cold_audio(w)
	else:
		frost_mat.set_shader_parameter("amount", 0.0)
		frost.visible = false
		_cold_audio(100.0)
	# Clearing box the player is working in (polish §7): live progress, and the contract timer.
	if player and Settings.get_value("gameplay", "show_contract_hud", true):
		var pp := Vector2(player.global_position.x, player.global_position.z)
		var b := Boxes.box_at(pp, 1.5) if not player.indoors else {}
		contract_panel.visible = not b.is_empty()
		if not b.is_empty():
			var c := Contracts.contract_for_box(b["id"])
			var head := "%s — %s" % [b["place"], b["name"]]
			if not c.is_empty():
				head = "Contract · " + head
			var pr := float(b["progress"])
			var line := "%s   %s" % [head, "clear ✓" if b["complete"] else "%d%%" % int(floor(pr * 100.0))]
			if not c.is_empty() and not c.get("tutorial", false):
				# Polish 5 §10: the job's due time (was the snowed-in clock).
				var dt := Contracts.due_text(c)
				if dt != "":
					var left: float = Contracts.hours_left(c)
					line += "\nDue %s%s" % [dt, "  (%d h left)" % int(ceil(maxf(left, 0.0))) if left < INF else ""]
			contract_l.text = line
			contract_bar.value = 1.0 if b["complete"] else pr
	else:
		contract_panel.visible = false
	_refresh_slots()
	if Settings.get_value("graphics", "fps_overlay", false) or (world and world.get("perf_overlay")):
		var sr = world.get("snow_renderer") if world else null
		perf_l.text = "FPS %d  |  frame %.1f ms  |  snow chunk updates %d  |  draw calls %d  |  relax queue %d" % [
			Engine.get_frames_per_second(), 1000.0 / maxf(Engine.get_frames_per_second(), 1.0),
			sr.updates_last_frame if sr else 0,
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), Snow.relax_pending()]
	else:
		perf_l.text = ""


## Polish 5 §9: the warmth arrows show once warmth moves faster than this per real minute (as the
## old 1 % per game hour at 2.5 real minutes a game hour).
const TREND_PER_REAL_MIN := 0.4


func _cold_audio(w: float) -> void:
	var shiver_db := -80.0 if w >= 45.0 else lerpf(-24.0, -6.0, clampf((45.0 - w) / 35.0, 0.0, 1.0))
	var heart_db := -80.0 if w >= 18.0 else lerpf(-16.0, 0.0, clampf((18.0 - w) / 16.0, 0.0, 1.0))
	if get_tree().paused:
		shiver_db = -80.0
		heart_db = -80.0
	for pair in [[_shiver, shiver_db], [_heart, heart_db]]:
		var p: AudioStreamPlayer = pair[0]
		if p.stream == null:
			continue
		p.volume_db = pair[1]
		if pair[1] > -79.0 and not p.playing:
			p.play()
		elif pair[1] <= -79.0 and p.playing:
			p.stop()
