extends CanvasLayer
class_name PravdaSempaiCrosshair

@export var crosshair_texture: TextureRect
@export var distance_label: Label
@export var gun: Node3D
@export var max_distance: float = 1000.0
@export var lerp_speed: float = 10.0
@export var camera_controller: Node3D

var final_crosshair_pos: Vector2

func _process(delta: float) -> void:
	if !gun || !crosshair_texture:
		gun = get_tree().get_first_node_in_group("gun")
		if !gun:
			return
	
	var camera = get_viewport().get_camera_3d()
	if !camera:
		return

	var space_state = get_viewport().get_world_3d().direct_space_state
	
	var query = PhysicsRayQueryParameters3D.create(
		gun.global_transform.origin,
		gun.global_transform.origin + gun.global_transform.basis.z * max_distance
	)
	var collision = space_state.intersect_ray(query)
	
	var target_position: Vector3
	if collision:
		target_position = collision.position
		if distance_label:
			var dist = gun.global_transform.origin.distance_to(target_position)
			distance_label.text = "%dм" % dist
	else:
		target_position = gun.global_transform.origin + gun.global_transform.basis.z * max_distance
		if distance_label:
			distance_label.text = "%dм+" % max_distance

	var gun_forward = gun.global_transform.basis.z
	var camera_forward = -camera.global_transform.basis.z
	var angle = rad_to_deg(gun_forward.angle_to(camera_forward))
	
	crosshair_texture.visible = angle <= camera.fov
	
	if crosshair_texture.visible:
		var screen_pos = camera.unproject_position(target_position)
		final_crosshair_pos = final_crosshair_pos.lerp(
			screen_pos - (crosshair_texture.size / 2),
			delta * lerp_speed
		)
		
		crosshair_texture.position = final_crosshair_pos
