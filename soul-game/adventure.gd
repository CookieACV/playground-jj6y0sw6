extends Node2D
# =========================================================
#  NOVA'S ADVENTURE
#  Walk: drag on the LEFT side of the screen (or arrow keys)
#  Talk: tap TALK (or press Enter). Some characters want to fight!
#  Battles: tap FIGHT / ACT / ITEM / SPARE, drag to dodge.
# =========================================================

const TILE := 48
const W := 40
const H := 30

var grid: Array = []          # 0 grass, 1 tree, 2 water, 3 path, 4 flower, 5 house
var houses: Array = []
var font: Font
var rng := RandomNumberGenerator.new()

# ---------- player ----------
var player := Vector2.ZERO
var cam := Vector2.ZERO
var max_hp := 20
var hp := 20
var items: Array = [["Starfruit", 12]]

# ---------- touch controls ----------
var joy_index := -1
var joy_origin := Vector2.ZERO
var joy_vec := Vector2.ZERO

# ---------- talking ----------
var state := "walk"     # walk, talk, choice | menu, act, item, fight, dodge, end
var in_battle := false
var lines: Array = []
var line_index := 0
var chars := 0.0
var after_talk := "walk"
var choice_npc := ""

# ---------- characters ----------
var npcs := {
	"pip": {"name": "PIP", "kind": "mushroom", "tile": Vector2(9, 10), "status": "",
		"lines": ["PIP: Hi Nova! Welcome to Glowmoss Village!", "PIP: BOLT lives by the lake. He's SO grumpy.",
			"PIP: Tip: being nice can calm monsters down!"]},
	"mossy": {"name": "MOSSY", "kind": "turtle", "tile": Vector2(18, 10), "status": "",
		"lines": ["MOSSY: Going on an adventure, little star?", "MOSSY: Take my famous Moss Muffin.",
			"* You got a Moss Muffin! (+10 HP)"],
		"after": ["MOSSY: Slow and steady, kiddo. Slow and steady."]},
	"bolt": {"name": "BOLT", "kind": "cloud", "tile": Vector2(29, 13), "status": "",
		"lines": ["BOLT: HEY! This is MY lake!", "BOLT: You wanna fight about it?"],
		"won": ["* Bolt is just a little puff of mist now..."],
		"friend": ["BOLT: Hey friend! Wanna watch me make a rainbow?"]},
	"rocco": {"name": "ROCCO", "kind": "rock", "tile": Vector2(31, 24), "status": "",
		"lines": ["ROCCO: ...", "ROCCO: Rocco guard this path. Nobody pass.", "ROCCO: You fight Rocco?"],
		"won": ["* Rocco is resting. He looks sleepy."],
		"friend": ["ROCCO: Rocco and Nova... friends. Rocco happy."]},
}

# ---------- bosses ----------
var bosses := {
	"bolt": {"hp": 60, "attacks": ["rain", "lightning", "wind"],
		"intro": ["* BOLT crackles with thunder!", "BOLT: Leave now, little star, or get ZAPPED!"],
		"acts": [["Tell a joke", 35, ["* Why did the cloud break up with the fog?", "* \"It needed more SPACE.\"", "BOLT: ...pfft. Terrible. Hehe."]],
			["Compliment", 25, ["* You say his thunder sounds awesome.", "BOLT: R-really? Nobody says that..."]],
			["Offer umbrella", 20, ["* You offer a tiny umbrella.", "BOLT: For ME? ...I'll go easy this turn."]]],
		"win": "BOLT fizzles into mist. The lake is quiet now.",
		"friend": "BOLT smiles. The clouds part and a rainbow appears!"},
	"rocco": {"hp": 80, "attacks": ["rocks", "boulders", "pebbles"],
		"intro": ["* The ground shakes!", "ROCCO: Rocco... SMASH!"],
		"acts": [["Pat his head", 30, ["* You pat Rocco's head. It's warm from the sun.", "ROCCO: ...nice."]],
			["Show a shiny pebble", 35, ["* You show Rocco a shiny pebble.", "ROCCO: OOOH. Shiny!"]],
			["Ask his name", 25, ["* You ask about him.", "ROCCO: Rocco is Rocco. Nobody ask before."]]],
		"win": "ROCCO crumbles into a pile of pebbles... then starts snoring.",
		"friend": "ROCCO gives you a big, gravelly hug."},
}

# ---------- battle state ----------
var boss_id := ""
var boss_hp := 0
var boss_max := 0
var calm := 0
var turn := 0
var easy := 0
var options: Array = []
var bar_t := 0.0
var shake := 0.0
var result := ""
var end_text := ""
var box := Rect2()
var star := Vector2.ZERO
var hurt := 0.0
var bullets: Array = []
var attack := ""
var dodge_time := 0.0
var spawn_timer := 0.0
var side := 1.0
const BUTTONS = ["FIGHT", "ACT", "ITEM", "SPARE"]


func _ready():
	RenderingServer.set_default_clear_color(Color(0.02, 0.02, 0.06))
	font = ThemeDB.fallback_font
	make_world()
	player = Vector2(12.5, 15.5) * TILE
	say(["* Welcome to Glowmoss Village!", "* Drag on the left side to walk. Tap TALK near someone to talk."], "walk")


# ================= WORLD MAP =================

func make_world():
	rng.seed = 7
	grid = []
	for y in H:
		var row = []
		for x in W:
			row.append(1 if x == 0 or y == 0 or x == W - 1 or y == H - 1 else 0)
		grid.append(row)
	for y in H:                                   # lake
		for x in W:
			if pow((x - 31) / 6.0, 2) + pow((y - 7) / 4.0, 2) < 1.0:
				grid[y][x] = 2
	for x in range(2, W - 2):                     # paths
		grid[15][x] = 3
	for y in range(3, H - 2):
		grid[y][12] = 3
	for y in range(15, 26):
		grid[y][31] = 3
	houses = [Rect2i(4, 5, 4, 3), Rect2i(15, 5, 4, 3), Rect2i(4, 19, 4, 3)]
	for hs in houses:
		for y in range(hs.position.y, hs.end.y):
			for x in range(hs.position.x, hs.end.x):
				grid[y][x] = 5
	for i in 260:                                 # trees and flowers
		var x = rng.randi_range(1, W - 2)
		var y = rng.randi_range(1, H - 2)
		if grid[y][x] != 0 or Vector2(x, y).distance_to(Vector2(12, 15)) < 4:
			continue
		var near_npc = false
		for id in npcs:
			if Vector2(x, y).distance_to(npcs[id]["tile"]) < 3:
				near_npc = true
		if near_npc:
			continue
		grid[y][x] = 1 if i % 3 == 0 else 4


func solid(p: Vector2) -> bool:
	var x = int(floor(p.x / TILE))
	var y = int(floor(p.y / TILE))
	if x < 0 or y < 0 or x >= W or y >= H:
		return true
	return grid[y][x] in [1, 2, 5]


func blocked(p: Vector2) -> bool:
	for o in [Vector2(-14, -10), Vector2(14, -10), Vector2(-14, 14), Vector2(14, 14)]:
		if solid(p + o):
			return true
	for id in npcs:
		if p.distance_to(npc_pos(id)) < 34.0:
			return true
	return false


func npc_pos(id) -> Vector2:
	return (npcs[id]["tile"] + Vector2(0.5, 0.5)) * TILE


func nearest_npc() -> String:
	for id in npcs:
		if player.distance_to(npc_pos(id)) < 70.0:
			return id
	return ""


# ================= TALKING =================

func say(new_lines: Array, then: String):
	lines = new_lines
	line_index = 0
	chars = 0.0
	after_talk = then
	state = "talk"


func advance_text():
	if chars < lines[line_index].length():
		chars = lines[line_index].length()
		return
	line_index += 1
	chars = 0.0
	if line_index < lines.size():
		return
	if after_talk.begins_with("ask:"):
		choice_npc = after_talk.substr(4)
		state = "choice"
	elif after_talk == "dodge":
		start_dodge()
	else:
		state = after_talk


func talk_to(id: String):
	var n = npcs[id]
	if id == "mossy":
		if n["status"] == "":
			n["status"] = "given"
			items.append(["Moss Muffin", 10])
			say(n["lines"], "walk")
		else:
			say(n["after"], "walk")
	elif n.has("won") and n["status"] != "":
		say(n[n["status"]], "walk")
	elif n.has("won"):
		say(n["lines"], "ask:" + id)
	else:
		say(n["lines"], "walk")


func pressed_talk():
	match state:
		"walk":
			var id = nearest_npc()
			if id != "":
				talk_to(id)
		"talk":
			advance_text()


# ================= INPUT =================

func _input(event):
	var s = get_viewport_rect().size
	var touch = DisplayServer.is_touchscreen_available()
	if event.is_action_pressed("ui_accept"):
		if state == "choice":
			start_battle(choice_npc)
		elif in_battle:
			on_tap(Vector2(-1, -1))
		else:
			pressed_talk()
		return
	if event.is_action_pressed("ui_cancel") and state == "choice":
		say(["* You walk away."], "walk")
		return
	if in_battle and state == "dodge":
		if event is InputEventScreenDrag:
			star += event.relative
		elif event is InputEventMouseMotion and not touch and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			star += event.relative
		return
	var tap = null
	if event is InputEventScreenTouch:
		if event.pressed:
			if not in_battle and state == "walk" and event.position.x < s.x * 0.5 and not talk_button().has_point(event.position):
				joy_index = event.index
				joy_origin = event.position
				joy_vec = Vector2.ZERO
			else:
				tap = event.position
		elif event.index == joy_index:
			joy_index = -1
			joy_vec = Vector2.ZERO
	elif event is InputEventScreenDrag and event.index == joy_index:
		joy_vec = ((event.position - joy_origin) / 60.0).limit_length(1.0)
	elif not touch and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		tap = event.position
	if tap != null:
		on_tap(tap)


func on_tap(p: Vector2):
	if not in_battle:
		if state == "choice":
			if yes_rect().has_point(p):
				start_battle(choice_npc)
			elif no_rect().has_point(p):
				say(["* You walk away."], "walk")
		elif talk_button().has_point(p) or state == "talk":
			pressed_talk()
		return
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
			leave_battle()


# ================= EVERY FRAME =================

func _process(delta):
	queue_redraw()
	var s = get_viewport_rect().size
	if state == "talk":
		chars += delta * 45.0
	if in_battle:
		battle_process(delta)
		return
	if state == "walk":
		var dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down") + joy_vec
		dir = dir.limit_length(1.0)
		var move = dir * 210.0 * delta
		if not blocked(player + Vector2(move.x, 0)):
			player.x += move.x
		if not blocked(player + Vector2(0, move.y)):
			player.y += move.y
	cam = player - s / 2.0
	cam.x = clamp(cam.x, 0.0, max(W * TILE - s.x, 0.0))
	cam.y = clamp(cam.y, 0.0, max(H * TILE - s.y, 0.0))


# ================= BATTLE =================

func start_battle(id: String):
	in_battle = true
	boss_id = id
	boss_max = bosses[id]["hp"]
	boss_hp = boss_max
	calm = 0
	turn = 0
	easy = 0
	hp = max_hp
	bullets.clear()
	say(bosses[id]["intro"], "menu")


func leave_battle():
	in_battle = false
	bullets.clear()
	if result == "lose":
		player = Vector2(12.5, 15.5) * TILE
		hp = max_hp
		say(["* You wake up back in the village. Try again!"], "walk")
	else:
		npcs[boss_id]["status"] = result
		say(["* " + ("You won!" if result == "won" else "You made a new friend!")], "walk")


func choose(i: int):
	match BUTTONS[i]:
		"FIGHT":
			state = "fight"
			bar_t = 0.0
		"ACT":
			options = []
			for a in bosses[boss_id]["acts"]:
				options.append(a[0])
			options.append("< Back")
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
				result = "friend"
				end_text = bosses[boss_id]["friend"]
				say(["* You offer your hand.", npcs[boss_id]["name"] + ": ...okay. Friends."], "end")
			else:
				say(["* You try to make peace.", npcs[boss_id]["name"] + ": NOT YET!"], "dodge")


func do_act(i: int):
	var acts = bosses[boss_id]["acts"]
	if i >= acts.size():
		state = "menu"
		return
	calm = min(calm + acts[i][1], 100)
	if i == 2 and boss_id == "bolt":
		easy = 1
	say(acts[i][2], "dodge")


func use_item(i: int):
	if i >= items.size():
		state = "menu"
		return
	var it = items[i]
	items.remove_at(i)
	hp = min(hp + it[1], max_hp)
	say(["* You ate the " + it[0] + ". +" + str(it[1]) + " HP!"], "dodge")


func strike():
	var dmg = int(round(14.0 * (1.0 - abs(bar_t - 0.5) * 2.0))) + 2
	if bar_t >= 1.0:
		dmg = 0
	boss_hp = max(boss_hp - dmg, 0)
	shake = 0.5
	if boss_hp <= 0:
		result = "won"
		end_text = bosses[boss_id]["win"]
		say(["* You hit for " + str(dmg) + "!"], "end")
	else:
		say(["* You missed!" if dmg == 0 else "* You hit for " + str(dmg) + " damage!"], "dodge")


func start_dodge():
	state = "dodge"
	dodge_time = 0.0
	spawn_timer = 0.6
	bullets.clear()
	star = box.get_center()
	var list = bosses[boss_id]["attacks"]
	attack = list[turn % list.size()]
	turn += 1


func battle_process(delta):
	var s = get_viewport_rect().size
	box = Rect2(Vector2(s.x / 2.0 - min(s.x * 0.86, 560.0) / 2.0, s.y * 0.36), Vector2(min(s.x * 0.86, 560.0), min(s.y * 0.3, 240.0)))
	shake = max(shake - delta, 0.0)
	hurt = max(hurt - delta, 0.0)
	if state == "fight":
		bar_t += delta / 1.3
		if bar_t >= 1.0:
			bar_t = 1.0
			strike()
	if state != "dodge":
		return
	star += Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down") * 220.0 * delta
	star.x = clamp(star.x, box.position.x + 10.0, box.end.x - 10.0)
	star.y = clamp(star.y, box.position.y + 10.0, box.end.y - 10.0)
	dodge_time += delta
	if dodge_time < 6.3:
		spawn_timer -= delta
		if spawn_timer <= 0.0:
			spawn_attack()
	var keep: Array = []
	for b in bullets:
		b["pos"] += b["vel"] * delta
		if b.has("warn"):
			b["warn"] -= delta
			b["life"] -= delta
			if b["life"] <= 0.0:
				continue
		if box.grow(250.0).has_point(b["pos"]):
			keep.append(b)
	bullets = keep
	if hurt == 0.0:
		for b in bullets:
			if hits_star(b):
				hp -= 3
				hurt = 0.9
				if hp <= 0:
					hp = 0
					result = "lose"
					end_text = "Your light fades... but stars always come back."
					bullets.clear()
					state = "end"
					return
				break
	if dodge_time > 7.0:
		bullets.clear()
		easy = max(easy - 1, 0)
		var line = "* " + npcs[boss_id]["name"] + " is getting ready..."
		if calm >= 100:
			line = "* " + npcs[boss_id]["name"] + " doesn't want to fight anymore. (Try SPARE!)"
		say([line], "menu")


func spawn_attack():
	var slow = 1.6 if easy > 0 else 1.0
	var bx = box
	match attack:
		"rain":
			add_bullet("circle", Vector2(randf_range(bx.position.x - 40, bx.end.x - 10), bx.position.y - 10), Vector2(45, 250) / slow, 5)
			spawn_timer = 0.11 * slow
		"lightning":
			var b = add_bullet("beam", Vector2(randf_range(bx.position.x + 20, bx.end.x - 20), bx.get_center().y), Vector2.ZERO, 0)
			b["size"] = Vector2(30, bx.size.y)
			b["warn"] = 0.75
			b["life"] = 1.15
			spawn_timer = 0.8 * slow
		"wind":
			var gap_y = randf_range(bx.position.y + 45, bx.end.y - 45)
			var x0 = bx.position.x - 20 if side > 0 else bx.end.x + 20
			var top_h = gap_y - 40 - bx.position.y
			var bot_h = bx.end.y - gap_y - 40
			var a = add_bullet("rect", Vector2(x0, bx.position.y + top_h / 2.0), Vector2(200 * side, 0) / slow, 0)
			a["size"] = Vector2(14, top_h)
			var c = add_bullet("rect", Vector2(x0, bx.end.y - bot_h / 2.0), Vector2(200 * side, 0) / slow, 0)
			c["size"] = Vector2(14, bot_h)
			side = -side
			spawn_timer = 1.1 * slow
		"rocks":
			add_bullet("circle", Vector2(randf_range(bx.position.x + 15, bx.end.x - 15), bx.position.y - 20), Vector2(0, randf_range(140, 200)), 14)
			spawn_timer = 0.35
		"boulders":
			var y = randf_range(bx.position.y + 20, bx.end.y - 20)
			var x1 = bx.position.x - 20 if side > 0 else bx.end.x + 20
			add_bullet("circle", Vector2(x1, y), Vector2(190 * side, 0), 18)
			side = -side
			spawn_timer = 0.75
		"pebbles":
			for _i in range(3):
				var p = Vector2(randf_range(bx.position.x, bx.end.x), bx.position.y - 30)
				if randf() < 0.5:
					p = Vector2(bx.position.x - 30 if randf() < 0.5 else bx.end.x + 30, randf_range(bx.position.y, bx.end.y))
				add_bullet("circle", p, (star - p).normalized() * 230.0, 6)
			spawn_timer = 0.7


func add_bullet(type: String, pos: Vector2, vel: Vector2, radius: float) -> Dictionary:
	var b = {"type": type, "pos": pos, "vel": vel, "size": Vector2(radius, radius)}
	bullets.append(b)
	return b


func hits_star(b) -> bool:
	if b.get("warn", 0.0) > 0.0:
		return false
	if b["type"] == "circle":
		return star.distance_to(b["pos"]) < b["size"].x + 6.0
	return Rect2(b["pos"] - b["size"] / 2.0, b["size"]).grow(5.0).has_point(star)


# ================= BUTTON SPOTS =================

func talk_button() -> Rect2:
	var s = get_viewport_rect().size
	return Rect2(s - Vector2(150, 150), Vector2(110, 110))


func dialog_rect() -> Rect2:
	var s = get_viewport_rect().size
	var w = min(s.x - 40.0, 760.0)
	return Rect2(Vector2(s.x / 2.0 - w / 2.0, s.y - 190.0), Vector2(w, 150))


func yes_rect() -> Rect2:
	var d = dialog_rect()
	return Rect2(d.position + Vector2(d.size.x / 2.0 - 190, 80), Vector2(160, 50))


func no_rect() -> Rect2:
	var d = dialog_rect()
	return Rect2(d.position + Vector2(d.size.x / 2.0 + 30, 80), Vector2(160, 50))


func button_rect(i: int) -> Rect2:
	var s = get_viewport_rect().size
	var bw = min(140.0, (box.size.x - 30.0) / 4.0)
	var x = s.x / 2.0 - (bw * 4.0 + 30.0) / 2.0 + i * (bw + 10.0)
	return Rect2(Vector2(x, box.end.y + 64.0), Vector2(bw, 56))


func row_at(p: Vector2) -> int:
	if not box.has_point(p):
		return -1
	return int((p.y - box.position.y - 14.0) / 40.0)


# ================= DRAWING =================

func _draw():
	if in_battle:
		draw_battle()
	else:
		draw_world()


func draw_world():
	var s = get_viewport_rect().size
	var t = Time.get_ticks_msec() / 1000.0
	draw_set_transform(-cam, 0.0, Vector2.ONE)
	var x0 = max(int(cam.x / TILE) - 1, 0)
	var y0 = max(int(cam.y / TILE) - 1, 0)
	var x1 = min(int((cam.x + s.x) / TILE) + 2, W)
	var y1 = min(int((cam.y + s.y) / TILE) + 2, H)
	for y in range(y0, y1):
		for x in range(x0, x1):
			var r = Rect2(x * TILE, y * TILE, TILE, TILE)
			var c = r.get_center()
			var green = Color(0.33, 0.62, 0.3) if (x + y) % 2 == 0 else Color(0.31, 0.59, 0.28)
			match grid[y][x]:
				0, 1, 4, 5:
					draw_rect(r, green)
				2:
					draw_rect(r, Color(0.2, 0.45, 0.85))
					draw_line(c + Vector2(-12, sin(t * 2 + x) * 3), c + Vector2(12, sin(t * 2 + x) * 3), Color(0.6, 0.8, 1.0), 2.0)
				3:
					draw_rect(r, Color(0.82, 0.72, 0.5))
			if grid[y][x] == 4:
				draw_circle(c + Vector2(-8, 4), 4.0, Color(1, 0.85, 0.2) if (x * y) % 2 == 0 else Color(1, 0.5, 0.7))
				draw_circle(c + Vector2(9, -6), 3.0, Color.WHITE)
			elif grid[y][x] == 1:
				draw_rect(Rect2(c + Vector2(-5, 4), Vector2(10, 18)), Color(0.45, 0.3, 0.15))
				draw_circle(c + Vector2(0, -4), 20.0, Color(0.12, 0.4, 0.15))
				draw_circle(c + Vector2(-6, -10), 9.0, Color(0.2, 0.5, 0.2))
	for hs in houses:
		var r = Rect2(hs.position * TILE, hs.size * TILE)
		draw_rect(Rect2(r.position + Vector2(8, 30), r.size - Vector2(16, 30)), Color(0.92, 0.85, 0.7))
		draw_colored_polygon(PackedVector2Array([r.position + Vector2(-4, 40), r.position + Vector2(r.size.x / 2.0, -10), r.position + Vector2(r.size.x + 4, 40)]), Color(0.65, 0.25, 0.2))
		draw_rect(Rect2(r.position + Vector2(r.size.x / 2.0 - 14, r.size.y - 44), Vector2(28, 44)), Color(0.45, 0.28, 0.15))
		draw_rect(Rect2(r.position + Vector2(24, 64), Vector2(30, 26)), Color(0.6, 0.85, 1.0))
	for id in npcs:
		draw_npc(npcs[id]["kind"], npc_pos(id) + Vector2(0, sin(t * 2.0 + npc_pos(id).x) * 2.0), npcs[id]["status"])
		if player.distance_to(npc_pos(id)) < 70.0 and state == "walk":
			draw_string(font, npc_pos(id) + Vector2(-60, -48), npcs[id]["name"], HORIZONTAL_ALIGNMENT_CENTER, 120, 18, Color.WHITE)
	draw_star(player + Vector2(0, sin(t * 6.0) * 2.0), 20.0, Color(1, 0.9, 0.2))
	draw_circle(player + Vector2(-6, -2), 3.0, Color.BLACK)
	draw_circle(player + Vector2(6, -2), 3.0, Color.BLACK)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# controls
	var tb = talk_button()
	var near = nearest_npc() != "" and state == "walk"
	draw_circle(tb.get_center(), 55.0, Color(1, 0.8, 0.2, 0.9 if near else 0.35))
	draw_string(font, tb.position + Vector2(0, 62), "TALK", HORIZONTAL_ALIGNMENT_CENTER, tb.size.x, 24, Color.BLACK)
	if joy_index >= 0:
		draw_circle(joy_origin, 60.0, Color(1, 1, 1, 0.15))
		draw_circle(joy_origin + joy_vec * 60.0, 26.0, Color(1, 1, 1, 0.5))
	draw_string(font, Vector2(16, 30), "HP " + str(hp) + "/" + str(max_hp) + "    Bag: " + str(items.size()) + " items", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)

	if state in ["talk", "choice"]:
		var d = dialog_rect()
		draw_rect(d, Color.BLACK)
		draw_rect(d, Color.WHITE, false, 4.0)
		if state == "talk":
			var text = lines[line_index].substr(0, int(chars))
			draw_multiline_string(font, d.position + Vector2(22, 40), text, HORIZONTAL_ALIGNMENT_LEFT, d.size.x - 44.0, 24, -1, Color.WHITE)
		else:
			draw_string(font, d.position + Vector2(22, 40), "Fight " + npcs[choice_npc]["name"] + "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color.WHITE)
			for pair in [[yes_rect(), "YES"], [no_rect(), "NO"]]:
				draw_rect(pair[0], Color(1, 0.6, 0.1), false, 3.0)
				draw_string(font, pair[0].position + Vector2(0, 34), pair[1], HORIZONTAL_ALIGNMENT_CENTER, pair[0].size.x, 24, Color(1, 0.6, 0.1))


func draw_battle():
	var s = get_viewport_rect().size
	var t = Time.get_ticks_msec() / 1000.0
	var c = Vector2(s.x / 2.0, s.y * 0.17 + sin(t * 1.5) * 6.0)
	if shake > 0.0:
		c += Vector2(randf_range(-6, 6), randf_range(-3, 3))
	draw_npc(npcs[boss_id]["kind"], c, "friend" if calm >= 100 else "", 2.2)
	draw_string(font, Vector2(0, c.y - 80), npcs[boss_id]["name"], HORIZONTAL_ALIGNMENT_CENTER, s.x, 22, Color.WHITE)
	var top = Vector2(s.x / 2.0 - 110.0, s.y * 0.17 + 108.0)
	draw_rect(Rect2(top, Vector2(220, 10)), Color(0.4, 0.05, 0.05))
	draw_rect(Rect2(top, Vector2(220.0 * boss_hp / boss_max, 10)), Color(0.3, 1.0, 0.3))
	draw_rect(Rect2(top + Vector2(0, 16), Vector2(220, 8)), Color(0.15, 0.15, 0.3))
	draw_rect(Rect2(top + Vector2(0, 16), Vector2(220.0 * calm / 100.0, 8)), Color(0.5, 0.8, 1.0))
	draw_string(font, top + Vector2(228, 25), "calm", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.5, 0.8, 1.0))
	draw_rect(box, Color.WHITE, false, 4.0)
	match state:
		"talk":
			draw_multiline_string(font, box.position + Vector2(24, 42), lines[line_index].substr(0, int(chars)), HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 48.0, 24, -1, Color.WHITE)
		"act", "item":
			for i in options.size():
				var y = box.position.y + 14.0 + i * 40.0
				draw_star(Vector2(box.position.x + 20, y + 20), 7.0, Color(1, 0.9, 0.3))
				draw_string(font, Vector2(box.position.x + 40, y + 28), options[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color.WHITE)
		"fight":
			var bar = Rect2(box.position + Vector2(20, box.size.y / 2.0 - 30), Vector2(box.size.x - 40, 60))
			draw_rect(bar, Color(0.15, 0.15, 0.2))
			draw_rect(Rect2(Vector2(bar.get_center().x - 40, bar.position.y), Vector2(80, 60)), Color(0.2, 0.5, 0.2))
			draw_rect(Rect2(Vector2(bar.get_center().x - 10, bar.position.y), Vector2(20, 60)), Color(0.4, 1.0, 0.4))
			draw_rect(Rect2(Vector2(bar.position.x + bar.size.x * bar_t - 4, bar.position.y - 8), Vector2(8, 76)), Color.WHITE)
			draw_string(font, Vector2(0, box.end.y - 18), "TAP when the line is in the middle!", HORIZONTAL_ALIGNMENT_CENTER, s.x, 18, Color(1, 1, 0.5))
		"dodge":
			for b in bullets:
				var r = Rect2(b["pos"] - b["size"] / 2.0, b["size"])
				if b["type"] == "circle":
					draw_circle(b["pos"], b["size"].x, Color(0.6, 0.8, 1.0) if boss_id == "bolt" else Color(0.65, 0.6, 0.55))
				elif b["type"] == "beam":
					if b["warn"] > 0.0:
						draw_rect(r, Color(1, 1, 0.3, 0.25))
						draw_rect(r, Color(1, 1, 0.3), false, 2.0)
					else:
						draw_rect(r, Color(1, 1, 0.75))
				else:
					draw_rect(r, Color(0.85, 0.95, 1.0))
			if hurt == 0.0 or int(hurt * 12.0) % 2 == 0:
				draw_star(star, 11.0, Color(1, 0.9, 0.2))
		"end":
			var title = {"won": "VICTORY", "friend": "FRIENDSHIP!", "lose": "GAME OVER"}[result]
			draw_string(font, box.position + Vector2(0, 60), title, HORIZONTAL_ALIGNMENT_CENTER, box.size.x, 40, Color(1, 0.9, 0.3))
			draw_multiline_string(font, box.position + Vector2(24, 110), end_text, HORIZONTAL_ALIGNMENT_CENTER, box.size.x - 48.0, 20, -1, Color.WHITE)
			draw_string(font, Vector2(0, box.end.y - 16), "tap to continue", HORIZONTAL_ALIGNMENT_CENTER, s.x, 18, Color(0.7, 0.7, 0.7))
	var hp_pos = Vector2(box.position.x, box.end.y + 30.0)
	draw_string(font, hp_pos, "NOVA   HP", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)
	draw_rect(Rect2(hp_pos + Vector2(130, -17), Vector2(160, 20)), Color(0.6, 0.05, 0.05))
	draw_rect(Rect2(hp_pos + Vector2(130, -17), Vector2(160.0 * hp / max_hp, 20)), Color(1, 0.85, 0.2))
	draw_string(font, hp_pos + Vector2(300, 0), str(hp) + " / " + str(max_hp), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)
	for i in BUTTONS.size():
		var r = button_rect(i)
		var col = Color(1, 0.6, 0.1) if state == "menu" else Color(0.4, 0.3, 0.2)
		if BUTTONS[i] == "SPARE" and calm >= 100 and state == "menu":
			col = Color(1, 1, 0.3)
		draw_rect(r, col, false, 3.0)
		draw_string(font, Vector2(r.position.x, r.position.y + 37), BUTTONS[i], HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 22, col)


# Draws a character. k = size (1 in the world, bigger in battles)
func draw_npc(kind: String, c: Vector2, status: String, k := 1.0):
	var happy = status == "friend"
	match kind:
		"mushroom":
			draw_rect(Rect2(c + Vector2(-9, -2) * k, Vector2(18, 20) * k), Color(0.98, 0.92, 0.8))
			draw_circle(c + Vector2(0, -6) * k, 17.0 * k, Color(0.9, 0.2, 0.2))
			draw_circle(c + Vector2(-7, -12) * k, 3.5 * k, Color.WHITE)
			draw_circle(c + Vector2(7, -9) * k, 3.0 * k, Color.WHITE)
			draw_circle(c + Vector2(-4, 6) * k, 2.0 * k, Color.BLACK)
			draw_circle(c + Vector2(4, 6) * k, 2.0 * k, Color.BLACK)
		"turtle":
			draw_circle(c + Vector2(16, -2) * k, 7.0 * k, Color(0.55, 0.75, 0.4))
			draw_circle(c, 17.0 * k, Color(0.25, 0.5, 0.25))
			draw_circle(c, 9.0 * k, Color(0.4, 0.62, 0.3))
			draw_circle(c + Vector2(18, -4) * k, 1.8 * k, Color.BLACK)
		"cloud":
			var grey = Color(0.75, 0.78, 0.85) if happy or status == "won" else Color(0.5, 0.53, 0.6)
			if not happy and status != "won":
				draw_colored_polygon(PackedVector2Array([c + Vector2(-3, 12) * k, c + Vector2(6, 12) * k, c + Vector2(1, 22) * k,
					c + Vector2(7, 22) * k, c + Vector2(-6, 38) * k, c + Vector2(-2, 26) * k, c + Vector2(-8, 26) * k]), Color(1, 0.9, 0.2))
			for puff in [[Vector2(-18, 3), 13.0], [Vector2(0, -6), 18.0], [Vector2(18, 3), 13.0], [Vector2(-8, 8), 13.0], [Vector2(8, 8), 13.0]]:
				draw_circle(c + puff[0] * k, puff[1] * k, grey)
			draw_face(c, k, happy)
		"rock":
			var pts = PackedVector2Array()
			for i in range(8):
				var a = i * TAU / 8.0
				pts.append(c + Vector2(cos(a) * 20.0, sin(a) * 17.0 + (2.0 if i % 2 == 0 else 0.0)) * k)
			draw_colored_polygon(pts, Color(0.55, 0.52, 0.48))
			draw_circle(c + Vector2(-8, 8) * k, 3.0 * k, Color(0.45, 0.42, 0.4))
			draw_face(c, k, happy)


func draw_face(c: Vector2, k: float, happy: bool):
	for sd in [-1.0, 1.0]:
		var e = c + Vector2(7 * sd, -2) * k
		draw_circle(e, 3.8 * k, Color.WHITE)
		draw_circle(e + Vector2(0, 1) * k, 2.0 * k, Color.BLACK)
		if not happy:
			draw_line(e + Vector2(-4 * sd, -6) * k, e + Vector2(4 * sd, -3) * k, Color.BLACK, 1.5 * k)
	if happy:
		draw_arc(c + Vector2(0, 5) * k, 5.0 * k, 0.2, PI - 0.2, 8, Color.BLACK, 1.2 * k)
	else:
		draw_line(c + Vector2(-5, 8) * k, c + Vector2(5, 7) * k, Color.BLACK, 1.2 * k)


func draw_star(p: Vector2, r: float, color: Color):
	var pts = PackedVector2Array()
	for i in range(10):
		var radius = r if i % 2 == 0 else r * 0.45
		var a = -PI / 2.0 + i * PI / 5.0
		pts.append(p + Vector2(cos(a), sin(a)) * radius)
	draw_colored_polygon(pts, color)
