extends SceneTree
## 한글 글꼴 연결 시험(headless). 실행: python tools/run_suites.py --suites font_tests --jobs 1
##
## 이 시험은 "화면이 예쁜가"를 보지 않는다. **글꼴이 실제로 붙어 있는가**만 단언한다.
## 눈으로 보는 확인은 docs/WEB_BUILD.md §9·§10(브라우저 확인 기록)과 docs/captures/에 따로 있다.
##
## 확인하는 것
##  A. 글꼴 파일이 프로젝트 안에 실제로 있다(assets/fonts/ui.ttf)와 가져오기 표식(.import)이 함께 있다.
##     .import이 없으면 내보내기에 들어가지 않는다 — 이것이 "웹에서 네모(□)"의 원인이었다.
##  B. 그 파일이 Font로 열리고, 현대 한글 음절 11,172자와 화면이 쓰는 기호가 전부 들어 있다.
##  C. 기본 테마에 연결됐다: project.godot의 gui/theme/custom_font, ThemeDB 기본 테마의 default_font,
##     ThemeDB.fallback_font 셋이 모두 이 글꼴을 가리킨다(세 곳 중 하나만 빠져도 화면 일부가 네모로 남는다).
##  D. 두 내보내기(웹·윈도우)가 이 파일을 담는다: export_filter가 all_resources이고 제외 목록이 assets를 건드리지 않는다.
##  E. 라이선스가 함께 나간다: assets/fonts/OFL.txt가 있고 OFL 1.1 전문이며, 고지 문구가 게임 화면(설정·제목)에 있다.
##  F. 글꼴에 없는 기호를 화면 글자에 다시 쓰지 않았다(docs/WEB_BUILD.md §2에서 바꿔 둔 ▸ ▾ ☠ 등).

const FONT_PATH := "res://assets/fonts/ui.ttf"
const IMPORT_PATH := "res://assets/fonts/ui.ttf.import"
const LICENSE_PATH := "res://assets/fonts/OFL.txt"
const PRESETS_PATH := "res://export_presets.cfg"

## 글꼴에 없어서 화면 글자에 쓰면 안 되는 기호(Noto Sans KR에 없다. WEB_BUILD.md §2에서 이미 바꿔 두었다)
const BANNED := ["▸", "▾", "☠", "⛔", "↳"]

## 화면이 실제로 쓰는 비-한글 기호. 하나라도 빠지면 그 자리가 네모가 된다.
const SYMBOLS := "§°±·×÷π—•…←→↔−√≈≠≤≥∈⊕①②③④⑤⑥⑦⑧⑨⑩⑪⑫ⓐⓑⓒ■□▶▼○●★〃"

var results := []

func ok(name: String, cond: bool, extra: String = "") -> void:
	results.append([cond, name, extra])
	print(("PASS " if cond else "FAIL ") + name + ((" — " + extra) if extra != "" else ""))

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	# ---------- A. 파일이 있는가 ----------
	var has_font := FileAccess.file_exists(FONT_PATH)
	ok("글꼴 파일이 프로젝트에 있다(%s)" % FONT_PATH, has_font)
	ok("가져오기 표식(.import)이 있다 — 없으면 내보내기에 담기지 않는다", FileAccess.file_exists(IMPORT_PATH))
	ok("엔진이 자원으로 인식한다(ResourceLoader.exists)", ResourceLoader.exists(FONT_PATH))
	var size_b := 0
	if has_font:
		var fh := FileAccess.open(FONT_PATH, FileAccess.READ)
		if fh != null:
			size_b = int(fh.get_length())
	ok("글꼴 파일이 비어 있지 않다", size_b > 100000, "%d바이트" % size_b)

	# ---------- B. 글꼴에 한글이 들어 있는가 ----------
	var res: Resource = load(FONT_PATH) if has_font else null
	var font: Font = res as Font
	ok("Font 자원으로 열린다(%s)" % ("null" if res == null else res.get_class()), font != null)
	if font == null:
		_finish()
		return

	# 현대 한글 음절 전체(U+AC00~U+D7A3). 한 자라도 빠지면 그 글자만 네모로 나온다.
	var miss_hangul := 0
	var first_missing := ""
	for cp in range(0xAC00, 0xD7A4):
		if not font.has_char(cp):
			miss_hangul += 1
			if first_missing == "":
				first_missing = char(cp)
	ok("현대 한글 음절 11,172자가 모두 있다", miss_hangul == 0, "빠진 글자 %d자%s" % [miss_hangul, (" (처음: %s)" % first_missing) if first_missing != "" else ""])

	var miss_ascii := []
	for cp in range(0x20, 0x7F):
		if not font.has_char(cp):
			miss_ascii.append(char(cp))
	ok("ASCII 글자가 모두 있다", miss_ascii.is_empty(), str(miss_ascii))

	var miss_sym := []
	for i in SYMBOLS.length():
		if not font.has_char(SYMBOLS.unicode_at(i)):
			miss_sym.append(SYMBOLS[i])
	ok("화면이 쓰는 기호 %d종이 모두 있다" % SYMBOLS.length(), miss_sym.is_empty(), str(miss_sym))

	# 실제로 글자가 그려지는지(자리만 있고 윤곽이 없으면 폭이 0이 된다)
	var w := font.get_string_size("예언의 시간표", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 24).x
	ok("한글 문자열의 그려지는 폭이 0보다 크다", w > 10.0, "폭 %.1f" % w)

	# ---------- C. 기본 테마에 연결됐는가 ----------
	var setting := String(ProjectSettings.get_setting("gui/theme/custom_font", ""))
	ok("project.godot의 gui/theme/custom_font가 이 글꼴을 가리킨다", setting == FONT_PATH, "값=%s" % setting)
	var theme_font: Font = ThemeDB.get_default_theme().default_font
	ok("기본 테마의 default_font가 붙어 있다(Label·Button·RichTextLabel이 읽는 곳)", theme_font != null and theme_font.get_rid() == font.get_rid(),
		"현재=%s" % ("null" if theme_font == null else theme_font.get_class()))
	var fb: Font = ThemeDB.fallback_font
	ok("ThemeDB.fallback_font가 붙어 있다(PRender.font()·터치 조작이 읽는 곳)", fb != null and fb.get_rid() == font.get_rid(),
		"현재=%s" % ("null" if fb == null else fb.get_class()))
	# 직접 그리는 경로가 실제로 같은 글꼴을 돌려주는지(간접 확인이 아니라 그 함수를 부른다)
	var render_font: Font = PRender.font()
	ok("PRender.font()가 같은 글꼴을 돌려준다", render_font != null and render_font.get_rid() == font.get_rid())

	# ---------- D. 두 내보내기에 담기는가 ----------
	var presets := _read_presets()
	for pname in ["Web", "Windows Desktop"]:
		var p: Dictionary = presets.get(pname, {})
		ok("내보내기 프리셋 '%s'이(가) 있다" % pname, not p.is_empty())
		if p.is_empty():
			continue
		ok("'%s'이(가) 모든 자원을 담는다(export_filter=all_resources)" % pname, String(p.get("export_filter", "")) == "all_resources", String(p.get("export_filter", "")))
		var excl := String(p.get("exclude_filter", ""))
		ok("'%s'의 제외 목록이 글꼴을 걸러내지 않는다" % pname, not _excluded(excl, "assets/fonts/ui.ttf"), "제외=%s" % excl)
		# .txt는 all_resources가 담지 않는다(실제 pck를 뜯어 확인했다). 포함 목록에 따로 적어야 나간다.
		var incl := String(p.get("include_filter", ""))
		ok("'%s'의 포함 목록이 라이선스 전문(.txt)을 담는다" % pname,
			_matches(incl, "assets/fonts/OFL.txt") and not _excluded(excl, "assets/fonts/OFL.txt"), "포함=%s / 제외=%s" % [incl, excl])

	# ---------- E. 라이선스와 고지 ----------
	var lic := ""
	if FileAccess.file_exists(LICENSE_PATH):
		var lf := FileAccess.open(LICENSE_PATH, FileAccess.READ)
		if lf != null:
			lic = lf.get_as_text()
	ok("라이선스 전문이 내보내기에 담기는 자리에 있다(%s)" % LICENSE_PATH, lic != "")
	ok("전문이 SIL OFL 1.1이다", lic.contains("SIL OPEN FONT LICENSE Version 1.1") and lic.contains("PERMISSION & CONDITIONS"))
	ok("전문에 저작권자 표시가 있다", lic.contains("Adobe"))
	ok("전문에 이 사본이 부분집합(수정본)이라는 사실이 적혀 있다", lic.to_lower().contains("modified version"))

	var notice := PUi.font_notice()
	ok("고지 문구가 비어 있지 않다", notice != "", notice)
	ok("고지 문구에 글꼴 이름·저작권자·라이선스가 함께 적혀 있다",
		notice.contains("Noto Sans KR") and notice.contains("Adobe") and notice.contains("Open Font License"), notice)
	ok("제목 화면용 짧은 고지에도 글꼴 이름과 라이선스가 있다",
		PUi.font_notice_short().contains("Noto Sans KR") and PUi.font_notice_short().contains("OFL"), PUi.font_notice_short())
	ok("PUi.font_license_path()가 실제 파일을 가리킨다", FileAccess.file_exists(PUi.font_license_path()))

	# 설정 화면을 실제로 만들어 고지가 화면 글자로 들어갔는지 본다
	var panel := PSettingsPanel.new()
	root.add_child(panel)
	await process_frame
	var seen := _texts_of(panel)
	ok("설정 화면에 고지 문구가 실제로 들어간다", seen.contains("Noto Sans KR") and seen.contains("OFL"))
	ok("설정 화면이 라이선스 전문 경로도 알려 준다", seen.contains(LICENSE_PATH))
	root.remove_child(panel)
	panel.free()   # quit() 전에 확실히 지운다(queue_free는 다음 프레임이라 종료와 겹친다)

	# 제목 화면은 main 없이 만들 수 없으므로 원본에서 고지를 부르는지 확인한다
	var title_src := _read("res://scripts/game/screens/title.gd")
	ok("제목 화면이 고지 한 줄을 그린다", title_src.contains("font_notice_short()"))

	# ---------- F. 글꼴에 없는 기호를 화면 글자에 쓰지 않았다 ----------
	var display := _display_text()
	var used_banned := []
	for b in BANNED:
		if display.contains(b):
			used_banned.append(b)
	ok("글꼴에 없는 기호를 화면 글자에 쓰지 않았다(%s)" % " ".join(BANNED), used_banned.is_empty(), str(used_banned))
	var missing_disp := {}
	for i in display.length():
		var cp := display.unicode_at(i)
		if cp < 0x80:
			continue
		if not font.has_char(cp):
			missing_disp[char(cp)] = true
	ok("화면 글자에 쓰인 모든 문자가 글꼴에 있다", missing_disp.is_empty(), str(missing_disp.keys()))

	_finish()

func _finish() -> void:
	var pass_n := 0
	for r in results:
		if r[0]:
			pass_n += 1
	print("%d/%d PASS" % [pass_n, results.size()])
	quit(0 if pass_n == results.size() else 1)

# ---------- 도우미 ----------

static func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return "" if f == null else f.get_as_text()

## export_presets.cfg를 프리셋 이름 → 값 사전으로 읽는다(옵션 절 [preset.N.options]는 건너뛴다)
func _read_presets() -> Dictionary:
	var out := {}
	var cur := {}
	var in_preset := false
	for raw in _read(PRESETS_PATH).split("\n"):
		var line := raw.strip_edges()
		if line.begins_with("["):
			if in_preset and cur.has("name"):
				out[String(cur["name"])] = cur.duplicate()
			cur = {}
			in_preset = line.begins_with("[preset.") and not line.ends_with(".options]")
			continue
		if not in_preset or not line.contains("="):
			continue
		var k := line.substr(0, line.find("=")).strip_edges()
		var v := line.substr(line.find("=") + 1).strip_edges()
		if v.begins_with("\"") and v.ends_with("\"") and v.length() >= 2:
			v = v.substr(1, v.length() - 2)
		cur[k] = v
	if in_preset and cur.has("name"):
		out[String(cur["name"])] = cur.duplicate()
	return out

## 쉼표로 이어진 규칙 목록(tests/*,tools/*,docs/*)이 이 경로에 걸리는가.
## 엔진과 같은 방식이다 — res:// 를 뗀 경로에 glob을 맞춘다.
static func _matches(filters: String, path: String) -> bool:
	for f in filters.split(",", false):
		var pat := f.strip_edges()
		if pat != "" and path.match(pat):
			return true
	return false

static func _excluded(filters: String, path: String) -> bool:
	return _matches(filters, path)

## 만들어진 Control 나무에서 눈에 보이는 글자를 모은다
func _texts_of(n: Node) -> String:
	var s := ""
	if n is RichTextLabel:
		s += (n as RichTextLabel).text + "\n"
	elif n is Label:
		s += (n as Label).text + "\n"
	elif n is Button:
		s += (n as Button).text + "\n"
	for c in n.get_children():
		s += _texts_of(c)
	return s

## 화면에 나올 수 있는 글자만 모은다: .gd는 문자열 리터럴만(주석은 화면에 나오지 않는다), 자료 파일은 전부.
func _display_text() -> String:
	var re := RegEx.new()
	re.compile("\"(?:[^\"\\\\\\n]|\\\\.)*\"")
	var out := PackedStringArray()
	for path in _walk("res://scripts") + _walk("res://scenes") + _walk("res://data"):
		var txt := _read(path)
		if txt == "":
			continue
		if path.ends_with(".gd"):
			for m in re.search_all(txt):
				out.append(m.get_string())
		else:
			out.append(txt)
	return "\n".join(out)

## 폴더 아래 .gd·.tscn·.json 경로 목록
func _walk(dir: String) -> Array:
	var out := []
	for d in DirAccess.get_directories_at(dir):
		out += _walk(dir + "/" + d)
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd") or f.ends_with(".tscn") or f.ends_with(".json"):
			out.append(dir + "/" + f)
	return out
