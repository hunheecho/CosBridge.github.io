class_name PStepDriver
extends RefCounted
## 프레임 → 고정 단계 변환 연결부. 화면(CombatView)과 프레임률 테스트가 같은 코드를 쓴다.
## - 누름(press)은 프레임 사이에 생겨도 잃지 않고, 다음에 실행되는 첫 단계에서 정확히 1번만 소비된다.
## - 누르고 있음(held)은 프레임 시작 시점의 상태를 그 프레임의 모든 단계에 같이 준다.
## - 한 프레임에 여러 단계를 진행해도 press를 중복 소비하지 않는다. 대기 중인 press는 reset()으로 버린다(일시정지·재시작·포커스 상실).

const STEP := 1.0 / 120.0
const MAX_STEPS_PER_FRAME := 12

var acc: float = 0.0
var press_pending: bool = false
var special_pending: bool = false
var e_pending: bool = false
var steps_last_frame: int = 0

func reset() -> void:
	acc = 0.0
	press_pending = false
	special_pending = false
	e_pending = false
	steps_last_frame = 0

func note_dodge_press() -> void:
	press_pending = true

func note_special_press() -> void:
	special_pending = true

func note_e_press() -> void:
	e_pending = true

## delta초만큼 진행. bot이 있으면 봇 입력, 없으면 (mx,my,held)와 대기 중인 press로 사람 입력을 만든다. 실행한 단계 수를 돌려준다.
func frame(st: CombatState, delta: float, mx: float, my: float, held: bool, bot: PBot = null) -> int:
	acc += minf(delta, 0.1)
	var n := 0
	while acc >= STEP and n < MAX_STEPS_PER_FRAME:
		var inp: Dictionary
		if bot != null:
			inp = bot.step_input(st)
		else:
			inp = { "mx": mx, "my": my, "dodge_press": press_pending, "dodge_held": held, "special": special_pending, "skill_e": e_pending }
			press_pending = false
			special_pending = false
			e_pending = false
		st.step(inp, STEP)
		acc -= STEP
		n += 1
	if n >= MAX_STEPS_PER_FRAME:
		acc = 0.0 # 너무 긴 프레임: 남은 시간을 버려 멈춤 방지(HTML과 같은 방식)
	steps_last_frame = n
	return n
