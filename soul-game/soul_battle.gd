extends Node2D
# SOUL BATTLE - step 1
# Drag your finger to move the heart. Dodge everything!
# (Arrow keys work too if you have a keyboard.)

var boss_name := "YOUR BOSS"     # <- change this to your character's name!

var box := Rect2()
var heart := Vector2.ZERO
var hp := 20
var max_hp := 20
var hurt_timer := 0.0
var bullets: Array = []
var attack := 0
var attack_time := 0.0
var spawn_timer := 0.0
var wall_side := 1.0
var survived := 0.0
var game_over := false
var font: Font

var attack_names = ["STAR RAIN", "WALL SLIDE", "AIMED SHOTS"]


func _ready():
	RenderingServer.set_default_clear_color(Color.BLACK)
	font = ThemeDB.fallback_font
	layout()
	heart = box.get_center()


# Works out where the box goes, based on the screen size
func layout():
	var s = get_viewport_rect().size
	var w = min(s.x * 0.8, 460.0)
	var h = min(s.y * 0.35, 300.0)
	box = Rect2(Vector2(s.x / 2.0 - w / 2.0, s.y * 0.42), Vector2(w, h))


func _input(event):
	if game_over:
		var tapped = (event is InputEventScreenTouch and event.pressed) \
			or (event is InputEventMouseButton and event.pressed)
		if tapped:
			restart()
		return
	# Finger drag moves the heart (on a touchscreen)
	if event is InputEventScreenDrag:
		heart += event.relative
	# Mouse drag moves it on a computer
	elif event is InputEventMouseMotion and not DisplayServer.is_touchscreen_available():
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			heart += event.relative


func restart():
	hp = max_hp
	bullets.clear()
	attack = 0
	attack_time = 0.0
	survived = 0.0
	hurt_timer = 0.0
	game_over = false
	heart = box.get_center()


func _process(delta):
	layout()
	queue_redraw()
	if game_over:
		return
	survived += delta

	# keyboard movement (optional)
	var dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	heart += dir * 220.0 * delta
	heart.x = clamp(heart.x, box.position.x + 9.0, box.end.x - 9.0)
	heart.y = clamp(heart.y, box.position.y + 9.0, box.end.y - 9.0)

	# switch attack every 8 seconds
	attack_time += delta
	if attack_time > 8.0:
		attack_time = 0.0
		attack = (attack + 1) % attack_names.size()
		spawn_timer = 1.0

	spawn_timer -= delta
	if spawn_timer <= 0.0:
		spawn_attack()

	# move bullets, remove the ones that left the area
	var keep: Array = []
	var area = box.grow(250.0)
	for b in bullets:
		b["pos"] += b["vel"] * delta
		if area.has_point(b["pos"]):
			keep.append(b)
	bullets = keep

	# did anything hit the heart?
	hurt_timer = max(hurt_timer - delta, 0.0)
	if hurt_timer == 0.0:
		for b in bullets:
			if hits_heart(b):
				hp -= 3
				hurt_timer = 1.0
				if hp <= 0:
					hp = 0
					game_over = true
				break


func hits_heart(b) -> bool:
	if b["type"] == "circle":
		return heart.distance_to(b["pos"]) < b["size"].x + 6.0
	var r = Rect2(b["pos"] - b["size"] / 2.0, b["size"])
	return r.grow(6.0).has_point(heart)


func add_bullet(type: String, pos: Vector2, vel: Vector2, size: Vector2):
	bullets.append({"type": type, "pos": pos, "vel": vel, "size": size})


func spawn_attack():
	match attack:
		0:  # STAR RAIN: stars fall from the top
			var x = randf_range(box.position.x + 10.0, box.end.x - 10.0)
			add_bullet("circle", Vector2(x, box.position.y - 10.0), Vector2(0, randf_range(170.0, 260.0)), Vector2(7, 7))
			spawn_timer = 0.22
		1:  # WALL SLIDE: a wall with a gap slides across
			var gap = 70.0
			var gap_y = randf_range(box.position.y + 40.0, box.end.y - 40.0)
			var start_x = box.position.x - 20.0 if wall_side > 0.0 else box.end.x + 20.0
			var top_h = gap_y - gap / 2.0 - box.position.y
			var bottom_h = box.end.y - (gap_y + gap / 2.0)
			var vel = Vector2(210.0 * wall_side, 0)
			add_bullet("rect", Vector2(start_x, box.position.y + top_h / 2.0), vel, Vector2(16, top_h))
			add_bullet("rect", Vector2(start_x, box.end.y - bottom_h / 2.0), vel, Vector2(16, bottom_h))
			wall_side = -wall_side
			spawn_timer = 1.1
		2:  # AIMED SHOTS: shots from the edges, aimed at you
			for _i in range(3):
				var edge = box.grow(30.0)
				var p = Vector2(randf_range(edge.position.x, edge.end.x), edge.position.y)
				if randf() < 0.5:
					p = Vector2(edge.position.x if randf() < 0.5 else edge.end.x, randf_range(edge.position.y, edge.end.y))
				add_bullet("circle", p, (heart - p).normalized() * 230.0, Vector2(6, 6))
			spawn_timer = 0.7


func _draw():
	var s = get_viewport_rect().size
	var t = Time.get_ticks_msec() / 1000.0

	# the boss (a placeholder: we will draw your real character later)
	var boss = Vector2(s.x / 2.0, s.y * 0.2 + sin(t * 2.0) * 6.0)
	draw_circle(boss, 55.0, Color(0.92, 0.92, 0.96))
	draw_circle(boss + Vector2(-18, -8), 9.0, Color.BLACK)
	draw_circle(boss + Vector2(18, -8), 9.0, Color.BLACK)
	draw_line(boss + Vector2(-20, 22), boss + Vector2(20, 22), Color.BLACK, 4.0)
	draw_string(font, Vector2(0, s.y * 0.2 + 85.0), boss_name, HORIZONTAL_ALIGNMENT_CENTER, s.x, 26, Color.WHITE)

	# attack name
	draw_string(font, Vector2(0, box.position.y - 14.0), attack_names[attack], HORIZONTAL_ALIGNMENT_CENTER, s.x, 22, Color(1, 1, 0.4))

	# the box
	draw_rect(box, Color.WHITE, false, 4.0)

	# bullets
	for b in bullets:
		if b["type"] == "circle":
			draw_circle(b["pos"], b["size"].x, Color.WHITE)
		else:
			draw_rect(Rect2(b["pos"] - b["size"] / 2.0, b["size"]), Color.WHITE)

	# the heart (flashes after you get hit)
	if hurt_timer == 0.0 or int(hurt_timer * 12.0) % 2 == 0:
		draw_heart(heart, Color(1, 0.1, 0.15))

	# HP bar
	var bar = Rect2(Vector2(box.position.x, box.end.y + 24.0), Vector2(200, 22))
	draw_string(font, bar.position + Vector2(0, 18), "HP", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)
	var bar_bg = Rect2(bar.position + Vector2(40, 0), bar.size)
	draw_rect(bar_bg, Color(0.7, 0.05, 0.05))
	draw_rect(Rect2(bar_bg.position, Vector2(bar.size.x * hp / max_hp, bar.size.y)), Color(1, 0.9, 0.1))
	draw_string(font, bar_bg.position + Vector2(bar.size.x + 12, 18), str(hp) + " / " + str(max_hp), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)
	draw_string(font, Vector2(box.position.x, box.end.y + 76), "Time: " + str(int(survived)) + "s", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)

	if game_over:
		draw_string(font, Vector2(0, s.y * 0.5), "GAME OVER", HORIZONTAL_ALIGNMENT_CENTER, s.x, 56, Color(1, 0.2, 0.2))
		draw_string(font, Vector2(0, s.y * 0.5 + 50), "You lasted " + str(int(survived)) + " seconds. Tap to try again", HORIZONTAL_ALIGNMENT_CENTER, s.x, 24, Color.WHITE)


func draw_heart(p: Vector2, color: Color):
	draw_circle(p + Vector2(-5, -3), 5.5, color)
	draw_circle(p + Vector2(5, -3), 5.5, color)
	draw_colored_polygon(PackedVector2Array([p + Vector2(-10.5, -1), p + Vector2(10.5, -1), p + Vector2(0, 11)]), color)
