extends Node
## Audio manager (Part 25): buses (Music / Ambience / SFX / UI), pooled one-shots with pitch
## variation, managed loops, weather ambience + music crossfades and indoor muffling.
## Only files that exist are ever loaded (Never reference missing audio).

const DIR := "res://assets/audio/"
const LOOPS := ["push_scrape", "push_snow", "plow_scrape", "blower_small", "blower_large", "blower_discharge",
	"electric_motor", "engine_truck", "engine_diesel", "engine_small", "tires_snow", "wind_light", "wind_strong",
	"blizzard", "fire_crackle", "furnace_hum", "room_tone", "shiver", "heartbeat", "music_calm", "music_snow"]

var _streams: Dictionary = {}
var _pool2d: Array = []
var _pool3d: Array = []
var _amb: Dictionary = {}      # name -> AudioStreamPlayer
var _music: Dictionary = {}
var _lowpass: AudioEffectLowPassFilter
var indoors := false
var ambience_enabled := false
var music_enabled := true
var _gust_timer := 4.0
## quit(): real time to wait after stopping every sound, so the audio thread can drop the
## stopped streams before the engine shuts down (it needs two mix steps, ~25 ms each at most).
const QUIT_DRAIN_MS := 150
var _quitting := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Closing the window quits through quit() too (see there).
	get_tree().auto_accept_quit = false
	_setup_buses()
	for i in range(12):
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool2d.append(p)
	for i in range(20):
		var p3 := AudioStreamPlayer3D.new()
		p3.bus = "SFX"
		p3.unit_size = 6.0
		p3.max_distance = 70.0
		p3.attenuation_filter_cutoff_hz = 9000.0
		add_child(p3)
		_pool3d.append(p3)
	for n in ["wind_light", "wind_strong", "blizzard", "fire_crackle", "furnace_hum", "room_tone"]:
		var a := AudioStreamPlayer.new()
		a.bus = "Interior" if n in ["fire_crackle", "furnace_hum", "room_tone"] else "Ambience"
		a.stream = stream(n)
		a.volume_db = -80.0
		add_child(a)
		_amb[n] = a
	# Preload every sound once (≈11 MB) so the first use of a sound never hitches a frame.
	var d := DirAccess.open(DIR)
	if d:
		for f in d.get_files():
			if f.ends_with(".wav.import") or f.ends_with(".wav"):
				stream(f.get_basename().get_basename() if f.ends_with(".import") else f.get_basename())
	for n in ["music_calm", "music_snow"]:
		var m := AudioStreamPlayer.new()
		m.bus = "Music"
		m.stream = stream(n)
		m.volume_db = -80.0
		add_child(m)
		_music[n] = m


func _setup_buses() -> void:
	for bus_name in ["Music", "Ambience", "Interior", "SFX", "UI"]:
		if AudioServer.get_bus_index(bus_name) < 0:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")
	var amb := AudioServer.get_bus_index("Ambience")
	_lowpass = AudioEffectLowPassFilter.new()
	_lowpass.cutoff_hz = 20000.0
	AudioServer.add_bus_effect(amb, _lowpass)
	var rev := AudioEffectReverb.new()
	rev.room_size = 0.35
	rev.wet = 0.08
	AudioServer.add_bus_effect(AudioServer.get_bus_index("SFX"), rev)
	apply_volumes()


func apply_volumes() -> void:
	var map := {"Master": "master", "Music": "music", "Ambience": "ambient", "Interior": "ambient", "SFX": "sfx", "UI": "sfx"}
	for bus in map.keys():
		var idx := AudioServer.get_bus_index(bus)
		if idx < 0:
			continue
		var v: float = float(Settings.get_value("audio", map[bus], 0.8))
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.0001)))
		AudioServer.set_bus_mute(idx, v <= 0.001)


func has_sound(sound: String) -> bool:
	return ResourceLoader.exists(DIR + sound + ".wav")


func stream(sound: String) -> AudioStream:
	if _streams.has(sound):
		return _streams[sound]
	var s: AudioStream = null
	if has_sound(sound):
		s = load(DIR + sound + ".wav")
		if s is AudioStreamWAV and sound in LOOPS:
			var w: AudioStreamWAV = s
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_begin = 0
			w.loop_end = int(w.get_length() * w.mix_rate)
	_streams[sound] = s
	return s


## Pick a random numbered variant if it exists (step_snow -> step_snow_1..4).
func variant(base: String, count: int) -> String:
	var n := base + "_%d" % (randi() % count + 1)
	return n if has_sound(n) else base


## Quit the game (HANDOFF §13 item 13). A sound still playing when the engine shuts down stays
## referenced by the audio server's playback list and is reported at exit as "N ObjectDB
## instances were leaked" / "M resources still in use" (the menu music, the EXIT click: whatever
## happened to be playing, so the counts varied). So: pause the tree (nothing restarts a sound),
## stop every player by taking its stream away, give the audio thread a moment to drop them,
## then quit.
func quit(code := 0) -> void:
	if _quitting:
		return
	_quitting = true
	get_tree().paused = true
	for cls in ["AudioStreamPlayer", "AudioStreamPlayer2D", "AudioStreamPlayer3D"]:
		for p in get_tree().root.find_children("*", cls, true, false):
			p.set("stream", null)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < QUIT_DRAIN_MS:
		await get_tree().process_frame
	get_tree().quit(code)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		quit()


func play(sound: String, volume_db := 0.0, pitch := 1.0, bus := "SFX") -> void:
	if _quitting:
		return
	var s := stream(sound)
	if s == null:
		return
	for p in _pool2d:
		var pl: AudioStreamPlayer = p
		if not pl.playing:
			pl.stream = s
			pl.volume_db = volume_db
			pl.pitch_scale = pitch * randf_range(0.95, 1.05)
			pl.bus = bus
			pl.play()
			return


func play_at(sound: String, pos: Vector3, volume_db := 0.0, pitch := 1.0) -> void:
	if _quitting:
		return
	var s := stream(sound)
	if s == null:
		return
	var best: AudioStreamPlayer3D = null
	for p in _pool3d:
		if not (p as AudioStreamPlayer3D).playing:
			best = p
			break
	if best == null:
		best = _pool3d[randi() % _pool3d.size()]
	best.stream = s
	best.global_position = pos
	best.volume_db = volume_db
	best.pitch_scale = pitch * randf_range(0.92, 1.08)
	best.play()


func ui(sound: String) -> void:
	play(sound, -4.0, 1.0, "UI")


## Create a managed looping 3D player attached to a node (tools, engines).
func make_loop(sound: String, parent: Node3D, volume_db := 0.0) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = stream(sound)
	p.bus = "SFX"
	p.unit_size = 7.0
	p.max_distance = 80.0
	p.volume_db = volume_db
	parent.add_child(p)
	return p


# -----------------------------------------------------------------------------
# Weather ambience and music
# -----------------------------------------------------------------------------

func set_ambience_enabled(on: bool) -> void:
	ambience_enabled = on
	for a in _amb.values():
		if on and not (a as AudioStreamPlayer).playing and a.stream:
			a.play()
	for m in _music.values():
		if on and music_enabled and not (m as AudioStreamPlayer).playing and m.stream:
			m.play()
	if not on:
		for a in _amb.values():
			a.stop()


func set_menu_music(on: bool) -> void:
	var m: AudioStreamPlayer = _music.get("music_calm")
	if m and m.stream:
		if on and not m.playing:
			m.play()
		m.volume_db = -6.0 if on else -80.0


func _process(delta: float) -> void:
	if not ambience_enabled or _quitting:
		return
	var cond := Weather.condition()
	var paused := get_tree().paused
	var targets := {"wind_light": -80.0, "wind_strong": -80.0, "blizzard": -80.0}
	match cond:
		0, 1:
			targets["wind_light"] = -16.0
		2:
			targets["wind_light"] = -9.0
		3:
			targets["wind_light"] = -10.0
			targets["wind_strong"] = -11.0
		4:
			targets["wind_strong"] = -5.0
			targets["blizzard"] = -16.0
		5:
			targets["wind_strong"] = -8.0
			targets["blizzard"] = 0.0
	var inside_gain := -10.0 if indoors else 0.0
	for k in targets.keys():
		var a: AudioStreamPlayer = _amb[k]
		var t: float = targets[k] + (inside_gain if targets[k] > -79.0 else 0.0)
		a.volume_db = move_toward(a.volume_db, t, delta * 12.0)
	# Interior ambience: fireplace crackle, heating hum, quiet room tone.
	var heat_on := Survival.power_on
	var fire_t := -6.0 if (indoors and heat_on) else -80.0
	var hum_t := -18.0 if (indoors and heat_on) else -80.0
	var room_t := -22.0 if indoors else -80.0
	(_amb["fire_crackle"] as AudioStreamPlayer).volume_db = move_toward(_amb["fire_crackle"].volume_db, fire_t, delta * 30.0)
	(_amb["furnace_hum"] as AudioStreamPlayer).volume_db = move_toward(_amb["furnace_hum"].volume_db, hum_t, delta * 30.0)
	(_amb["room_tone"] as AudioStreamPlayer).volume_db = move_toward(_amb["room_tone"].volume_db, room_t, delta * 30.0)
	_lowpass.cutoff_hz = move_toward(_lowpass.cutoff_hz, 700.0 if indoors else 20000.0, delta * 30000.0)
	# Music: calm when clear, atmospheric during snow, fades out in a blizzard.
	var calm_t := -80.0
	var snow_t := -80.0
	if music_enabled:
		if cond <= 1:
			calm_t = -8.0
		elif cond <= 3:
			snow_t = -9.0
		elif cond == 4:
			snow_t = -20.0
	for pair in [["music_calm", calm_t], ["music_snow", snow_t]]:
		var m: AudioStreamPlayer = _music[pair[0]]
		if m.stream and not m.playing and pair[1] > -79.0:
			m.play()
		m.volume_db = move_toward(m.volume_db, pair[1], delta * 6.0)
	# Gusts and rattles in strong weather.
	if not paused and not indoors and cond >= 3:
		_gust_timer -= delta
		if _gust_timer <= 0.0:
			_gust_timer = randf_range(3.0, 9.0) if cond == 5 else randf_range(8.0, 18.0)
			play("gust_whistle", -6.0 if cond == 5 else -14.0)
			if cond >= 4 and randf() < 0.5:
				play("rattle", -12.0)


func stop_all_ambience() -> void:
	set_ambience_enabled(false)
	for m in _music.values():
		m.volume_db = -80.0
