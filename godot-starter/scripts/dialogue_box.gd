extends CanvasLayer
## Shows lines of text one at a time. Press Enter/Space to go to the next line.
## Use it from any script:
##   get_tree().get_first_node_in_group("dialogue").start(["Line 1", "Line 2"], optional_callback)

@onready var panel: Panel = $Panel
@onready var label: Label = $Panel/Label

var lines: Array = []
var index := 0
var on_done: Callable


func _ready() -> void:
	panel.visible = false


func start(new_lines: Array, done: Callable = Callable()) -> void:
	lines = new_lines
	index = 0
	on_done = done
	Game.in_dialogue = true
	panel.visible = true
	label.text = lines[0]


func _unhandled_input(event: InputEvent) -> void:
	if not panel.visible:
		return
	if event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		index += 1
		if index >= lines.size():
			panel.visible = false
			Game.in_dialogue = false
			if on_done.is_valid():
				on_done.call()
		else:
			label.text = lines[index]
