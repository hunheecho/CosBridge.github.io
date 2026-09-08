class_name PAudio
extends Node
## 합성음(HTML audio.js 이식). 외부 파일 없음: 짧은 톤·잡음을 AudioStreamGenerator(모노 22050Hz)로 만들어 PackedFloat32Array로 캐시하고, 재생 중인 소리를 매 프레임 섞어 밀어 넣는다.
## 음량(0..1)·음소거는 user://audio_prefs.json에 저장. 오디오 장치가 없어도(헤드리스) 오류 없이 조용히 동작한다.
## drain(st): st.events에 새로 쌓인 이름을 소리로 바꾼다(프레임당 최대 6개, 같은 이름은 40ms 안에 1번).
##
## 기술별 구분(타격감): 규칙이 이미 내주는 부가 데이터만 읽는다 — st.events_data의 swing{form: arc|beam|melee}과 hit{crit}.
##   같은 "hit"이라도 어떤 기술이 낸 적중인지에 따라 hit_arc·hit_beam·hit_melee·hit_shot으로 나눠 낸다(치명타는 crit).
##   휘두르는 소리도 swing_arc·swing_beam·swing_melee로 나눈다. 규칙에 새 신호를 넣지 않았고, 소리 선택은 판정에 아무 영향이 없다.
##   적중 이벤트는 그 기술의 swing/shoot 이벤트 바로 앞에 쌓이므로(무기 코드가 피해를 먼저 주고 소리 이름을 낸다) 뒤쪽 8칸까지만 보고 짝을 짓는다.

const RATE := 22050
const MAX_PER_FRAME := 6
const MAX_DUR := 0.3
const PREFS := "user://audio_prefs.json"

var volume: float = 0.5
var muted: bool = false
var _player: AudioStreamPlayer = null
var _pb: AudioStreamGeneratorPlayback = null
var _ok: bool = false
var _cache: Dictionary = {}     # name → PackedFloat32Array
var _voices: Array = []         # [{buf: PackedFloat32Array, pos: int}]
var _last: Dictionary = {}      # name → msec(마지막 재생)
var _ev_idx: int = 0
var _evd_idx: int = 0           # st.events_data에서 다음에 볼 자리(이름이 있는 이벤트의 부가 데이터)
var _ev_st_id: int = 0

func _ready() -> void:
	load_prefs()
	_setup()

func _setup() -> void:
	var devs: PackedStringArray = AudioServer.get_output_device_list()
	if devs.is_empty() or AudioServer.get_mix_rate() <= 0.0:
		return
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = float(RATE)
	gen.buffer_length = 0.12
	_player = AudioStreamPlayer.new()
	_player.name = "Synth"
	_player.stream = gen
	# 웹(브라우저)에서 기본 재생 방식은 '샘플'이고, 생성기 스트림은 샘플로 재생할 수 없다.
	# 그대로 두면 브라우저에서 "cannot be sampled" 오류가 나고 소리가 하나도 나지 않는다.
	# 어느 플랫폼에서든 이 합성음은 '스트림'으로만 재생하므로 못 박아 둔다.
	_player.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	add_child(_player)
	_player.play()
	var pb := _player.get_stream_playback()
	if pb is AudioStreamGeneratorPlayback:
		_pb = pb
		_ok = true

## 종료 시 생성기 재생을 먼저 멈추고 playback 참조를 놓는다(내보낸 빌드에서 종료 중 AudioServer 정리 뒤 접근을 막기 위해)
func _exit_tree() -> void:
	_ok = false
	_pb = null
	_voices.clear()
	if _player != null and is_instance_valid(_player):
		_player.stop()

func _process(_dt: float) -> void:
	if not _ok or _pb == null:
		return
	if not _player.playing:
		_player.play()
		var pb := _player.get_stream_playback()
		if pb is AudioStreamGeneratorPlayback:
			_pb = pb
	var n: int = _pb.get_frames_available()
	if n <= 0:
		return
	var master: float = 0.0 if muted else volume
	var out := PackedVector2Array()
	out.resize(n)
	if _voices.is_empty() or master <= 0.0:
		out.fill(Vector2.ZERO)
		_voices.clear()
	else:
		out.fill(Vector2.ZERO)
		var keep: Array = []
		for v in _voices:
			var buf: PackedFloat32Array = v.buf
			var pos: int = v.pos
			var m: int = mini(n, buf.size() - pos)
			for i in m:
				var s: float = buf[pos + i] * master
				out[i] += Vector2(s, s)
			v.pos = pos + m
			if v.pos < buf.size():
				keep.append(v)
		_voices = keep
		for i in n:
			var s: Vector2 = out[i]
			out[i] = Vector2(clampf(s.x, -1.0, 1.0), clampf(s.y, -1.0, 1.0))
	_pb.push_buffer(out)

# ---------- 설정 ----------
func load_prefs() -> void:
	if not FileAccess.file_exists(PREFS):
		return
	var f := FileAccess.open(PREFS, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	if parsed.has("volume") and typeof(parsed.volume) == TYPE_FLOAT:
		volume = clampf(float(parsed.volume), 0.0, 1.0)
	if parsed.has("muted") and typeof(parsed.muted) == TYPE_BOOL:
		muted = bool(parsed.muted)

func save_prefs() -> void:
	var f := FileAccess.open(PREFS, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({ "volume": volume, "muted": muted }))

func set_volume(v: float) -> void:
	volume = clampf(v, 0.0, 1.0)
	save_prefs()

func set_muted(b: bool) -> void:
	muted = b
	save_prefs()

# ---------- 재생 ----------
func play(snd: String) -> void:
	if not _ok or muted:
		return
	var now: int = Time.get_ticks_msec()
	if _last.has(snd) and now - int(_last[snd]) < 40:
		return
	_last[snd] = now
	var buf := _sound(snd)
	if buf.is_empty():
		return
	_voices.append({ "buf": buf, "pos": 0 })

## 새 전투 상태에 연결. skip_existing=true면 이미 쌓인 이벤트는 재생하지 않는다(준비된 상태를 넘겨받을 때)
func reset(st: CombatState, skip_existing: bool = false) -> void:
	_ev_st_id = st.get_instance_id() if st != null else 0
	_ev_idx = st.events.size() if (st != null and skip_existing) else 0
	_evd_idx = st.events_data.size() if (st != null and skip_existing) else 0
	_break_seen = false

## 보스 지형 파괴 **예고** 전용 소리(docs/BOSS_BREAK.md). 규칙은 파괴가 일어난 뒤에만 shatter를 내주므로
## 예고에는 소리가 없었다(자격이 설 때 나는 boss_lock은 다른 공격 확정과 같은 소리다).
## 규칙에 새 이벤트를 넣지 않고 **표시 계층에서** 보스의 파괴 자격(break_want)이 서는 순간을 보고 낸다 —
## 상태를 읽기만 하고 판정·난수에는 아무 영향이 없다(적중 소리를 기술별로 나누는 것과 같은 방식).
var _break_seen := false

func _break_warn_due(st: CombatState) -> bool:
	var want := false
	for e in st.enemies:
		if bool(e.get("break_want", false)) and not bool(e.dead):
			want = true
			break
	var fire: bool = want and not _break_seen
	_break_seen = want
	return fire

## 적중 소리를 기술별로 나눈다. 값은 규칙이 이미 내주던 것(form)뿐이고 판정에는 쓰이지 않는다
const HIT_BY_FORM := { "arc": "hit_arc", "beam": "hit_beam", "melee": "hit_melee", "shot": "hit_shot" }
const SWING_BY_FORM := { "arc": "swing_arc", "beam": "swing_beam", "melee": "swing_melee" }
const FORM_LOOKAHEAD := 8   # 적중 뒤 이 칸 안에 오는 발사 이벤트까지만 같은 기술로 본다

## st.events의 새 항목을 소리로. 프레임당 최대 MAX_PER_FRAME개(넘치는 것은 버린다)
func drain(st: CombatState) -> void:
	if st == null:
		return
	if st.get_instance_id() != _ev_st_id:
		reset(st, true)
	if _ev_idx > st.events.size():
		_ev_idx = 0
		_evd_idx = 0
	if _evd_idx > st.events_data.size():
		_evd_idx = 0
	if _break_warn_due(st):     # 파괴 예고: 다른 확정 소리와 섞이지 않게 이벤트 처리 앞에서 한 번만
		play("break_warn")
	var r := _plan(st)
	var played := 0
	for snd in r.names:
		if played >= MAX_PER_FRAME:
			break
		if _has_sound(String(snd)):
			play(String(snd))
			played += 1
	_ev_idx = st.events.size()
	_evd_idx = int(r.next_d)

## 아직 소리로 내지 않은 이벤트가 어떤 소리 이름으로 나갈지(시험·진단용 — 상태를 바꾸지 않는다)
func pending_sounds(st: CombatState) -> Array:
	return _plan(st).names

## 이번에 처리할 구간의 이벤트 → 소리 이름. events_data와 짝을 맞추고 적중의 기술 모양을 정한다
func _plan(st: CombatState) -> Dictionary:
	var ev: Array = st.events
	var evd: Array = st.events_data
	var n: int = ev.size()
	# ① 이벤트 번호 ↔ 부가 데이터 맞추기(events_data는 events의 부분열이라 앞에서부터 이름으로 맞으면 된다)
	var data_at := {}
	var dp: int = _evd_idx
	var i: int = _ev_idx
	while i < n:
		if dp < evd.size() and String((evd[dp] as Dictionary).get("name", "")) == String(ev[i]):
			data_at[i] = evd[dp]
			dp += 1
		i += 1
	# ② 각 적중이 어느 기술에서 나왔는지: 무기 코드가 피해를 먼저 주고 소리 이름을 나중에 내므로 뒤에서 앞으로 훑는다
	var forms := _forms_for(ev, data_at, _ev_idx, n)
	var names := []
	i = _ev_idx
	while i < n:
		names.append(_variant(String(ev[i]), data_at.get(i, {}), String(forms.get(i, ""))))
		i += 1
	return { "names": names, "next_d": dp }

## 구간 [from, to)의 각 적중 번호 → 기술 모양(arc|beam|melee|shot). 짝을 못 찾으면 넣지 않는다
func _forms_for(ev: Array, data_at: Dictionary, from: int, to: int) -> Dictionary:
	var out := {}
	var form := ""
	var at := -9999
	var j: int = to - 1
	while j >= from:
		var nm := String(ev[j])
		if nm == "swing":
			form = String((data_at.get(j, {}) as Dictionary).get("form", ""))
			at = j
		elif nm == "shoot":
			form = "shot"
			at = j
		elif nm == "hit" and form != "" and at - j <= FORM_LOOKAHEAD:
			out[j] = form
		j -= 1
	return out

## 이벤트 이름 → 실제로 낼 소리 이름. 규칙 이벤트는 그대로 두고 표시 계층에서만 갈래를 고른다
func _variant(name: String, data: Dictionary, form: String) -> String:
	if name == "swing":
		return String(SWING_BY_FORM.get(String(data.get("form", "")), "swing"))
	if name == "hit":
		if bool(data.get("crit", false)):
			return "crit"
		return String(HIT_BY_FORM.get(form, "hit"))
	return name

# ---------- 합성 ----------
const NAMES := ["hit", "crit", "kill", "hurt", "lock", "bite_lock", "dodge", "perfect", "special", "chest", "win", "lose", "wave", "group", "shoot", "spore", "explode", "shatter", "burst", "bite", "boss_howl", "boss_roar", "boss_land", "boss_sweep", "boss_lock", "orb", "swing", "levelup", "skill_e", "hazard_warn", "hazard_arm", "reinforce", "rescued", "saving", "dash_hit", "timeout", "ui", "ready_dodge", "ready_q", "ready_e", "seal_move_warn", "altar_heal", "block",
	# 기술별 적중·휘두름(타격감) + 보스 사망 반응
	"hit_arc", "hit_beam", "hit_melee", "hit_shot", "swing_arc", "swing_beam", "swing_melee", "boss_down",
	# 보스 지형 파괴 **예고**(부서지는 소리 shatter와 반대 방향의 낮은 삐걱임 — 아직 안 부서졌음을 알린다)
	"break_warn"]

func _has_sound(snd: String) -> bool:
	return NAMES.has(snd)

func _sound(snd: String) -> PackedFloat32Array:
	if _cache.has(snd):
		return _cache[snd]
	var buf := _synth(snd)
	_cache[snd] = buf
	return buf

static func _ensure(buf: PackedFloat32Array, n: int) -> PackedFloat32Array:
	if buf.size() < n:
		var old: int = buf.size()
		buf.resize(n)
		for i in range(old, n):
			buf[i] = 0.0
	return buf

## 톤: type = sine|square|sawtooth|triangle. gain은 dur 동안 0.001로 지수 감쇠, sweep_to>0이면 주파수도 지수 이동
static func _tone(buf: PackedFloat32Array, at: float, freq: float, dur: float, type: String, gain: float, sweep_to: float = 0.0) -> PackedFloat32Array:
	dur = minf(dur, MAX_DUR - at)
	if dur <= 0.0:
		return buf
	var start: int = int(at * RATE)
	var n: int = int(dur * RATE)
	buf = _ensure(buf, start + n)
	var phase := 0.0
	var ratio: float = (sweep_to / freq) if sweep_to > 0.0 else 1.0
	var decay: float = 0.001 / maxf(0.001, gain)
	for i in n:
		var k: float = float(i) / float(n)
		var f: float = freq * pow(ratio, k)
		phase += f / float(RATE)
		var ph: float = phase - floor(phase)
		var w: float
		match type:
			"square": w = 1.0 if ph < 0.5 else -1.0
			"sawtooth": w = 2.0 * ph - 1.0
			"triangle": w = 4.0 * absf(ph - 0.5) - 1.0
			_: w = sin(TAU * ph)
		buf[start + i] += w * gain * pow(decay, k)
	return buf

## 잡음: 선형 감쇠. hp>0이면 1극 고역통과(차단 hp Hz), 아니면 800Hz 저역통과
static func _noise(buf: PackedFloat32Array, at: float, dur: float, gain: float, hp: float = 0.0, seed_v: int = 1) -> PackedFloat32Array:
	dur = minf(dur, MAX_DUR - at)
	if dur <= 0.0:
		return buf
	var start: int = int(at * RATE)
	var n: int = int(dur * RATE)
	buf = _ensure(buf, start + n)
	var rng := PRng.new(seed_v * 7919 + 13)
	var dt: float = 1.0 / float(RATE)
	var fc: float = hp if hp > 0.0 else 800.0
	var rc: float = 1.0 / (TAU * fc)
	var a_lp: float = dt / (rc + dt)
	var a_hp: float = rc / (rc + dt)
	var y := 0.0
	var xp := 0.0
	for i in n:
		var x: float = (rng.next() * 2.0 - 1.0) * (1.0 - float(i) / float(n))
		if hp > 0.0:
			y = a_hp * (y + x - xp)
			xp = x
		else:
			y += a_lp * (x - y)
		buf[start + i] += y * gain
	return buf

static func _synth(snd: String) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	match snd:
		"hit":
			b = _tone(b, 0.0, 320.0, 0.06, "square", 0.12)
			b = _noise(b, 0.0, 0.04, 0.08, 2000.0, 1)
		"dash_hit":
			b = _tone(b, 0.0, 260.0, 0.07, "square", 0.14, 180.0)
			b = _noise(b, 0.0, 0.05, 0.1, 1500.0, 2)
		"crit":
			b = _tone(b, 0.0, 520.0, 0.08, "square", 0.15, 700.0)
			b = _noise(b, 0.0, 0.05, 0.1, 2500.0, 3)
		"kill":
			b = _tone(b, 0.0, 180.0, 0.15, "triangle", 0.2, 60.0)
			b = _noise(b, 0.0, 0.08, 0.12, 0.0, 4)
		"hurt":
			b = _tone(b, 0.0, 140.0, 0.25, "sawtooth", 0.25, 60.0)
			b = _noise(b, 0.0, 0.1, 0.15, 0.0, 5)
		"lock":
			b = _tone(b, 0.0, 900.0, 0.05, "square", 0.12)
			b = _tone(b, 0.06, 1100.0, 0.06, "square", 0.12)
		"bite_lock":
			b = _tone(b, 0.0, 700.0, 0.05, "square", 0.12)
			b = _tone(b, 0.06, 950.0, 0.06, "square", 0.12)
		"boss_lock":
			b = _tone(b, 0.0, 500.0, 0.08, "square", 0.18)
			b = _tone(b, 0.09, 700.0, 0.1, "square", 0.2)
		"dodge":
			b = _noise(b, 0.0, 0.12, 0.12, 1200.0, 6)
		"perfect":
			b = _tone(b, 0.0, 1200.0, 0.12, "sine", 0.2, 1800.0)
		"saving":
			b = _tone(b, 0.0, 900.0, 0.1, "sine", 0.15, 1400.0)
			b = _tone(b, 0.1, 1400.0, 0.1, "sine", 0.12, 1800.0)
		"special":
			b = _tone(b, 0.0, 220.0, 0.3, "sine", 0.2, 110.0)
			b = _tone(b, 0.0, 330.0, 0.3, "sine", 0.12, 165.0)
		"skill_e":
			b = _tone(b, 0.0, 600.0, 0.25, "sine", 0.2, 100.0)
			b = _noise(b, 0.0, 0.12, 0.12, 0.0, 7)
		"burst":
			b = _tone(b, 0.0, 600.0, 0.25, "sine", 0.2, 100.0)
			b = _noise(b, 0.0, 0.15, 0.15, 0.0, 8)
		"chest", "rescued":
			for i in 3:
				b = _tone(b, float(i) * 0.07, [660.0, 880.0, 1100.0][i], 0.1, "triangle", 0.15)
		"win":
			for i in 4:
				b = _tone(b, float(i) * 0.065, [523.0, 659.0, 784.0, 1046.0][i], 0.1, "triangle", 0.18)
		"lose":
			for i in 3:
				b = _tone(b, float(i) * 0.1, [400.0, 300.0, 200.0][i], 0.1, "sawtooth", 0.18)
		"timeout":
			b = _tone(b, 0.0, 300.0, 0.14, "sawtooth", 0.16)
			b = _tone(b, 0.15, 200.0, 0.14, "sawtooth", 0.16)
		"wave", "reinforce", "group":
			b = _tone(b, 0.0, 90.0, 0.3, "sine", 0.25, 50.0)
		"shoot":
			b = _noise(b, 0.0, 0.06, 0.1, 3000.0, 9)
		"spore":
			b = _tone(b, 0.0, 200.0, 0.3, "sine", 0.15, 80.0)
			b = _noise(b, 0.0, 0.2, 0.08, 0.0, 10)
		"explode":
			b = _noise(b, 0.0, 0.25, 0.25, 0.0, 11)
			b = _tone(b, 0.0, 100.0, 0.3, "sawtooth", 0.15, 40.0)
		"shatter":
			b = _tone(b, 0.0, 1500.0, 0.1, "square", 0.1, 900.0)
		"break_warn": # 파괴 **예고**: 낮은 곳에서 위로 훑는 삐걱임 두 번 + 굵은 잡음.
			# 실제 파괴음(shatter, 높은 곳에서 아래로 떨어지는 짧은 사각파)과 방향이 반대라 소리만으로 갈린다
			b = _tone(b, 0.0, 90.0, 0.13, "sawtooth", 0.16, 220.0)
			b = _tone(b, 0.15, 110.0, 0.13, "sawtooth", 0.16, 260.0)
			b = _noise(b, 0.0, 0.12, 0.10, 300.0, 21)
		"bite":
			b = _noise(b, 0.0, 0.05, 0.2, 400.0, 12)
			b = _tone(b, 0.0, 220.0, 0.08, "square", 0.15, 90.0)
		"boss_howl":
			b = _tone(b, 0.0, 160.0, 0.3, "sawtooth", 0.18, 240.0)
			b = _tone(b, 0.0, 80.0, 0.3, "sine", 0.2, 120.0)
		"boss_roar":
			b = _tone(b, 0.0, 90.0, 0.3, "sawtooth", 0.25, 50.0)
			b = _noise(b, 0.0, 0.3, 0.2, 0.0, 13)
		"boss_land", "hazard_arm":
			b = _tone(b, 0.0, 60.0, 0.3, "sine", 0.35, 30.0)
			b = _noise(b, 0.0, 0.25, 0.3, 0.0, 14)
		"boss_sweep":
			b = _noise(b, 0.0, 0.18, 0.2, 600.0, 15)
			b = _tone(b, 0.0, 140.0, 0.2, "triangle", 0.15, 70.0)
		"hazard_warn":
			b = _tone(b, 0.0, 800.0, 0.05, "square", 0.1)
			b = _tone(b, 0.12, 800.0, 0.05, "square", 0.1)
		"orb", "levelup":
			for i in 3:
				b = _tone(b, float(i) * 0.06, [880.0, 1175.0, 1568.0][i], 0.12, "sine", 0.15)
		"swing":
			b = _noise(b, 0.0, 0.07, 0.05, 2500.0, 16)
		# ---------- 기술별 적중(타격감): 음색·음높이·길이를 서로 다르게 해 소리만으로 어떤 기술이 맞았는지 알게 한다 ----------
		"hit_arc": # 베기: 높은 쇳소리 + 스치는 잡음(짧고 날카롭게)
			b = _tone(b, 0.0, 520.0, 0.05, "square", 0.11, 380.0)
			b = _noise(b, 0.0, 0.05, 0.09, 3200.0, 17)
		"hit_beam": # 관통: 낮게 꽂히는 소리(아래로 훑는 삼각파 + 굵은 잡음)
			b = _tone(b, 0.0, 240.0, 0.09, "triangle", 0.15, 120.0)
			b = _noise(b, 0.0, 0.06, 0.09, 900.0, 18)
		"hit_melee": # 단검: 아주 짧고 높은 톡(연타에 묻히지 않게 가장 짧다)
			b = _tone(b, 0.0, 720.0, 0.035, "square", 0.10)
			b = _noise(b, 0.0, 0.025, 0.07, 4000.0, 19)
		"hit_shot": # 원거리 명중: 딱 하고 박히는 소리(중간 음, 잡음 짧게)
			b = _tone(b, 0.0, 400.0, 0.05, "square", 0.11, 300.0)
			b = _noise(b, 0.0, 0.03, 0.08, 2200.0, 20)
		# ---------- 기술별 휘두름(발사 순간) ----------
		"swing_arc":
			b = _noise(b, 0.0, 0.08, 0.055, 2200.0, 21)
		"swing_beam":
			b = _noise(b, 0.0, 0.06, 0.05, 1200.0, 22)
			b = _tone(b, 0.0, 300.0, 0.06, "triangle", 0.05, 200.0)
		"swing_melee":
			b = _noise(b, 0.0, 0.04, 0.045, 3500.0, 23)
			b = _noise(b, 0.05, 0.04, 0.04, 3500.0, 24)
		"boss_down": # 보스 사망 반응: 길게 무너지는 저음 + 잡음
			b = _tone(b, 0.0, 150.0, 0.3, "sawtooth", 0.26, 40.0)
			b = _noise(b, 0.0, 0.28, 0.18, 0.0, 25)
		"ui":
			b = _tone(b, 0.0, 700.0, 0.04, "square", 0.06)
		# 준비 완료 신호(회피/Q/E): false→true 전환에 딱 1번. 음색·음높이를 서로 다르게 해 소리만으로도 구분되게 한다.
		# 소리를 꺼도 테두리 점등·쿨다운 숫자로 같은 정보를 읽을 수 있다(PCombatHud).
		"ready_dodge": # 짧은 삼각파 위로(가벼운 발놀림)
			b = _tone(b, 0.0, 620.0, 0.07, "triangle", 0.10, 900.0)
		"ready_q": # 두 음 사인(낮→높, 장 개시)
			b = _tone(b, 0.0, 440.0, 0.07, "sine", 0.10)
			b = _tone(b, 0.06, 660.0, 0.09, "sine", 0.10)
		"ready_e": # 사각파 두 번 두드림(무거운 기술)
			b = _tone(b, 0.0, 330.0, 0.06, "square", 0.09)
			b = _tone(b, 0.09, 330.0, 0.08, "square", 0.09)
	return b
