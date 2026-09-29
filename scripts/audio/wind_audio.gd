## Vent procédural : bruit blanc filtré (passe-bas à un pôle) dont la hauteur et le volume
## suivent la vitesse air. Aucun échantillon sonore.
class_name WindAudio
extends AudioStreamPlayer

const MIX_RATE := 22050.0

var bird: Bird
var _playback: AudioStreamGeneratorPlayback
var _lp := 0.0
var _lp2 := 0.0
var _rng := RandomNumberGenerator.new()
var _gain := 0.0
var _cutoff := 300.0


func setup(p_bird: Bird) -> void:
	bird = p_bird
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = MIX_RATE
	gen.buffer_length = 0.12
	stream = gen
	volume_db = -6.0
	_rng.seed = 1
	play()
	_playback = get_stream_playback()


func _process(dt: float) -> void:
	if _playback == null or bird == null:
		return
	var speed := bird.model.air_speed if bird.state == Bird.State.FLYING else 0.0
	var target_gain: float = clampf((speed - 4.0) / 26.0, 0.0, 1.0)
	target_gain = target_gain * target_gain
	if bird.model.diving:
		target_gain *= 1.3
	_gain = lerpf(_gain, target_gain, 3.0 * dt)
	_cutoff = lerpf(_cutoff, 180.0 + speed * 55.0, 3.0 * dt)
	var alpha := clampf(_cutoff / MIX_RATE * TAU, 0.0, 0.95)
	var frames := _playback.get_frames_available()
	if frames <= 0:
		return
	var buf := PackedVector2Array()
	buf.resize(frames)
	var g := _gain * 0.9
	for i in frames:
		var white := _rng.randf_range(-1.0, 1.0)
		_lp += alpha * (white - _lp)
		_lp2 += alpha * (_lp - _lp2)
		var s := _lp2 * g * 4.0
		buf[i] = Vector2(s, s * 0.97 + _lp * g * 0.1)
	_playback.push_buffer(buf)
