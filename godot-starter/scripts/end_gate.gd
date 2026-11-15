extends Area2D
## The entrance to the bad guy area. Right now it just shows a message.
## Next step: make a new scene for the bad guy area and load it here with
##   get_tree().change_scene_to_file("res://scenes/your_new_scene.tscn")


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	body.set_deferred("global_position", body.global_position - Vector2(40, 0))
	get_tree().get_first_node_in_group("dialogue").start([
		"* The bad guy area is just ahead...",
		"* (Build it next! Open scripts/end_gate.gd to see how.)",
	])
