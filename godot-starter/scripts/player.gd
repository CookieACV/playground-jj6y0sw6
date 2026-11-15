extends CharacterBody2D
## The character you control. Arrow keys to move, Enter/Space to talk.

@export var speed := 160.0

## Positions the player walked through, newest first. The ally follows this trail.
var trail: Array[Vector2] = []
const TRAIL_MAX := 60

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	if Game.has_return_pos:
		global_position = Game.player_return_pos


func _physics_process(_delta: float) -> void:
	var dir := Vector2.ZERO
	if not Game.in_dialogue:
		dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")

	velocity = dir * speed
	move_and_slide()

	if dir != Vector2.ZERO:
		sprite.play("walk")
		if dir.x != 0:
			sprite.flip_h = dir.x < 0
		trail.push_front(global_position)
		if trail.size() > TRAIL_MAX:
			trail.pop_back()
	else:
		sprite.play("idle")
