class_name SoundManager
extends Node

## Plays SoundCues. Requests only count up; once per frame each requested cue
## plays at most once, louder the more requests it stands for, within its own
## voice cap and the global one.

const POLYPHONY := 32

@export var bank: SoundBank

## Positional requests outside this world rect are dropped. Set by Main each frame.
var view_rect := Rect2()

var _player: AudioStreamPlayer
var _playback: AudioStreamPlaybackPolyphonic
var _pending: Dictionary[SoundCue, int] = {}
var _last_played: Dictionary[SoundCue, float] = {}
## Live voices, oldest first: { id, cue }.
var _voices: Array[Dictionary] = []


func _ready() -> void:
	var stream := AudioStreamPolyphonic.new()
	stream.polyphony = POLYPHONY
	_player = AudioStreamPlayer.new()
	_player.stream = stream
	add_child(_player)
	_player.play()
	_playback = _player.get_stream_playback()


## Release live voices and the player.
func _exit_tree() -> void:
	for voice in _voices:
		_playback.stop_stream(voice.id)
	_voices.clear()
	_playback = null
	_player.stop()
	_player.stream = null


func request(cue: SoundCue, count: int = 1) -> void:
	if cue == null or cue.stream == null or count <= 0:
		return
	_pending[cue] = _pending.get(cue, 0) + count


func request_at(cue: SoundCue, at: Vector2) -> void:
	if view_rect.has_point(at):
		request(cue)


func _process(_delta: float) -> void:
	if _pending.is_empty():
		return
	_reap()
	var now := Time.get_ticks_msec() / 1000.0
	for cue in _pending:
		if now - _last_played.get(cue, -INF) < cue.min_interval:
			continue
		var gain := minf(log(float(_pending[cue])) / log(2.0) * cue.stack_gain_db, cue.max_stack_db)
		if _play(cue, cue.volume_db + gain):
			_last_played[cue] = now
	_pending.clear()


func _play(cue: SoundCue, volume_db: float) -> bool:
	var victim := -1
	var own := 0
	for i in _voices.size():
		if _voices[i].cue == cue:
			own += 1
			if victim < 0:
				victim = i
	if own < cue.max_voices:
		victim = -1
		if _voices.size() >= POLYPHONY:
			for i in _voices.size():
				if _voices[i].cue.priority <= cue.priority:
					victim = i
					break
			if victim < 0:
				return false
	if victim >= 0:
		_playback.stop_stream(_voices[victim].id)
		_voices.remove_at(victim)

	var id := _playback.play_stream(cue.stream, 0.0, volume_db, 1.0,
		AudioServer.PLAYBACK_TYPE_DEFAULT, cue.bus)
	if id == AudioStreamPlaybackPolyphonic.INVALID_ID:
		return false
	_voices.append({ id = id, cue = cue })
	return true


func _reap() -> void:
	var live: Array[Dictionary] = []
	for voice in _voices:
		if _playback.is_stream_playing(voice.id):
			live.append(voice)
	_voices = live
