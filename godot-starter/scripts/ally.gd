extends Node2D
## The friend you meet. Walk up and press Enter/Space to talk; after that they follow you.

## How far behind the player the ally walks (bigger = further back).
@export var follow_gap := 16

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
var player: Node2D


func _ready() -> void:
	player = get_tree().get_first_node_in_group("player")
	if Game.ally_joined:
		global_position = player.global_position + Vector2(-40, 0)


func _process(delta: float) -> void:
	if Game.ally_joined:
		_follow(delta)
	else:
		sprite.play("idle")


func _unhandled_input(event: InputEvent) -> void:
	if Game.ally_joined or Game.in_dialogue:
		return
	if event.is_action_pressed("ui_accept") and global_position.distance_to(player.global_position) < 60:
		get_viewport().set_input_as_handled()
		var dialogue = get_tree().get_first_node_in_group("dialogue")
		dialogue.start([
			"%s: hey. where are you headed, kid?" % Game.ALLY_NAME,
			"%s: To the bad guy area. I have to stop them." % Game.HERO_NAME,
			"%s: alone? nah. that's a bad idea." % Game.ALLY_NAME,
			"%s: i'll come with you. let's do this together." % Game.ALLY_NAME,
			"* %s joined the team!" % Game.ALLY_NAME,
		], _on_joined)


func _on_joined() -> void:
	Game.ally_joined = true
	player.trail.clear()


func _follow(delta: float) -> void:
	var trail: Array[Vector2] = player.trail
	if trail.is_empty():
		sprite.play("idle")
		return
	var target: Vector2 = trail[min(follow_gap, trail.size() - 1)]
	var old_pos := global_position
	global_position = global_position.lerp(target, min(1.0, 10.0 * delta))
	var moved := global_position - old_pos
	if moved.length() > 0.3:
		sprite.play("walk")
		if absf(moved.x) > 0.1:
			sprite.flip_h = moved.x < 0
	else:
		sprite.play("idle")
