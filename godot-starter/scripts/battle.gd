extends Node2D
## Team-up battle.
##  1. Pick a move for the hero (FIGHT / ACT / ITEM)
##  2. Pick a move for the ally (FIGHT / HEAL)
##  3. Dodge the enemy's attack: move the red square with the arrow keys!
## Win by bringing the enemy's HP to 0, or by using ACT until mercy hits 100%.

enum State { HERO_MENU, ALLY_MENU, MESSAGE, DODGE, WON, LOST }

const HERO_OPTIONS := ["FIGHT", "ACT", "ITEM"]
const ALLY_OPTIONS := ["FIGHT", "HEAL"]
const TEXT_BOX := Rect2(30, 230, 580, 150)
const DODGE_BOX := Rect2(220, 230, 200, 150)
const DODGE_TIME := 5.0
const HEART_SPEED := 150.0

var enemy_max_hp := 40
var enemy_hp := 40
var mercy := 0

var state := State.HERO_MENU
var choice := 0
var hero_action := ""

var messages: Array = []
var after_messages: Callable

# Dodge phase
var heart := Vector2.ZERO
var bullets: Array = []   # each bullet is {"pos": Vector2, "vel": Vector2}
var dodge_timer := 0.0
var spawn_timer := 0.0
var hurt_timer := 0.0

var enemy_sprite: Sprite2D
var text_label: Label
var menu_label: Label
var stats_label: Label


func _ready() -> void:
	enemy_sprite = Sprite2D.new()
	enemy_sprite.texture = load("res://assets/enemy.png")
	enemy_sprite.position = Vector2(320, 110)
	enemy_sprite.scale = Vector2(4, 4)
	add_child(enemy_sprite)

	text_label = _make_label(Vector2(50, 245), Vector2(540, 120), 20)
	stats_label = _make_label(Vector2(30, 392), Vector2(580, 30), 16)
	menu_label = _make_label(Vector2(30, 425), Vector2(580, 40), 22)

	_show_messages(["* The %s blocks the way!" % Game.ENEMY_NAME], _go_to_hero_menu)


func _make_label(pos: Vector2, size: Vector2, font_size: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.size = size
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", font_size)
	add_child(l)
	return l


func _process(delta: float) -> void:
	match state:
		State.HERO_MENU, State.ALLY_MENU:
			_menu_input()
		State.MESSAGE:
			if Input.is_action_just_pressed("ui_accept"):
				_next_message()
		State.DODGE:
			_update_dodge(delta)
		State.WON, State.LOST:
			if Input.is_action_just_pressed("ui_accept"):
				_leave_battle()
	queue_redraw()


# ---------------- Menus ----------------

func _menu_input() -> void:
	var options: Array = HERO_OPTIONS if state == State.HERO_MENU else ALLY_OPTIONS
	if Input.is_action_just_pressed("ui_right"):
		choice = (choice + 1) % options.size()
	elif Input.is_action_just_pressed("ui_left"):
		choice = (choice - 1 + options.size()) % options.size()
	elif Input.is_action_just_pressed("ui_cancel") and state == State.ALLY_MENU:
		_go_to_hero_menu()   # go back and change the hero's move
	elif Input.is_action_just_pressed("ui_accept"):
		if state == State.HERO_MENU:
			hero_action = options[choice]
			if Game.ally_hp > 0:
				state = State.ALLY_MENU
				choice = 0
			else:
				_do_turn(hero_action, "")
		else:
			_do_turn(hero_action, options[choice])
	_update_ui()


func _go_to_hero_menu() -> void:
	state = State.HERO_MENU
	choice = 0
	_update_ui()


func _update_ui() -> void:
	stats_label.text = "%s HP %d/%d    %s HP %d/%d    ITEMS %d    %s HP %d/%d" % [
		Game.HERO_NAME, Game.hero_hp, Game.hero_max_hp,
		Game.ALLY_NAME, Game.ally_hp, Game.ally_max_hp,
		Game.items, Game.ENEMY_NAME, enemy_hp, enemy_max_hp]

	text_label.visible = state != State.DODGE
	match state:
		State.HERO_MENU:
			text_label.text = "* What will %s do?" % Game.HERO_NAME
			menu_label.text = _menu_text(HERO_OPTIONS)
		State.ALLY_MENU:
			text_label.text = "* What will %s do?\n  (Esc = go back)" % Game.ALLY_NAME
			menu_label.text = _menu_text(ALLY_OPTIONS)
		State.DODGE:
			menu_label.text = "DODGE! (arrow keys)"
		_:
			menu_label.text = "(Enter)"


func _menu_text(options: Array) -> String:
	var parts: Array[String] = []
	for i in options.size():
		parts.append(("> " if i == choice else "  ") + options[i])
	return "     ".join(parts)


# ---------------- Turn logic ----------------

func _do_turn(hero_move: String, ally_move: String) -> void:
	var msgs: Array = []

	match hero_move:
		"FIGHT":
			var dmg := randi_range(6, 10)
			enemy_hp -= dmg
			msgs.append("* %s attacks! %d damage!" % [Game.HERO_NAME, dmg])
		"ACT":
			mercy = min(mercy + 35, 100)
			msgs.append("* %s tells the %s to stand down.\n  (Mercy: %d%%)" % [Game.HERO_NAME, Game.ENEMY_NAME, mercy])
		"ITEM":
			if Game.items > 0:
				Game.items -= 1
				Game.hero_hp = min(Game.hero_hp + 10, Game.hero_max_hp)
				msgs.append("* %s eats a snack. Recovered 10 HP!" % Game.HERO_NAME)
			else:
				msgs.append("* No items left!")

	match ally_move:
		"FIGHT":
			var dmg := randi_range(4, 8)
			enemy_hp -= dmg
			msgs.append("* %s attacks too! %d damage!" % [Game.ALLY_NAME, dmg])
		"HEAL":
			Game.hero_hp = min(Game.hero_hp + 6, Game.hero_max_hp)
			msgs.append("* %s heals %s. +6 HP!" % [Game.ALLY_NAME, Game.HERO_NAME])

	if enemy_hp <= 0:
		enemy_hp = 0
		msgs.append("* The %s was defeated!" % Game.ENEMY_NAME)
		_show_messages(msgs, _win)
	elif mercy >= 100:
		msgs.append("* The %s gives up and walks away." % Game.ENEMY_NAME)
		_show_messages(msgs, _win)
	else:
		msgs.append("* The %s attacks! Get ready to dodge!" % Game.ENEMY_NAME)
		_show_messages(msgs, _start_dodge)


func _show_messages(msgs: Array, then: Callable) -> void:
	messages = msgs.duplicate()
	after_messages = then
	state = State.MESSAGE
	_update_ui()
	text_label.text = messages.pop_front()


func _next_message() -> void:
	if messages.is_empty():
		after_messages.call()
	else:
		text_label.text = messages.pop_front()


func _win() -> void:
	state = State.WON
	Game.enemy_beaten = true
	Game.just_won = true
	enemy_sprite.visible = false
	_update_ui()
	text_label.text = "* YOU WON!\n* Press Enter to continue."


func _lose() -> void:
	state = State.LOST
	_update_ui()
	text_label.text = "* %s fell...\n* Press Enter to try again." % Game.HERO_NAME


func _leave_battle() -> void:
	if state == State.LOST:
		Game.heal_party()
	get_tree().change_scene_to_file("res://scenes/overworld.tscn")


# ---------------- Dodge phase ----------------

func _start_dodge() -> void:
	state = State.DODGE
	heart = DODGE_BOX.get_center()
	bullets.clear()
	dodge_timer = DODGE_TIME
	spawn_timer = 0.0
	hurt_timer = 0.0
	_update_ui()


func _update_dodge(delta: float) -> void:
	# Move the heart, but keep it inside the box.
	var dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	heart += dir * HEART_SPEED * delta
	heart.x = clamp(heart.x, DODGE_BOX.position.x + 8, DODGE_BOX.end.x - 8)
	heart.y = clamp(heart.y, DODGE_BOX.position.y + 8, DODGE_BOX.end.y - 8)

	# Spawn falling bullets.
	spawn_timer -= delta
	if spawn_timer <= 0:
		spawn_timer = 0.3
		var x := randf_range(DODGE_BOX.position.x + 6, DODGE_BOX.end.x - 6)
		bullets.append({
			"pos": Vector2(x, DODGE_BOX.position.y + 4),
			"vel": Vector2(randf_range(-25, 25), randf_range(90, 160)),
		})

	for b in bullets:
		b["pos"] += b["vel"] * delta
	bullets = bullets.filter(func(b): return b["pos"].y < DODGE_BOX.end.y - 2)

	# Getting hit hurts the hero or the ally (random), then a short invincibility.
	hurt_timer -= delta
	if hurt_timer <= 0:
		for b in bullets:
			if b["pos"].distance_to(heart) < 10:
				_take_hit()
				break

	if Game.hero_hp <= 0:
		_lose()
		return

	dodge_timer -= delta
	if dodge_timer <= 0:
		bullets.clear()
		_go_to_hero_menu()


func _take_hit() -> void:
	hurt_timer = 0.8
	var dmg := 3
	if Game.ally_hp > 0 and randf() < 0.5:
		Game.ally_hp = max(Game.ally_hp - dmg, 0)
	else:
		Game.hero_hp = max(Game.hero_hp - dmg, 0)
	_update_ui()


# ---------------- Drawing ----------------

func _draw() -> void:
	draw_rect(Rect2(0, 0, 640, 480), Color.BLACK)
	if state == State.DODGE:
		draw_rect(DODGE_BOX, Color.WHITE, false, 4.0)
		var blink := hurt_timer > 0 and fmod(hurt_timer, 0.2) < 0.1
		draw_rect(Rect2(heart - Vector2(7, 7), Vector2(14, 14)), Color(1, 0, 0, 0.3) if blink else Color.RED)
		for b in bullets:
			draw_circle(b["pos"], 5.0, Color.WHITE)
	else:
		draw_rect(TEXT_BOX, Color.WHITE, false, 4.0)
