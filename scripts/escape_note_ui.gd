extends CanvasLayer

var main_node: Node = null
var opened_msec: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func mark_opened() -> void:
	opened_msec = Time.get_ticks_msec()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if Time.get_ticks_msec() - opened_msec < 160:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_E, KEY_TAB, KEY_SPACE]:
			get_viewport().set_input_as_handled()
			if main_node and main_node.has_method("close_escape_note"):
				main_node.close_escape_note()
	elif event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		if main_node and main_node.has_method("close_escape_note"):
			main_node.close_escape_note()
