extends Node
## Chiptune-style sound effects synthesized in code (square/triangle/noise, no audio files).
## Sfx.play("hit") anywhere. Volume from Settings.sfx_volume.

const RATE := 22050
const VOICES := 10

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0


func _ready() -> void:
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	# name -> list of [wave, freq_start, freq_end, seconds, volume]
	var defs := {
		"tap": [["square", 880, 880, 0.03, 0.25]],
		"flip": [["square", 520, 1040, 0.08, 0.3]],
		"big": [["square", 523, 523, 0.07, 0.35], ["square", 659, 659, 0.07, 0.35], ["square", 784, 784, 0.07, 0.35],
				["square", 1047, 1047, 0.2, 0.35]],
		"hit": [["noise", 0, 0, 0.09, 0.6], ["square", 110, 55, 0.08, 0.4]],
		"whistle": [["square", 2100, 2200, 0.25, 0.18]],
		"throw": [["triangle", 300, 700, 0.12, 0.4]],
		"catch": [["square", 660, 990, 0.05, 0.3]],
		"td": [["square", 392, 392, 0.1, 0.35], ["square", 523, 523, 0.1, 0.35], ["square", 659, 659, 0.1, 0.35],
				["square", 784, 784, 0.1, 0.35], ["square", 659, 659, 0.08, 0.35], ["square", 784, 784, 0.3, 0.35]],
		"kick": [["noise", 0, 0, 0.05, 0.5], ["triangle", 200, 90, 0.1, 0.5]],
		"bad": [["square", 300, 150, 0.25, 0.3]],
		"coin": [["square", 988, 988, 0.05, 0.3], ["square", 1319, 1319, 0.15, 0.3]],
		# Menu / reward juice.
		"tick": [["square", 1568, 1568, 0.018, 0.12]],
		"coin_tick": [["square", 1319, 1760, 0.04, 0.18]],
		"claim": [["square", 784, 784, 0.05, 0.3], ["square", 988, 988, 0.05, 0.3], ["square", 1319, 1319, 0.05, 0.3],
				["square", 1568, 1568, 0.18, 0.3]],
		"levelup": [["square", 523, 523, 0.08, 0.3], ["square", 659, 659, 0.08, 0.3], ["square", 784, 784, 0.08, 0.3],
				["square", 1047, 1047, 0.08, 0.3], ["square", 784, 784, 0.06, 0.3], ["square", 1047, 1047, 0.08, 0.3],
				["square", 1319, 1319, 0.35, 0.32]],
		"whoosh": [["noise", 0, 0, 0.22, 0.25]],
		"cheer": [["noise", 0, 0, 0.9, 0.3], ["triangle", 400, 700, 0.3, 0.12]],
		"groan": [["triangle", 280, 110, 0.7, 0.3], ["noise", 0, 0, 0.35, 0.1]],
		"oh": [["triangle", 320, 520, 0.22, 0.25], ["noise", 0, 0, 0.12, 0.1]],
		"swoosh": [["triangle", 200, 900, 0.14, 0.35]],
		# Pack opening.
		"rumble": [["square", 55, 50, 0.5, 0.35], ["noise", 0, 0, 0.1, 0.2]],
		"tear": [["noise", 0, 0, 0.18, 0.55], ["square", 1200, 300, 0.12, 0.25]],
		"slam": [["noise", 0, 0, 0.06, 0.6], ["square", 90, 40, 0.18, 0.5]],
		"reveal": [["square", 392, 784, 0.12, 0.3]],
		"sparkle": [["square", 2093, 2093, 0.03, 0.15], ["square", 2637, 2637, 0.03, 0.15], ["square", 3136, 3136, 0.06, 0.12]],
		"firework": [["noise", 0, 0, 0.05, 0.5], ["triangle", 900, 200, 0.25, 0.3]],
		"walkout": [["triangle", 110, 110, 0.25, 0.4], ["triangle", 147, 147, 0.25, 0.4], ["triangle", 165, 165, 0.25, 0.4],
				["triangle", 220, 220, 0.5, 0.45]],
		"elite": [["square", 523, 523, 0.09, 0.32], ["square", 659, 659, 0.09, 0.32], ["square", 784, 784, 0.09, 0.32],
				["square", 1047, 1047, 0.09, 0.32], ["square", 1319, 1319, 0.09, 0.32], ["square", 1568, 1568, 0.09, 0.32],
				["square", 2093, 2093, 0.4, 0.32]],
		# Pack tier climb: one rising step per tier, a deflating fake-out and the X-Factor zap.
		"climb0": [["square", 262, 294, 0.14, 0.3]],
		"climb1": [["square", 330, 392, 0.14, 0.32]],
		"climb2": [["square", 440, 523, 0.16, 0.34], ["square", 659, 659, 0.08, 0.3]],
		"climb3": [["square", 587, 784, 0.16, 0.36], ["square", 1047, 1047, 0.1, 0.32]],
		"fizzle": [["triangle", 400, 180, 0.35, 0.3]],
		"xf": [["noise", 0, 0, 0.05, 0.4], ["square", 1500, 300, 0.12, 0.3], ["square", 300, 1800, 0.18, 0.32]],
		"spin": [["square", 1200, 1200, 0.02, 0.15]],
	}
	for n in defs:
		_streams[n] = _build(defs[n])


func play(sound: String) -> void:
	if not _streams.has(sound) or Settings.sfx_volume <= 0.0:
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _streams[sound]
	p.volume_db = linear_to_db(Settings.sfx_volume)
	p.play()


static func _build(parts: Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var phase := 0.0
	for part in parts:
		var wave: String = part[0]
		var f0: float = part[1]
		var f1: float = part[2]
		var n := int(float(part[3]) * RATE)
		var vol: float = part[4]
		for i in n:
			var u := float(i) / maxf(n, 1)
			var f := lerpf(f0, f1, u)
			phase = fmod(phase + f / RATE, 1.0)
			var s := 0.0
			match wave:
				"square":
					s = 1.0 if phase < 0.5 else -1.0
				"triangle":
					s = 4.0 * absf(phase - 0.5) - 1.0
				"noise":
					s = rng.randf_range(-1.0, 1.0)
			var env := minf(1.0, (1.0 - u) * 4.0) * minf(1.0, u * 60.0 + 0.2)
			var v := int(clampf(s * vol * env, -1.0, 1.0) * 32767.0)
			data.append(v & 0xFF)
			data.append((v >> 8) & 0xFF)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w
