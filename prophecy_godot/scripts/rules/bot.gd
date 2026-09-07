class_name PBot
extends RefCounted
## 봇 입력(시험·영상용). 사람 입력과 같은 {mx,my,dodge_press,dodge_held,special}를 만든다. 규칙 우회·즉시 종료·접촉 무시 처리 없음.
## 정책(policy):
##  - "stand": 제자리에서 자동 공격만(입력 없음). 밀도 비교의 기준선.
##  - "active": 확정된 돌진 통로 안이면 옆으로 회피(press, 끝날 때까지 held → 최대 거리), 물기 고정/유효 구간의 부채꼴 안이면 옆으로 회피,
##              위협이 없으면 가장 가까운 적에게 접근, 200 안에 2마리 이상이면 Q. (v2: 물기 회피 추가. v1은 돌진 통로만)
## 판단 주기 5스텝(HTML DECIDE_STEPS와 동일)

var policy: String = "active"
var last: Dictionary = { "mx": 0.0, "my": 0.0, "dodge_press": false, "dodge_held": false, "special": false }

func _init(pol: String = "active") -> void:
	policy = pol

func step_input(st: CombatState) -> Dictionary:
	if policy == "stand":
		return { "mx": 0.0, "my": 0.0, "dodge_press": false, "dodge_held": false, "special": false }
	if st.step_n % 5 != 0:
		return { "mx": last.mx, "my": last.my, "dodge_press": false, "dodge_held": bool(last.dodge_held) or st.player.dodge_active, "special": false }
	last = decide(st)
	return last

func decide(st: CombatState) -> Dictionary:
	var p := st.player
	var mx := 0.0
	var my := 0.0
	var dodge := false
	var special := false
	var threatened := false
	for e in st.alive_enemies():
		var d: Dictionary = e.def
		if e.state == "lock" or e.state == "dash":
			var L := float(d.dash.dash_speed) * float(d.dash.dash_time)
			var ex: float = e.x + cos(e.dir) * L
			var ey: float = e.y + sin(e.dir) * L
			if PGeom.seg_circle(e.x, e.y, ex, ey, p.x, p.y, p.r + e.r + 10.0):
				threatened = true
				var side := [-sin(e.dir), cos(e.dir)]
				var rel: float = (p.x - e.x) * side[0] + (p.y - e.y) * side[1]
				var s := 1.0 if rel >= 0.0 else -1.0
				mx += side[0] * s
				my += side[1] * s
				if e.state == "lock":
					dodge = true
		elif e.state == "bite_lock" or e.state == "bite_hit":
			var dist := PGeom.dist(e.x, e.y, p.x, p.y)
			if dist <= float(d.bite.reach) + 24.0:
				var ang := atan2(p.y - e.y, p.x - e.x)
				if absf(PGeom.ang_diff(ang, e.dir)) <= float(d.bite.arc_deg) * PI / 360.0 + 0.35:
					threatened = true
					var side2 := [-sin(e.dir), cos(e.dir)]
					var rel2: float = (p.x - e.x) * side2[0] + (p.y - e.y) * side2[1]
					var s2 := 1.0 if rel2 >= 0.0 else -1.0
					mx += side2[0] * s2
					my += side2[1] * s2
					if e.state == "bite_lock":
						dodge = true
	if not threatened:
		var best := {}
		var bd := INF
		for e in st.alive_enemies():
			var dd := PGeom.dist(p.x, p.y, e.x, e.y)
			if dd < bd:
				bd = dd
				best = e
		if not best.is_empty() and bd > 60.0:
			var n := st.steer_dir({ "x": p.x, "y": p.y, "r": p.r, "steer_side": 0, "steer_t": 0.0 }, best.x, best.y)
			mx = n[0]
			my = n[1]
	var near := 0
	for e in st.alive_enemies():
		if PGeom.dist(p.x, p.y, e.x, e.y) < 200.0:
			near += 1
	if near >= 2 and p.special_cd <= 0.0:
		special = true
	var n2 := PGeom.norm(mx, my)
	return { "mx": n2[0], "my": n2[1], "dodge_press": dodge, "dodge_held": dodge or p.dodge_active, "special": special }
