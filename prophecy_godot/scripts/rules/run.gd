class_name PRun
extends RefCounted
## (임시 스텁 — 회차는 이식 중) HTML run.js

static func add_log(run: Dictionary, msg: String) -> void:
	if not run.has("log"): run.log = []
	(run.log as Array).insert(0, "%d일차 · %s" % [int(run.get("day", 1)), msg])
	if (run.log as Array).size() > 8: (run.log as Array).resize(8)
