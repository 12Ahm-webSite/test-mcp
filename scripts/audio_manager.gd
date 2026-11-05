extends Node

var _crystal_sfx: Dictionary = {}
var _jump_sfx: AudioStreamWAV = null
var _dash_sfx: AudioStreamWAV = null
var _shield_hit_sfx: AudioStreamWAV = null
var _portal_sfx: AudioStreamWAV = null
var _alert_sfx: AudioStreamWAV = null

# Battle Mode SFX
var _pistol_sfx: AudioStreamWAV = null
var _smg_sfx: AudioStreamWAV = null
var _grenade_throw_sfx: AudioStreamWAV = null
var _explosion_sfx: AudioStreamWAV = null
var _hit_sfx: AudioStreamWAV = null
var _pickup_weapon_sfx: AudioStreamWAV = null
var _medkit_sfx: AudioStreamWAV = null
var _drone_laser_sfx: AudioStreamWAV = null
var _drone_alert_sfx: AudioStreamWAV = null
var _datapad_sfx: AudioStreamWAV = null

var _players: Array[AudioStreamPlayer] = []
const MAX_PLAYERS := 8
var _current_player_idx := 0

var _bgm_player: AudioStreamPlayer = null
var _bgm_tracks: Dictionary = {}
var _current_bgm_track: String = ""

func _ready() -> void:
	add_to_group("audio_manager")
	
	# Instantiate polyphonic audio player pool
	for i in range(MAX_PLAYERS):
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_players.append(p)
		
	# Dedicated looping BGM player
	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.bus = "Master"
	add_child(_bgm_player)
		
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
	
	# Battle SFX
	_pistol_sfx = _gen_gunshot(950.0, 0.12, 0.85)
	_smg_sfx = _gen_gunshot(750.0, 0.08, 0.70)
	_grenade_throw_sfx = _gen_sweep(450.0, 200.0, 0.18)
	_explosion_sfx = _gen_explosion(0.65)
	_hit_sfx = _gen_harmonic(220.0, 0.12)
	_pickup_weapon_sfx = _gen_chime(440.0, 880.0, 0.16)
	_medkit_sfx = _gen_trill(330.0, 660.0, 0.24)
	_drone_laser_sfx = _gen_sweep(1200.0, 400.0, 0.09)
	_drone_alert_sfx = _gen_trill(880.0, 1760.0, 0.22)
	_datapad_sfx = _gen_chord(0.3)

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

func play_pistol() -> void:
	play_sfx(_pistol_sfx, 0.0)

func play_smg() -> void:
	play_sfx(_smg_sfx, -1.0)

func play_grenade_throw() -> void:
	play_sfx(_grenade_throw_sfx, -2.0)

func play_explosion() -> void:
	play_sfx(_explosion_sfx, 3.0)

func play_hit() -> void:
	play_sfx(_hit_sfx, -2.0)

func play_weapon_pickup() -> void:
	play_sfx(_pickup_weapon_sfx, 0.0)

func play_medkit() -> void:
	play_sfx(_medkit_sfx, 1.0)

func play_drone_laser() -> void:
	play_sfx(_drone_laser_sfx, -2.0)

func play_drone_alert() -> void:
	play_sfx(_drone_alert_sfx, 1.0)

func play_datapad() -> void:
	play_sfx(_datapad_sfx, 1.0)

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
		var env := exp(-t * 8.0)
		var val_f := (sin(t * f * TAU) * 0.5 + sin(t * f * 2.0 * TAU) * 0.3 + sin(t * f * 3.0 * TAU) * 0.2) * env
		var val_i := int(clampf(val_f, -1.0, 1.0) * 32767.0)
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
	var chord := [523.25, 659.25, 783.99, 1046.5] # C Major 7/9
	
	for i in range(samples):
		var t := float(i) / float(rate)
		var env := exp(-t * 6.0)
		var sum := 0.0
		for f in chord:
			sum += sin(t * f * TAU)
		var val_f := (sum / float(chord.size())) * env * 0.8
		var val_i := int(clampf(val_f, -1.0, 1.0) * 32767.0)
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
		var progress := t / duration
		var freq := lerpf(f_start, f_end, progress)
		var env := sin(progress * PI)
		var val_f := sin(t * freq * TAU) * env * 0.65
		var val_i := int(clampf(val_f, -1.0, 1.0) * 32767.0)
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
	
	for i in range(samples):
		var t := float(i) / float(rate)
		var progress := t / duration
		var env := sin(progress * PI) * (1.0 - progress * 0.4)
		var noise := (randf() * 2.0 - 1.0) * 0.5
		var sweep := sin(t * lerpf(600.0, 140.0, progress) * TAU) * 0.5
		var val_f := (noise + sweep) * env * 0.7
		var val_i := int(clampf(val_f, -1.0, 1.0) * 32767.0)
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
		var env := exp(-t * 14.0)
		var tone := sin(t * 1200.0 * TAU) * 0.4 + sin(t * 2400.0 * TAU) * 0.3
		var noise := (randf() * 2.0 - 1.0) * 0.3
		var val_f := (tone + noise) * env * 0.8
		var val_i := int(clampf(val_f, -1.0, 1.0) * 32767.0)
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
		var lfo := sin(t * 8.0 * TAU) * 15.0
		var tone := sin(t * (220.0 + lfo) * TAU) * 0.5 + sin(t * (440.0 + lfo) * TAU) * 0.25
		var val_f := tone * env * 0.7
		var val_i := int(clampf(val_f, -1.0, 1.0) * 32767.0)
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

func _gen_gunshot(f_start: float, duration: float, intensity: float) -> AudioStreamWAV:
	var rate := 22050
	var samples := int(rate * duration)
	var bytes := PackedByteArray()
	bytes.resize(samples * 2)
	
	for i in range(samples):
		var t := float(i) / float(rate)
		var progress := t / duration
		var env := exp(-progress * 18.0) * intensity
		var cur_freq := f_start * exp(-progress * 25.0)
		var tone := sin(t * cur_freq * TAU)
		var noise := (randf() * 2.0 - 1.0)
		var sample_val := clampf((tone * 0.35 + noise * 0.65) * env, -1.0, 1.0)
		bytes.encode_s16(i * 2, int(sample_val * 32767.0))
		
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = bytes
	return stream

func _gen_explosion(duration: float) -> AudioStreamWAV:
	var rate := 22050
	var samples := int(rate * duration)
	var bytes := PackedByteArray()
	bytes.resize(samples * 2)
	
	for i in range(samples):
		var t := float(i) / float(rate)
		var progress := t / duration
		var env := exp(-progress * 5.0)
		var sub_bass := sin(t * (70.0 - progress * 40.0) * TAU) * 0.65
		var noise := (randf() * 2.0 - 1.0) * 0.55
		var sample_val := clampf((sub_bass + noise) * env, -1.0, 1.0)
		bytes.encode_s16(i * 2, int(sample_val * 32767.0))
		
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = bytes
	return stream

# ==============================================================================
# BACKGROUND MUSIC (BGM) SYSTEM & SYNTHESIZERS
# ==============================================================================

func play_bgm_for_level(level_id: String) -> void:
	if _current_bgm_track == level_id and _bgm_player != null and _bgm_player.playing:
		return
	
	var stream: AudioStreamWAV = _get_or_create_bgm(level_id)
	if not stream or _bgm_player == null:
		return
		
	_current_bgm_track = level_id
	_bgm_player.stream = stream
	_bgm_player.volume_db = -10.0
	_bgm_player.play()

func stop_bgm() -> void:
	if _bgm_player != null and _bgm_player.playing:
		_bgm_player.stop()
	_current_bgm_track = ""

func duck_bgm() -> void:
	if _bgm_player != null:
		var tw := create_tween()
		tw.tween_property(_bgm_player, "volume_db", -22.0, 0.8)

func _get_or_create_bgm(level_id: String) -> AudioStreamWAV:
	if _bgm_tracks.has(level_id):
		return _bgm_tracks[level_id]
		
	var stream: AudioStreamWAV = null
	var rate := 22050
	var duration := 8.0
	var samples := int(rate * duration)
	
	match level_id:
		"level_1", "battle_1":
			stream = _gen_bgm_ruins(rate, samples, duration)
		"level_2", "battle_2":
			stream = _gen_bgm_canyon(rate, samples, duration)
		"level_3", "battle_3":
			stream = _gen_bgm_caverns(rate, samples, duration)
		_:
			stream = _gen_bgm_ruins(rate, samples, duration)
			
	if stream:
		_bgm_tracks[level_id] = stream
	return stream

func _gen_bgm_ruins(rate: int, samples: int, duration: float) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples * 2)
	
	var note_freqs: Array[float] = [440.0, 522.5, 660.0, 392.0]
	
	for i in range(samples):
		var t := float(i) / float(rate)
		var p1: float = sin(t * 110.0 * TAU) * 0.22
		var p2: float = sin(t * 165.0 * TAU) * 0.16
		var p3: float = sin(t * 261.25 * TAU) * 0.12
		var p4: float = sin(t * 330.0 * TAU) * 0.10
		var pad: float = (p1 + p2 + p3 + p4) * (0.85 + 0.15 * sin(t * 0.25 * TAU))
		
		var arp_step: int = int(fmod(t * 2.0, 4.0))
		var cur_freq: float = note_freqs[arp_step]
		var note_t: float = fmod(t, 0.5)
		var arp_env: float = exp(-note_t * 8.0) * 0.18
		var arp: float = sin(note_t * cur_freq * TAU) * arp_env
		
		var sample_f: float = clampf(pad + arp, -1.0, 1.0)
		bytes.encode_s16(i * 2, int(sample_f * 32767.0))
		
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = bytes
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = samples
	return stream

func _gen_bgm_canyon(rate: int, samples: int, duration: float) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples * 2)
	
	for i in range(samples):
		var t := float(i) / float(rate)
		var beat_t: float = fmod(t, 0.5)
		var pulse_env: float = exp(-beat_t * 10.0) * 0.25
		var bass: float = sin(t * 73.42 * TAU) * (0.15 + pulse_env)
		
		var f_harm: float = 293.66 if fmod(t, 4.0) < 2.0 else 329.63
		var harmony: float = sin(t * f_harm * TAU) * 0.14
		var shimmer: float = sin(t * 587.25 * TAU) * (0.04 + 0.03 * sin(t * 0.5 * TAU))
		
		var sample_f: float = clampf(bass + harmony + shimmer, -1.0, 1.0)
		bytes.encode_s16(i * 2, int(sample_f * 32767.0))
		
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = bytes
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = samples
	return stream

func _gen_bgm_caverns(rate: int, samples: int, duration: float) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples * 2)
	
	var arp_freqs: Array[float] = [174.5, 207.5, 261.25, 311.125]
	
	for i in range(samples):
		var t := float(i) / float(rate)
		var sub: float = sin(t * 43.625 * TAU) * 0.35 + sin(t * 65.375 * TAU) * 0.2
		var sub_lfo: float = 0.8 + 0.2 * sin(t * 0.25 * TAU)
		
		var arp_idx: int = int(fmod(t * 4.0, 4.0))
		var arp_t: float = fmod(t, 0.25)
		var a_freq: float = arp_freqs[arp_idx]
		var a_env: float = exp(-arp_t * 14.0) * 0.22
		var arp: float = sin(arp_t * a_freq * TAU) * a_env
		
		var sweep_freq: float = 880.0 + sin(t * 0.25 * TAU) * 440.0
		var cavern_glow: float = sin(t * sweep_freq * TAU) * 0.06
		
		var sample_f: float = clampf((sub * sub_lfo) + arp + cavern_glow, -1.0, 1.0)
		bytes.encode_s16(i * 2, int(sample_f * 32767.0))
		
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = bytes
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = samples
	return stream
