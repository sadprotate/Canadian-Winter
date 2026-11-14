extends Control
## Polish 8 §17: the hint panel. The tips that teach the player how to do something (Gerry's how-to,
## the first drive, the first pickup of each kind of tool, the garage, the cold) go through one small
## panel on the right of the screen: a title and one or more short pages, with Back and Next (OK on
## the last page). The hint keys (hint_back / hint_next / hint_ok, the "hint" context) work on foot,
## in vehicles and at machines; the buttons can be clicked whenever the cursor is free.
##
## It never freezes anything: the player keeps moving and working and the clock keeps running. A
## hint stays until OK. Hints queue, one at a time; one waits (hidden, still current) while the
## computer, the sleep prompt, Gerry's dialogue, the pause menu, F1, the summary or the fade is up.
## It stays up over the map, the TV, the letter and the photo (the cursor is free there). It sits
## clear of the speech box, the crosshair, the prompts and the HUD's lines.
##
## Each hint shows once per save (Game.hints_seen, marked when it opens); show_hint(id, true) shows
## one again (Gerry's when you talk to him again, the cold-night warning each night). With "Show
## hints" off nothing opens. It lives on game_root.time_layer, above the modals, like SpeedControl.

const KEYS := ["hint_back", "hint_next", "hint_ok"]
## The modals a hint stays up over (the cursor is free there); any other modal hides it.
const OVER_MODALS := ["map", "tv", "letter", "photo"]
const WIDTH := 376.0

var world: Node
var queue: Array = []          # waiting hints: {id, data}
var current: Dictionary = {}   # the hint up now: {id, title, pages, data}; empty when none
var page := 0
var box: PanelContainer
var title_l: Label
var text_l: Label
var count_l: Label
var ok_l: Label
var back_b: Button
var next_b: Button


func _ready() -> void:
	theme = UIKit.theme()
	UIKit.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	box = UIKit.panel(UIKit.sb(Color(0.07, 0.09, 0.15, 0.9), 12, 2, UIKit.ACCENT, 16))
	box.name = "HintBox"
	box.anchor_left = 1.0
	box.anchor_right = 1.0
	box.offset_right = -20.0
	box.offset_left = -20.0 - WIDTH
	box.offset_top = 150.0
	box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.visible = false
	add_child(box)
	var v := UIKit.vbox(8)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(v)
	title_l = UIKit.label("", 22, UIKit.ACCENT)
	title_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_l.custom_minimum_size.x = WIDTH - 36.0
	v.add_child(title_l)
	text_l = UIKit.label("", 19, Color.WHITE)
	text_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_l.custom_minimum_size.x = WIDTH - 36.0
	v.add_child(text_l)
	var row := UIKit.hbox(8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(row)
	count_l = UIKit.label("", 16, UIKit.MUTED)
	count_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(count_l)
	row.add_child(UIKit.hspacer())
	back_b = _button("HintBack", func(): back())
	row.add_child(back_b)
	next_b = _button("HintNext", func(): next())
	row.add_child(next_b)
	ok_l = UIKit.label("", 15, UIKit.MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	v.add_child(ok_l)


func _button(n: String, cb: Callable) -> Button:
	var b := Button.new()
	b.name = n
	b.focus_mode = Control.FOCUS_NONE      # never takes the keyboard (Space, Enter, the arrows)
	b.custom_minimum_size = Vector2(0, 34)
	b.add_theme_font_size_override("font_size", 17)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.pressed.connect(func():
		AudioMgr.ui("ui_click")
		cb.call())
	return b


static func enabled() -> bool:
	return bool(Settings.get_value("gameplay", "show_hints", true))


## Queue a hint (it opens when nothing blocks it and the one before it is closed). False when hints
## are off or (unless `again`) it was seen already. `data` is the vehicle or tool that opened it.
## Again, the one up now goes back to its first page.
func show_hint(id: String, again := false, data: Resource = null) -> bool:
	if not enabled():
		return false
	if not again and Game.hint_seen(id):
		return false
	if not current.is_empty() and current["id"] == id:
		if again:
			page = 0
			_render()
		return true
	for q in queue:
		if q["id"] == id:
			return true
	if HelpText.hint(id, data).is_empty():
		return false
	queue.append({"id": id, "data": data})
	return true


## Take a hint off the screen and out of the queue (Gerry's when his trail is done).
func drop(id: String) -> void:
	queue = queue.filter(func(q): return q["id"] != id)
	if not current.is_empty() and current["id"] == id:
		current = {}


func is_open(id := "") -> bool:
	return box.visible and not current.is_empty() and (id == "" or current["id"] == id)


func back() -> void:
	if current.is_empty() or page <= 0:
		return
	page -= 1
	_render()


## The next page, or OK on the last one.
func next() -> void:
	if current.is_empty():
		return
	if page >= (current["pages"] as Array).size() - 1:
		ok()
		return
	page += 1
	_render()


func ok() -> void:
	current = {}
	page = 0


## Nothing blocks a hint: the game runs on screen (not paused, asleep, dead or faded), and no modal
## is up other than the map, the TV, the letter or the photo.
func can_show() -> bool:
	if world == null or not is_instance_valid(world) or not enabled():
		return false
	var hud: Control = world.get("hud")
	if hud == null or not is_instance_valid(hud) or not hud.visible:
		return false
	if get_tree().paused or bool(world.get("_dead")) or bool(world.get("_sleeping")):
		return false
	var fd: ColorRect = world.get("fade")
	if fd != null and fd.color.a > 0.05:
		return false
	return world.get("modal") == null or str(world.get("modal_kind")) in OVER_MODALS


func _process(_d: float) -> void:
	if not enabled():
		queue.clear()
		current = {}
	var ok_now := can_show()
	if current.is_empty() and ok_now and not queue.is_empty():
		var q: Dictionary = queue.pop_front()
		var h := HelpText.hint(str(q["id"]), q["data"])
		if not h.is_empty():
			current = {"id": q["id"], "title": h["title"], "pages": h["pages"], "data": q["data"]}
			page = 0
			Game.mark_hint_seen(str(q["id"]))
	box.visible = ok_now and not current.is_empty()
	if box.visible:
		_render()


## The page with the keys bound now (a rebind shows at once); the buttons clickable only while the
## cursor is free.
func _render() -> void:
	if current.is_empty():
		return
	var pages: Array = current["pages"]
	page = clampi(page, 0, pages.size() - 1)
	var last := page >= pages.size() - 1
	var t := Settings.with_keys(str(current["title"]))
	if title_l.text != t:
		title_l.text = t
	var body := Settings.with_keys(str(pages[page]))
	if text_l.text != body:
		text_l.text = body
	count_l.text = "%d / %d" % [page + 1, pages.size()] if pages.size() > 1 else ""
	back_b.text = "[%s] Back" % Settings.action_label("hint_back")
	back_b.disabled = page == 0
	back_b.visible = pages.size() > 1
	next_b.text = ("[%s] OK" if last else "[%s] Next") % Settings.action_label("hint_next")
	ok_l.text = "" if last else "[%s] OK" % Settings.action_label("hint_ok")
	ok_l.visible = not last
	var free := not Game.input_captured()
	var mf := Control.MOUSE_FILTER_STOP if free else Control.MOUSE_FILTER_IGNORE
	back_b.mouse_filter = mf
	next_b.mouse_filter = mf


## The hint keys, read before the GUI (the arrows are also Godot's ui_left / ui_right) and only
## while a hint shows; never while typing. Each press goes through the press cap.
func _input(event: InputEvent) -> void:
	if not box.visible or current.is_empty() or Game.typing():
		return
	if event is InputEventKey and (event as InputEventKey).echo:
		return
	for a in KEYS:
		if event.is_action_pressed(a):
			get_viewport().set_input_as_handled()
			if Settings.accept_press(a):
				match a:
					"hint_back": back()
					"hint_next": next()
					"hint_ok": ok()
			return
