extends Area2D
## Invisible line in front of the enemy. Walking into it starts the battle
## (but only once your ally has joined you).


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player") or Game.enemy_beaten:
		return

	if not Game.ally_joined:
		body.set_deferred("global_position", body.global_position - Vector2(60, 0))
		get_tree().get_first_node_in_group("dialogue").start([
			"* It's too dangerous to go alone...",
			"* Maybe someone back there can help you.",
		])
		return

	Game.player_return_pos = body.global_position - Vector2(80, 0)
	Game.has_return_pos = true
	get_tree().change_scene_to_file.call_deferred("res://scenes/battle.tscn")
