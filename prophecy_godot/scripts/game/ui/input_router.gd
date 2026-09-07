class_name PInputRouter
extends RefCounted
## 장치 → 행동 변환(입력 확장 지점). 키보드·게임패드는 InputMap 행동(move_left/right/up/down · dodge · slowfield · skill_e)을 읽고,
## 가상 터치 상태(왼쪽 스틱 · 오른쪽 회피 유지·Q·E)를 같은 행동으로 합친다. 규칙(CombatState)은 장치를 모른다.
## 결과 형식은 PStepDriver가 이미 쓰는 것과 같다:
## - 누름(press: 회피·Q·E)은 이벤트가 온 순간 driver.note_*_press()로 기록 → 프레임 사이에 생겨도 다음 단계에서 정확히 1번 소비(PStepDriver 계약).
## - 유지(dodge_held)와 이동(mx, my)은 프레임 시작에 poll()로 읽어 그 프레임의 모든 단계에 같이 준다.
## 키보드만 쓸 때의 값은 godot-0.4.3 combat_view.gd의 인라인 코드와 같다(가상 상태가 비어 있으면 -1/0/1 합과 Input.is_action_pressed 그대로;
## 기준 전투 D33·PROPHECY_DODGE_DEMO·PROPHECY_CAPTURE가 이 경로를 쓴다). 이동 벡터의 크기는 CombatState가 PGeom.norm으로 정규화하므로
## 스틱 기울기 크기는 속도에 반영되지 않는다(방향만; 데드존은 여기서 처리).

const STICK_DEADZONE := 0.2

var virtual_move := Vector2.ZERO   # 가상 스틱(-1..1, 데드존 처리 뒤)
var virtual_held := false           # 가상 회피 버튼을 누르고 있음
var virtual_used := false           # 가상 입력이 한 번이라도 들어왔는지(HUD 문구 등 표시용)

## 가상 상태 폐기(일시정지·재시작·포커스 상실). 키보드 상태는 엔진(Input)이 가진다
func reset() -> void:
	virtual_move = Vector2.ZERO
	virtual_held = false

## 이벤트(키보드·게임패드·InputEventAction): 누름을 driver에 기록한다. 반복(echo)은 무시
func handle_event(event: InputEvent, driver: PStepDriver) -> void:
	if event.is_action_pressed("dodge") and not event.is_echo():
		driver.note_dodge_press()
	if event.is_action_pressed("slowfield") and not event.is_echo():
		driver.note_special_press()
	if event.is_action_pressed("skill_e") and not event.is_echo():
		driver.note_e_press()

## 프레임 시작: 이동 벡터와 유지 상태 {mx, my, held}
func poll() -> Dictionary:
	var mx := 0.0
	var my := 0.0
	if Input.is_action_pressed("move_left"):
		mx -= 1.0
	if Input.is_action_pressed("move_right"):
		mx += 1.0
	if Input.is_action_pressed("move_up"):
		my -= 1.0
	if Input.is_action_pressed("move_down"):
		my += 1.0
	var held: bool = Input.is_action_pressed("dodge")
	if virtual_move != Vector2.ZERO:
		mx += virtual_move.x
		my += virtual_move.y
	if virtual_held:
		held = true
	return { "mx": mx, "my": my, "held": held }

## 가상 버튼 누름(터치 오버레이·시험). kind = "dodge" | "special" | "e"
func virtual_press(kind: String, driver: PStepDriver) -> void:
	virtual_used = true
	match kind:
		"dodge": driver.note_dodge_press()
		"special": driver.note_special_press()
		"e": driver.note_e_press()

func set_virtual_move(v: Vector2) -> void:
	virtual_move = v
	if v != Vector2.ZERO:
		virtual_used = true

func set_virtual_held(h: bool) -> void:
	virtual_held = h
	if h:
		virtual_used = true

## 다음 단계가 받을 입력 사전 미리 보기(소비하지 않음). PStepDriver.frame이 만드는 사전과 같은 키·값
func preview(driver: PStepDriver) -> Dictionary:
	var p := poll()
	return { "mx": float(p.mx), "my": float(p.my), "dodge_press": driver.press_pending, "dodge_held": bool(p.held), "special": driver.special_pending, "skill_e": driver.e_pending }

## 가상 스틱: 중심에서의 오프셋(px) → -1..1 벡터. 데드존 안은 0, 데드존~반지름은 0..1로 다시 매핑, 반지름 밖은 길이 1(방향 유지)
static func stick_vector(offset: Vector2, radius: float, deadzone: float = STICK_DEADZONE) -> Vector2:
	if radius <= 0.0:
		return Vector2.ZERO
	var len: float = offset.length() / radius
	if len <= deadzone:
		return Vector2.ZERO
	var mag: float = minf(1.0, (len - deadzone) / maxf(0.0001, 1.0 - deadzone))
	return offset.normalized() * mag
