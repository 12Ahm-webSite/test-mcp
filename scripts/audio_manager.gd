extends Node

var _crystal_sfx: Dictionary = {}
var _jump_sfx: AudioStreamWAV = null
var _dash_sfx: AudioStreamWAV = null
var _shield_hit_sfx: AudioStreamWAV = null
var _portal_sfx: AudioStreamWAV = null
var _alert_sfx: AudioStreamWAV = null

var _players: Array[AudioStreamPlayer] = []
const MAX_PLAYERS := 8
var _current_player_idx := 0

func _ready() -> void:
	add_to_group("audio_manager")
	
	# Instantiate polyphonic audio player pool
	for i in range(MAX_PLAYERS):
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_players.append(p)
		
	_generate_all_sfx()

func _generate_all_sfx() -> void:
	_crystal_sfx[0] = _gen_chime(880.0, 1320.0, 0.22) # Energy
	_crystal_sfx[1] = _gen_trill(587.0, 1174.0, 0.25) # Speed
	_crystal_sfx[2] = _gen_harmonic(440.0, 0.3)      # Shield
	_crystal_sfx[3] = _gen_chord(0.35)              # Rare
	
	_jump_sfx = _gen_sweep(180.0, 420.0, 0.16)
	_dash_sfx = _gen_dash_whoosh(0.2)
	_shield_hit_sfx = _gen_deflect(0.25)
	_portal_sfx = _gen_portal_hum(0.8)
	_alert_sfx = _gen_alert(0.3)

func play_sfx(stream: AudioStreamWAV, volume_db: float = 0.0) -> void:
	if not stream or _players.is_empty():
		return
	var player := _players[_current_player_idx]
	_current_player_idx = (_current_player_idx + 1) % MAX_PLAYERS
	player.stream = stream
	player.volume_db = volume_db
	player.play()

func play_crystal(type: int) -> void:
	var sfx: AudioStreamWAV = _crystal_sfx.get(type, _crystal_sfx[0])
	play_sfx(sfx, -2.0)

func play_jump() -> void:
	play_sfx(_jump_sfx, -4.0)

func play_dash() -> void:
	play_sfx(_dash_sfx, -3.0)

func play_shield_hit() -> void:
	play_sfx(_shield_hit_sfx, 0.0)

func play_portal() -> void:
	play_sfx(_portal_sfx, 2.0)

func play_alert() -> void:
	play_sfx(_alert_sfx, -1.0)

# --- Procedural Audio Synthesizers (16-bit PCM Mono 22050Hz) ---

func _gen_chime(f1: float, f2: float, duration: float) -> AudioStreamWAV:
	var rate := 22050
	var samples := int(rate * duration)
	var bytes := PackedByteArray()
	bytes.resize(samples * 2)
	var half := samples / 2
	
	for i in range(samples):
		var t := float(i) / float(rate)
		var freq := f1 if i < half else f2
		var env := 1.0 - (float(i) / float(samples))
		var val_f := sin(t * freq * TAU) * env * 0.7
		var val_i := int(clampf(val_f, -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, val_i)
		
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = bytes
	return stream

func _gen_trill(f1: float, f2: float, duration: float) -> AudioStreamWAV:
	var rate := 22050
	var samples := int(rate * duration)
	var bytes := PackedByteArray()
	bytes.resize(samples * 2)
	
	for i in range(samples):
		var t := float(i) / float(rate)
		var freq := lerpf(f1, f2, (t / duration)) + sin(t * 30.0) * 40.0
		var env := 1.0 - (float(i) / float(samples))
		var val_f := (sin(t * freq * TAU) + 0.3 * sin(t * freq * 2.0 * TAU)) * env * 0.6
		var val_i := int(clampf(val_f, -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, val_i)
		
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = bytes
	return stream

func _gen_harmonic(f: float, duration: float) -> AudioStreamWAV:
	var rate := 22050
	var samples := int(rate * duration)
	var bytes := PackedByteArray()
	bytes.resize(samples * 2)
	
	for i in range(samples):
		var t := float(i) / float(rate)
		var env := 1.0 - (float(i) / float(samples))
		var wave := sin(t * f * TAU) * 0.5 + sin(t * f * 1.5 * TAU) * 0.3 + sin(t * f * 2.0 * TAU) * 0.2
		var val_i := int(clampf(wave * env, -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, val_i)
		
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = bytes
	return stream

func _gen_chord(duration: float) -> AudioStreamWAV:
	var rate := 22050
	var samples := int(rate * duration)
	var bytes := PackedByteArray()
	bytes.resize(samples * 2)
	var f1 := 523.25 # C5
	var f2 := 659.25 # E5
	var f3 := 783.99 # G5
	var f4 := 1046.5 # C6
	
	for i in range(samples):
		var t := float(i) / float(rate)
		var env := pow(1.0 - (float(i) / float(samples)), 1.5)
		var wave := (sin(t * f1 * TAU) + sin(t * f2 * TAU) + sin(t * f3 * TAU) + sin(t * f4 * TAU)) * 0.25
		var val_i := int(clampf(wave * env, -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, val_i)
		
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = bytes
	return stream

func _gen_sweep(f_start: float, f_end: float, duration: float) -> AudioStreamWAV:
	var rate := 22050
	var samples := int(rate * duration)
	var bytes := PackedByteArray()
	bytes.resize(samples * 2)
	
	for i in range(samples):
		var t := float(i) / float(rate)
		var frac := t / duration
		var freq := lerpf(f_start, f_end, frac)
		var env := sin(frac * PI)
		var wave := sin(t * freq * TAU) * env * 0.6
		var val_i := int(clampf(wave, -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, val_i)
		
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = bytes
	return stream

func _gen_dash_whoosh(duration: float) -> AudioStreamWAV:
	var rate := 22050
	var samples := int(rate * duration)
	var bytes := PackedByteArray()
	bytes.resize(samples * 2)
	
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	
	for i in range(samples):
		var frac := float(i) / float(samples)
		var env := sin(frac * PI) * (1.0 - frac * 0.5)
		var noise := rng.randf_range(-1.0, 1.0)
		var wave := noise * 0.6 + sin(frac * 60.0) * 0.4
		var val_i := int(clampf(wave * env * 0.8, -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, val_i)
		
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = bytes
	return stream

func _gen_deflect(duration: float) -> AudioStreamWAV:
	var rate := 22050
	var samples := int(rate * duration)
	var bytes := PackedByteArray()
	bytes.resize(samples * 2)
	
	for i in range(samples):
		var t := float(i) / float(rate)
		var env := exp(-t * 12.0)
		var wave := sin(t * 1200.0 * TAU) * 0.5 + sin(t * 700.0 * TAU) * 0.5
		var val_i := int(clampf(wave * env, -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, val_i)
		
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = bytes
	return stream

func _gen_portal_hum(duration: float) -> AudioStreamWAV:
	var rate := 22050
	var samples := int(rate * duration)
	var bytes := PackedByteArray()
	bytes.resize(samples * 2)
	
	for i in range(samples):
		var t := float(i) / float(rate)
		var env := sin((float(i) / float(samples)) * PI)
		var wave := sin(t * 220.0 * TAU) * 0.4 + sin(t * 440.0 * TAU) * 0.3 + sin(t * 660.0 * TAU) * 0.3
		var val_i := int(clampf(wave * env * 0.9, -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, val_i)
		
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = bytes
	return stream

func _gen_alert(duration: float) -> AudioStreamWAV:
	var rate := 22050
	var samples := int(rate * duration)
	var bytes := PackedByteArray()
	bytes.resize(samples * 2)
	
	for i in range(samples):
		var t := float(i) / float(rate)
		var env := 1.0 - (float(i) / float(samples))
		var freq := 660.0 if fmod(t, 0.1) < 0.05 else 880.0
		var wave := sin(t * freq * TAU) * env * 0.6
		var val_i := int(clampf(wave, -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, val_i)
		
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = bytes
	return stream
