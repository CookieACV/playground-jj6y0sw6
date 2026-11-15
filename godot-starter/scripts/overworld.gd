extends Node2D
## The map you walk around on.


func _ready() -> void:
	if Game.enemy_beaten:
		$Enemy.visible = false
	if Game.just_won:
		Game.just_won = false
		await get_tree().process_frame
		$DialogueBox.start([
			"* You and %s beat the %s!" % [Game.ALLY_NAME, Game.ENEMY_NAME],
			"%s: nice teamwork, kid. keep going." % Game.ALLY_NAME,
		])
