extends Node
## Original chiptune music synthesized in code (no audio files): a mellow menu loop, a driving
## game loop, a tense clutch loop for close late games, win / lose jingles and a crowd bed.
## Tracks are rendered once on a worker thread at startup (a second or two on a phone) and
## start as soon as they are ready. Music.play("menu" | "game" | "clutch" | "") crossfades;
## Music.jingle("win" | "lose") plays once over a ducked loop; Music.set_crowd(true) adds the
## stadium murmur. Volume comes from Settings.music_volume. Silent in headless runs.

const RATE := 11025
const FADE := 0.7

## Per track: tempo, bars as [root midi note, minor?], drum style and how busy the arp/bass are.
const TRACKS := {
	"menu": {"bpm": 96, "bars": [[45, true], [41, false], [48, false], [43, false], [45, true], [41, false], [48, false], [43, false]],
			"style": 0, "lead_seed": 11, "lead_density": 0.5, "key": 57},
	"game": {"bpm": 138, "bars": [[40, true], [36, false], [43, false], [38, false], [40, true], [36, false], [43, false], [38, false]],
			"style": 1, "lead_seed": 23, "lead_density": 0.7, "key": 64},
	"clutch": {"bpm": 156, "bars": [[38, true], [34, false], [36, false], [45, false], [38, true], [34, false], [36, false], [45, false]],
			"style": 2, "lead_seed": 37, "lead_density": 0.8, "key": 62},
}

var enabled := true

var _streams: Dictionary = {}
var _building: Dictionary = {}
var _wanted := "menu"   # the menu loop starts by itself as soon as it is rendered
var _current := ""
var _players: Array[AudioStreamPlayer] = []
var _active := 0
var _jingle_player: AudioStreamPlayer
var _crowd_player: AudioStreamPlayer
var _crowd_on := false
var _mutex := Mutex.new()


func _ready() -> void:
	enabled = DisplayServer.get_name() != "headless"
	if not enabled:
		return
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.volume_db = -60.0
		add_child(p)
		_players.append(p)
	_jingle_player = AudioStreamPlayer.new()
	add_child(_jingle_player)
	_crowd_player = AudioStreamPlayer.new()
	add_child(_crowd_player)
	Settings.changed.connect(_apply_volume)
	for name in ["menu", "game", "clutch", "win", "lose", "crowd"]:
		_building[name] = true
		WorkerThreadPool.add_task(_render_task.bind(name))


func _render_task(name: String) -> void:
	var s: AudioStreamWAV
	match name:
		"win":
			s = _jingle([[72, 0.0], [76, 0.11], [79, 0.22], [84, 0.33], [79, 0.5], [84, 0.62], [88, 0.8]], 1.6, 1.0)
		"lose":
			s = _jingle([[67, 0.0], [64, 0.22], [60, 0.44], [55, 0.7]], 1.5, 0.9)
		"crowd":
			s = _crowd()
		_:
			s = _track(TRACKS[name])
	call_deferred("_on_ready", name, s)


func _on_ready(name: String, s: AudioStreamWAV) -> void:
	if OS.get_cmdline_user_args().has("--music-debug"):
		print("MUSIC ready ", name, " at ", Time.get_ticks_msec(), " ms, ", s.data.size() / 2, " samples")
	_streams[name] = s
	_building.erase(name)
	if name == _wanted:
		play(name)
	if name == "crowd" and _crowd_on:
		set_crowd(true)


## Crossfade to a track ("" = silence). Safe to call before the track finished rendering.
func play(track: String) -> void:
	_wanted = track
	if not enabled or _players.is_empty():
		return
	if track == "":
		_fade_out_current()
		_current = ""
		return
	if track == _current:
		return
	if not _streams.has(track):
		return   # starts from _on_ready
	_fade_out_current()
	_active = 1 - _active
	var p := _players[_active]
	p.stream = _streams[track]
	p.volume_db = -60.0
	p.play()
	create_tween().tween_property(p, "volume_db", _target_db(), FADE)
	_current = track


func jingle(name: String) -> void:
	if not enabled or not _streams.has(name) or Settings.music_volume <= 0.0:
		return
	_jingle_player.stream = _streams[name]
	_jingle_player.volume_db = linear_to_db(Settings.music_volume)
	_jingle_player.play()
	# Duck the loop under the jingle.
	var p := _players[_active]
	if p.playing:
		var tw := create_tween()
		tw.tween_property(p, "volume_db", _target_db() - 14.0, 0.2)
		tw.tween_interval(1.4)
		tw.tween_property(p, "volume_db", _target_db(), 0.8)


func set_crowd(on: bool) -> void:
	_crowd_on = on
	if not enabled:
		return
	if on and _streams.has("crowd") and Settings.sfx_volume > 0.0:
		if not _crowd_player.playing:
			_crowd_player.stream = _streams["crowd"]
			_crowd_player.volume_db = linear_to_db(Settings.sfx_volume * 0.35)
			_crowd_player.play()
	elif not on:
		_crowd_player.stop()


func _target_db() -> float:
	return linear_to_db(maxf(Settings.music_volume, 0.0001)) if Settings.music_volume > 0.0 else -80.0


func _fade_out_current() -> void:
	var p := _players[_active]
	if p.playing:
		var tw := create_tween()
		tw.tween_property(p, "volume_db", -60.0, FADE)
		tw.tween_callback(p.stop)


func _apply_volume() -> void:
	if not enabled:
		return
	var p := _players[_active]
	if p.playing:
		p.volume_db = _target_db()
	if _crowd_player.playing:
		_crowd_player.volume_db = linear_to_db(maxf(Settings.sfx_volume * 0.35, 0.0001))


# ---------------------------------------------------------------- synthesis (worker thread)

static func _hz(midi: float) -> float:
	return 440.0 * pow(2.0, (midi - 69.0) / 12.0)


## Adds one note to `buf` (mono float samples). wave: 0 pulse 50%, 1 pulse 25%, 2 triangle.
static func _note(buf: PackedFloat32Array, start: int, length: int, freq: float, wave: int, vol: float, decay: float) -> void:
	var phase := 0.0
	var inc := freq / RATE
	var end := mini(start + length, buf.size())
	for i in range(start, end):
		phase += inc
		if phase >= 1.0:
			phase -= 1.0
		var s := 0.0
		if wave == 2:
			s = 4.0 * absf(phase - 0.5) - 1.0
		elif wave == 1:
			s = 1.0 if phase < 0.25 else -1.0
		else:
			s = 1.0 if phase < 0.5 else -1.0
		var u := float(i - start) / maxf(length, 1)
		var env := exp(-decay * u) * minf(1.0, float(i - start) / 40.0)
		buf[i] += s * vol * env


static func _kick(buf: PackedFloat32Array, start: int, vol: float) -> void:
	var n := int(0.11 * RATE)
	var phase := 0.0
	for i in n:
		if start + i >= buf.size():
			return
		var u := float(i) / n
		phase += lerpf(150.0, 45.0, u) / RATE
		buf[start + i] += sin(phase * TAU) * vol * (1.0 - u)


static func _hit(buf: PackedFloat32Array, start: int, seconds: float, vol: float, rng: RandomNumberGenerator) -> void:
	var n := int(seconds * RATE)
	for i in n:
		if start + i >= buf.size():
			return
		var u := float(i) / n
		buf[start + i] += rng.randf_range(-1.0, 1.0) * vol * (1.0 - u) * (1.0 - u)


static func _to_wav(buf: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var peak := 0.001
	for v in buf:
		peak = maxf(peak, absf(v))
	var gain := 0.85 / peak if peak > 0.85 else 1.0
	var bytes := PackedByteArray()
	bytes.resize(buf.size() * 2)
	for i in buf.size():
		bytes.encode_s16(i * 2, int(clampf(buf[i] * gain, -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = buf.size()
	return w


## A looping track: bass, arpeggio, a seeded pentatonic lead and drums over 8 chord bars.
static func _track(spec: Dictionary) -> AudioStreamWAV:
	var bpm: float = spec["bpm"]
	var bars: Array = spec["bars"]
	var style: int = spec["style"]
	var sps := int(RATE * 60.0 / bpm / 4.0)   # samples per sixteenth
	var buf := PackedFloat32Array()
	buf.resize(sps * 16 * bars.size())
	var rng := RandomNumberGenerator.new()
	rng.seed = int(spec["lead_seed"])
	var drum_rng := RandomNumberGenerator.new()
	drum_rng.seed = 5
	var key: int = spec["key"]
	var pent := [0, 3, 5, 7, 10, 12, 15, 17]   # minor pentatonic steps above the key
	var walk := 3
	for b in bars.size():
		var root: int = bars[b][0]
		var minor: bool = bars[b][1]
		var third := 3 if minor else 4
		var tones := [0, third, 7, 12, 7, third]
		for s in 16:
			var at := (b * 16 + s) * sps
			# Bass.
			if style == 0:
				if s == 0 or s == 8:
					_note(buf, at, sps * 7, _hz(root + (0 if s == 0 else 7)), 2, 0.32, 2.5)
			elif s % 2 == 0:
				_note(buf, at, sps * 2, _hz(root + (12 if (s / 2) % 4 == 3 else 0)), 2, 0.34, 2.0)
			# Arpeggio.
			if style == 0:
				if s % 2 == 0:
					_note(buf, at, sps * 2, _hz(root + 24 + int(tones[(s / 2) % tones.size()])), 1, 0.06, 3.0)
			else:
				_note(buf, at, sps, _hz(root + 24 + int(tones[s % tones.size()])), 1, 0.05 if style == 1 else 0.06, 3.0)
			# Lead: a wandering pentatonic melody with a rhythm that breathes.
			if s % 2 == 0 and rng.randf() < float(spec["lead_density"]):
				walk = clampi(walk + rng.randi_range(-2, 2), 0, pent.size() - 1)
				var hold := 2 if style == 0 else (rng.randi_range(1, 2) * 2)
				_note(buf, at, sps * hold, _hz(key + 12 + int(pent[walk]) + (root - int(bars[0][0]))), 0, 0.13, 2.2)
			# Drums.
			if style == 0:
				if s == 0:
					_kick(buf, at, 0.3)
				if s % 4 == 2:
					_hit(buf, at, 0.02, 0.07, drum_rng)
			else:
				if s == 0 or s == 8 or (style == 2 and s == 10):
					_kick(buf, at, 0.5)
				if s == 4 or s == 12:
					_hit(buf, at, 0.09, 0.32, drum_rng)
				if s % 2 == 0 or style == 2:
					_hit(buf, at, 0.018, 0.09, drum_rng)
	return _to_wav(buf, true)


## One-shot jingle: notes [midi, start seconds], total length, volume.
static func _jingle(notes: Array, seconds: float, vol: float) -> AudioStreamWAV:
	var buf := PackedFloat32Array()
	buf.resize(int(seconds * RATE))
	for n in notes:
		_note(buf, int(float(n[1]) * RATE), int(0.35 * RATE), _hz(float(n[0])), 0, 0.28 * vol, 4.0)
		_note(buf, int(float(n[1]) * RATE), int(0.35 * RATE), _hz(float(n[0]) - 12.0), 2, 0.2 * vol, 4.0)
	return _to_wav(buf, false)


## Stadium murmur: soft low-passed noise with a slow swell, seamless loop.
static func _crowd() -> AudioStreamWAV:
	var n := RATE * 4
	var buf := PackedFloat32Array()
	buf.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var y := 0.0
	var z := 0.0
	for i in n:
		y += 0.12 * (rng.randf_range(-1.0, 1.0) - y)
		z += 0.35 * (y - z)
		var swell := 0.75 + 0.25 * sin(float(i) / n * TAU * 2.0)
		buf[i] = z * 2.2 * swell
	return _to_wav(buf, true)
