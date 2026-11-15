class_name pickable
extends RigidBody3D

var picked = false
var dropped = false
@onready var col: CollisionShape3D = $col


func _process(_delta):
	if picked:
		freeze = true
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		gravity_scale = 0.0
		col.disabled = true
	else:
		if freeze:
			freeze = false
		gravity_scale = 1.0
	if dropped:
		dropped = false
		freeze = false
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		col.disabled = false


func _on_player_handpos(handpos) -> void:
	if picked:
		global_transform = handpos
