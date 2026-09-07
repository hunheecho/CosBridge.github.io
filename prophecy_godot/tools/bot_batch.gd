extends SceneTree
## 실력 봇 배치 실행기 진입점(헤드리스): 환경 변수를 읽어 PBotBatch.run()을 부른다. 본체·환경 변수 목록: tools/bot_batch_core.gd, 규칙·형식: docs/BOT_FRAMEWORK.md.
## 사용: PROPHECY_BOT_RUN_ID=<id> [PROPHECY_BOT_MODE=compare|throughput|report] [PROPHECY_BOT_BUDGET_SEC=600] godot --headless --path prophecy_godot -s tools/bot_batch.gd
## 종료 코드: 0 완료 · 2 캐시 키 불일치(무효화) · 3 예산 초과로 부분 완료(같은 run_id로 재개)

func _init() -> void:
	var b := PBotBatch.new()
	var r := b.run({})
	quit(int(r.code))
