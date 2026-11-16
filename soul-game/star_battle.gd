extends Node2D
# =========================================================
#  STAR BATTLE  -  you are NOVA, a little star spirit.
#  Boss: BOLT, a grumpy thundercloud.
#  Tap buttons to choose. In dodge turns, drag your finger
#  to move your star. Beat Bolt... or make friends with him!
# =========================================================

# ---------- things you can easily change ----------
var hero_name := "NOVA"
var boss_name := "BOLT"
var max_hp := 20
var boss_max_hp := 60
var items = [["Moon Cookie", 8], ["Starfruit", 12], ["Cloud Candy", 5]]

# ---------- game state ----------
var state := "talk"          # talk, menu, act, item, fight, dodge, end
var hp := 20
var boss_hp := 60
var calm := 0                # reach 100 and you can SPARE Bolt
var turn := 0
var easy_turns := 0
var lines: Array = []
var line_index := 0
var chars := 0.0
var after_talk := "menu"
var options: Array = []
var bar_t := 0.0
var shake := 0.0
var end_title := ""
var end_text := ""

var box := Rect2()
var star := Vector2.ZERO
var hurt_timer := 0.0
var bullets: Array = []
var attack := 0
var dodge_time := 0.0
var spawn_timer := 0.0
var wall_side := 1.0
var font: Font

const BUTTONS = ["FIGHT", "ACT", "ITEM", "SPARE"]
const ACTS = ["Check", "Tell a joke", "Compliment", "Offer an umbrella", "< Back"]


func _ready():
	RenderingServer.set_default_clear_color(Color(0.02, 0.02, 0.06))
	font = ThemeDB.fallback_font
	restart()


func restart():
	hp = max_hp
	boss_hp = boss_max_hp
	calm = 0
	turn = 0
	easy_turns = 0
	items = [["Moon Cookie", 8], ["Starfruit", 12], ["Cloud Candy", 5]]
	bullets.clear()
	say(["* A grumpy thundercloud blocks your path!",
		boss_name + ": Who said you could fly under MY sky?",
		boss_name + ": Leave now, little star, or get ZAPPED!"], "menu")


# ================= TEXT =================

func say(new_lines: Array, then: String):
	lines = new_lines
	line_index = 0
	chars = 0.0
	after_talk = then
	state = "talk"


func advance_text():
	var full = lines[line_index]
	if chars < full.length():
		chars = full.length()          # tap once to show the whole line
		return
	line_index += 1
	chars = 0.0
	if line_index >= lines.size():
		match after_talk:
			"menu":
				state = "menu"
			"dodge":
				start_dodge()
			_:
				state = "end"


# ================= INPUT =================

func _input(event):
	var touch = DisplayServer.is_touchscreen_available()
	if state == "dodge":
		if event is InputEventScreenDrag:
			star += event.relative
		elif event is InputEventMouseMotion and not touch and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			star += event.relative
		return
	var tap = null
	if touch and event is InputEventScreenTouch and event.pressed:
		tap = event.position
	elif not touch and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		tap = event.position
	elif event.is_action_pressed("ui_accept"):
		tap = Vector2(-1, -1)
	if tap != null:
		on_tap(tap)


func on_tap(p: Vector2):
	match state:
		"talk":
			advance_text()
		"menu":
			for i in BUTTONS.size():
				if button_rect(i).has_point(p):
					choose(i)
		"act", "item":
			var i = row_at(p)
			if i >= 0 and i < options.size():
				if state == "act":
					do_act(i)
				else:
					use_item(i)
		"fight":
			strike()
		"end":
			restart()


func choose(i: int):
	match BUTTONS[i]:
		"FIGHT":
			state = "fight"
			bar_t = 0.0
		"ACT":
			options = ACTS
			state = "act"
		"ITEM":
			if items.is_empty():
				say(["* Your bag is empty!"], "menu")
				return
			options = []
			for it in items:
				options.append(it[0] + "  (+" + str(it[1]) + " HP)")
			options.append("< Back")
			state = "item"
		"SPARE":
			if calm >= 100:
				end_title = "FRIENDSHIP ENDING"
				end_text = boss_name + " smiles. The clouds part and the sky turns gold.\n" + boss_name + ": ...Want to fly together?"
				say(["* You offer " + boss_name + " your hand.", boss_name + ": I... I don't want to fight anymore."], "end")
			else:
				say(["* You try to make peace.", boss_name + ": HA! Not a chance!"], "dodge")


func do_act(i: int):
	match i:
		0:
			say(["* " + boss_name + "  ATK 3  HP " + str(boss_hp) + "/" + str(boss_max_hp),
				"* Calm: " + str(calm) + "%. He seems lonely up there."], "dodge")
		1:
			calm = min(calm + 35, 100)
			say(["* You ask: why did the cloud break up with the fog?",
				"* \"It needed more SPACE.\"", boss_name + ": ...pfft. That's terrible. Hehe."], "dodge")
		2:
			calm = min(calm + 25, 100)
			say(["* You tell " + boss_name + " his thunder sounds awesome.", boss_name + ": R-really? Nobody ever says that..."], "dodge")
		3:
			calm = min(calm + 20, 100)
			easy_turns = 1
			say(["* You offer " + boss_name + " a tiny umbrella.", boss_name + ": For ME? ...I'll go easy on you this turn."], "dodge")
		_:
			state = "menu"


func use_item(i: int):
	if i >= items.size():
		state = "menu"
		return
	var it = items[i]
	items.remove_at(i)
	hp = min(hp + it[1], max_hp)
	say(["* You ate the " + it[0] + ". +" + str(it[1]) + " HP!"], "dodge")


# ================= FIGHT (timing bar) =================

func strike():
	var accuracy = 1.0 - abs(bar_t - 0.5) * 2.0       # 1.0 = perfect middle
	var dmg = int(round(14.0 * accuracy)) + 2
	if bar_t >= 1.0:
		dmg = 0
	boss_hp = max(boss_hp - dmg, 0)
	shake = 0.5
	if boss_hp <= 0:
		end_title = "VICTORY"
		end_text = boss_name + " fizzles into a little puff of mist.\nThe sky is quiet now... maybe too quiet."
		say(["* You hit " + boss_name + " for " + str(dmg) + "!", boss_name + ": N-no... my storm..."], "end")
	elif dmg == 0:
		say(["* You missed!"], "dodge")
	else:
		say(["* You hit " + boss_name + " for " + str(dmg) + " damage!"], "dodge")


# ================= DODGE TURN =================

func start_dodge():
	state = "dodge"
	dodge_time = 0.0
	spawn_timer = 0.6
	bullets.clear()
	star = box.get_center()
	attack = turn % 3
	turn += 1


func end_dodge():
	bullets.clear()
	if easy_turns > 0:
		easy_turns -= 1
	var flavor = ["* " + boss_name + " rumbles angrily.", "* It smells like rain.", "* " + boss_name + " is charging up..."]
	var line = flavor[turn % flavor.size()]
	if calm >= 100:
		line = "* " + boss_name + " doesn't want to fight anymore. (Try SPARE!)"
	say([line], "menu")


func spawn_attack():
	var slow = 1.6 if easy_turns > 0 else 1.0
	match attack:
		0:  # RAIN
			var x = randf_range(box.position.x - 40.0, box.end.x - 10.0)
			add_bullet("circle", Vector2(x, box.position.y - 10.0), Vector2(45, 250) / slow, Vector2(5, 5))
			spawn_timer = 0.11 * slow
		1:  # LIGHTNING: warns first, then strikes
			var x = randf_range(box.position.x + 20.0, box.end.x - 20.0)
			var b = add_bullet("beam", Vector2(x, box.get_center().y), Vector2.ZERO, Vector2(30, box.size.y))
			b["warn"] = 0.75
			b["life"] = 1.15
			spawn_timer = 0.8 * slow
		2:  # WIND WALLS with a gap
			var gap = 80.0
			var gap_y = randf_range(box.position.y + 45.0, box.end.y - 45.0)
			var start_x = box.position.x - 20.0 if wall_side > 0.0 else box.end.x + 20.0
			var top_h = gap_y - gap / 2.0 - box.position.y
			var bottom_h = box.end.y - (gap_y + gap / 2.0)
			var vel = Vector2(200.0 * wall_side, 0) / slow
			add_bullet("rect", Vector2(start_x, box.position.y + top_h / 2.0), vel, Vector2(14, top_h))
			add_bullet("rect", Vector2(start_x, box.end.y - bottom_h / 2.0), vel, Vector2(14, bottom_h))
			wall_side = -wall_side
			spawn_timer = 1.1 * slow


func add_bullet(type: String, pos: Vector2, vel: Vector2, size: Vector2) -> Dictionary:
	var b = {"type": type, "pos": pos, "vel": vel, "size": size}
	bullets.append(b)
	return b


func hits_star(b) -> bool:
	if b.get("warn", 0.0) > 0.0:
		return false
	if b["type"] == "circle":
		return star.distance_to(b["pos"]) < b["size"].x + 6.0
	var r = Rect2(b["pos"] - b["size"] / 2.0, b["size"])
	return r.grow(5.0).has_point(star)


# ================= EVERY FRAME =================

func _process(delta):
	layout()
	queue_redraw()
	shake = max(shake - delta, 0.0)
	hurt_timer = max(hurt_timer - delta, 0.0)
	match state:
		"talk":
			chars += delta * 45.0
		"fight":
			bar_t += delta / 1.3
			if bar_t >= 1.0:
				bar_t = 1.0
				strike()
		"dodge":
			update_dodge(delta)


func update_dodge(delta):
	var dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	star += dir * 220.0 * delta
	star.x = clamp(star.x, box.position.x + 10.0, box.end.x - 10.0)
	star.y = clamp(star.y, box.position.y + 10.0, box.end.y - 10.0)
	dodge_time += delta
	if dodge_time < 6.3:
		spawn_timer -= delta
		if spawn_timer <= 0.0:
			spawn_attack()
	var keep: Array = []
	var area = box.grow(250.0)
	for b in bullets:
		b["pos"] += b["vel"] * delta
		if b.has("warn"):
			b["warn"] -= delta
			b["life"] -= delta
			if b["life"] <= 0.0:
				continue
		if area.has_point(b["pos"]):
			keep.append(b)
	bullets = keep
	if hurt_timer == 0.0:
		for b in bullets:
			if hits_star(b):
				hp -= 3
				hurt_timer = 0.9
				if hp <= 0:
					hp = 0
					bullets.clear()
					end_title = "GAME OVER"
					end_text = "Your light fades... but stars always come back."
					state = "end"
					return
				break
	if dodge_time > 7.0:
		end_dodge()


# ================= LAYOUT =================

func layout():
	var s = get_viewport_rect().size
	var w = min(s.x * 0.86, 560.0)
	var h = min(s.y * 0.3, 240.0)
	box = Rect2(Vector2(s.x / 2.0 - w / 2.0, s.y * 0.36), Vector2(w, h))


func button_rect(i: int) -> Rect2:
	var s = get_viewport_rect().size
	var bw = min(140.0, (box.size.x - 30.0) / 4.0)
	var total = bw * 4.0 + 30.0
	var x = s.x / 2.0 - total / 2.0 + i * (bw + 10.0)
	return Rect2(Vector2(x, box.end.y + 64.0), Vector2(bw, 56))


func row_at(p: Vector2) -> int:
	if not box.has_point(p):
		return -1
	return int((p.y - box.position.y - 14.0) / 40.0)


# ================= DRAWING =================

func _draw():
	var s = get_viewport_rect().size
	var t = Time.get_ticks_msec() / 1000.0
	draw_boss(Vector2(s.x / 2.0, s.y * 0.17 + sin(t * 1.5) * 6.0), t)

	# boss HP and calm meter
	var top = Vector2(s.x / 2.0 - 110.0, s.y * 0.17 + 108.0)
	draw_rect(Rect2(top, Vector2(220, 10)), Color(0.4, 0.05, 0.05))
	draw_rect(Rect2(top, Vector2(220.0 * boss_hp / boss_max_hp, 10)), Color(0.3, 1.0, 0.3))
	draw_rect(Rect2(top + Vector2(0, 16), Vector2(220, 8)), Color(0.15, 0.15, 0.3))
	draw_rect(Rect2(top + Vector2(0, 16), Vector2(220.0 * calm / 100.0, 8)), Color(0.5, 0.8, 1.0))
	draw_string(font, top + Vector2(228, 25), "calm", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.5, 0.8, 1.0))

	draw_rect(box, Color.WHITE, false, 4.0)

	match state:
		"talk":
			var full = lines[line_index]
			var shown = full.substr(0, int(chars))
			draw_multiline_string(font, box.position + Vector2(24, 42), shown, HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 48.0, 24, -1, Color.WHITE)
			if chars >= full.length():
				draw_string(font, box.end - Vector2(80, 14), "tap >", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 0.5))
		"act", "item":
			for i in options.size():
				var y = box.position.y + 14.0 + i * 40.0
				draw_string(font, Vector2(box.position.x + 40, y + 28), options[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color.WHITE)
				draw_star(Vector2(box.position.x + 20, y + 20), 7.0, Color(1, 0.9, 0.3))
		"fight":
			var bar = Rect2(box.position + Vector2(20, box.size.y / 2.0 - 30), Vector2(box.size.x - 40, 60))
			draw_rect(bar, Color(0.15, 0.15, 0.2))
			draw_rect(Rect2(Vector2(bar.get_center().x - 40, bar.position.y), Vector2(80, 60)), Color(0.2, 0.5, 0.2))
			draw_rect(Rect2(Vector2(bar.get_center().x - 10, bar.position.y), Vector2(20, 60)), Color(0.4, 1.0, 0.4))
			var mx = bar.position.x + bar.size.x * bar_t
			draw_rect(Rect2(Vector2(mx - 4, bar.position.y - 8), Vector2(8, 76)), Color.WHITE)
			draw_string(font, Vector2(0, box.end.y - 18), "TAP when the line is in the middle!", HORIZONTAL_ALIGNMENT_CENTER, s.x, 18, Color(1, 1, 0.5))
		"dodge":
			for b in bullets:
				if b["type"] == "circle":
					draw_circle(b["pos"], b["size"].x, Color(0.6, 0.8, 1.0))
				elif b["type"] == "beam":
					var r = Rect2(b["pos"] - b["size"] / 2.0, b["size"])
					if b["warn"] > 0.0:
						draw_rect(r, Color(1, 1, 0.3, 0.25))
						draw_rect(r, Color(1, 1, 0.3), false, 2.0)
					else:
						draw_rect(r, Color(1, 1, 0.75))
				else:
					draw_rect(Rect2(b["pos"] - b["size"] / 2.0, b["size"]), Color(0.85, 0.95, 1.0))
			if hurt_timer == 0.0 or int(hurt_timer * 12.0) % 2 == 0:
				draw_star(star, 11.0, Color(1, 0.9, 0.2))
		"end":
			draw_string(font, box.position + Vector2(0, 60), end_title, HORIZONTAL_ALIGNMENT_CENTER, box.size.x, 40, Color(1, 0.9, 0.3))
			draw_multiline_string(font, box.position + Vector2(24, 110), end_text, HORIZONTAL_ALIGNMENT_CENTER, box.size.x - 48.0, 20, -1, Color.WHITE)
			draw_string(font, Vector2(0, box.end.y - 16), "tap to play again", HORIZONTAL_ALIGNMENT_CENTER, s.x, 18, Color(0.7, 0.7, 0.7))

	# your HP
	var hp_pos = Vector2(box.position.x, box.end.y + 30.0)
	draw_string(font, hp_pos, hero_name + "   HP", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)
	var bar_bg = Rect2(hp_pos + Vector2(130, -17), Vector2(160, 20))
	draw_rect(bar_bg, Color(0.6, 0.05, 0.05))
	draw_rect(Rect2(bar_bg.position, Vector2(160.0 * hp / max_hp, 20)), Color(1, 0.85, 0.2))
	draw_string(font, hp_pos + Vector2(300, 0), str(hp) + " / " + str(max_hp), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)

	# menu buttons
	for i in BUTTONS.size():
		var r = button_rect(i)
		var active = state == "menu"
		var col = Color(1, 0.6, 0.1) if active else Color(0.4, 0.3, 0.2)
		if BUTTONS[i] == "SPARE" and calm >= 100 and active:
			col = Color(1, 1, 0.3)
		draw_rect(r, col, false, 3.0)
		draw_string(font, Vector2(r.position.x, r.position.y + 37), BUTTONS[i], HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 22, col)


func draw_boss(c: Vector2, _t: float):
	if shake > 0.0:
		c += Vector2(randf_range(-6, 6), randf_range(-3, 3))
	var happy = calm >= 100
	var grey = Color(0.75, 0.78, 0.85) if happy else Color(0.5, 0.53, 0.6)
	# lightning bolt tail
	var bolt = PackedVector2Array([c + Vector2(-8, 30), c + Vector2(14, 30), c + Vector2(2, 58),
		c + Vector2(16, 58), c + Vector2(-14, 100), c + Vector2(-4, 66), c + Vector2(-18, 66)])
	if not happy:
		draw_colored_polygon(bolt, Color(1, 0.9, 0.2))
	# fluffy cloud body
	for puff in [[Vector2(-48, 8), 34.0], [Vector2(0, -16), 46.0], [Vector2(48, 8), 34.0], [Vector2(-20, 20), 34.0], [Vector2(22, 20), 34.0]]:
		draw_circle(c + puff[0], puff[1], grey)
	# eyes
	for side in [-1.0, 1.0]:
		var e = c + Vector2(18 * side, -4)
		draw_circle(e, 10.0, Color.WHITE)
		draw_circle(e + Vector2(0, 2), 5.0, Color.BLACK)
		if happy:
			draw_arc(e + Vector2(0, -10), 9.0, PI * 1.15, PI * 1.85, 8, Color.BLACK, 3.0)
		else:
			draw_line(e + Vector2(-11 * side, -16), e + Vector2(9 * side, -8), Color.BLACK, 4.0)   # angry brows
	# mouth
	if happy:
		draw_arc(c + Vector2(0, 14), 12.0, 0.2, PI - 0.2, 10, Color.BLACK, 3.0)
	else:
		draw_line(c + Vector2(-12, 22), c + Vector2(12, 18), Color.BLACK, 3.0)
	draw_string(font, Vector2(c.x - 100, c.y - 72), boss_name, HORIZONTAL_ALIGNMENT_CENTER, 200, 22, Color.WHITE)


func draw_star(p: Vector2, r: float, color: Color):
	var pts = PackedVector2Array()
	for i in range(10):
		var radius = r if i % 2 == 0 else r * 0.45
		var a = -PI / 2.0 + i * PI / 5.0
		pts.append(p + Vector2(cos(a), sin(a)) * radius)
	draw_colored_polygon(pts, color)
