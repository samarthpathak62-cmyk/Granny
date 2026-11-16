extends StaticBody3D

var monster_key = false
var wooden_hammer = false
var final = false


func _ready():
	pass


func _process(_delta):
	if monster_key and wooden_hammer and final:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		get_tree().change_scene_to_file("res://scenes/game_over.tscn")


func _on_need_monster_key_monster_done(_is_done):
	monster_key = true


func _on_wood_hammer_beaten(_is_done):
	wooden_hammer = true


func _on_openz_all_locks_all_done(_is_done):
	if monster_key and wooden_hammer:
		final = true
	else:
		var player = get_tree().get_first_node_in_group("player")
		if player and player.has_method("_show_hint"):
			var missing: PackedStringArray = PackedStringArray()
			if not wooden_hammer:
				missing.append("Hammer (Plank)")
			if not monster_key:
				missing.append("Master Key")
			player._show_hint("MAIN DOOR LOCKED! Needs: %s" % " + ".join(missing), 2.8)
