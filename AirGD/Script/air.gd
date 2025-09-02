extends VehicleBody3D
class_name PravdaSempaiAir

@export_category("HP")
@export var HP: float = 5000.0
@export_category("Настройка самолета")
@export var MAX_STEER_ANGLE: float = 0.6
@export var roll_sensitivity: float = 7.0
@export var yaw_sensitivity: float = 5.0
@export var pitch_sensitivity: float = 12.0
@export var max_engine_power: float = 10000.0
@export var min_engine_power: float = 2000.0
@export var lift_coefficient: float = 2.0
@export var drag_coefficient: float = 0.3
@export var angular_damping: float = 2.0
@export var rotation_speed_limit: float = 5.0
@export var takeoff_speed: float = 30.0
@export var engine_power_change_speed: float = 500.0
@export var ground_drag: float = 5.0
@export var air_drag: float = 0.5
@export var max_speed: float = 300.0
@export var stall_speed: float = 15.0

@export_category("Звук двигателя")
@export var engine_sound: AudioStreamPlayer3D
@export var min_volume: float = -20.0
@export var max_volume: float = 0.0
@export var min_pitch: float = 0.5
@export var max_pitch: float = 1.2
@export var sound_fade_speed: float = 2.0

var target_volume: float = min_volume
var target_pitch: float = min_pitch

@export_category("Закрылки")
@export var rollFlap: Array[Node3D] = []
@export var leftFlapWing: Array[Node3D] = []
@export var rightFlapWing: Array[Node3D] = []

@export_category("AI Настройки")
@export var AI: bool = false
@export var detection_radius: float = 50.0
@export var player_group_name: String = "PlayerTEST"
@export var ignore_player_tag: String = "AI_Only"
@export var waypoints: Array[NodePath] = []
@export var waypoint_reach_distance: float = 100.0
@export var ai_aggressiveness: float = 0.8

var current_engine_power: float = 0.0
var current_waypoint_index: int = 0
var target_player: Node3D = null
var waypoint_nodes: Array[Node3D] = []
var is_on_ground: bool = true

var current_base_angle = 0.0
var current_differential = 0.0
var current_left_aileron_angle = 0.0
var current_right_aileron_angle = 0.0
const FLAP_SPEED: float = 2.0

var current_speed: float = 0.0
var throttle_percentage: float = 0.0

func _ready():
	angular_damp = angular_damping
	for wp_path in waypoints:
		var wp = get_node(wp_path)
		if wp:
			waypoint_nodes.append(wp)
	
	current_engine_power = 0.0
	linear_damp = ground_drag
	
	if engine_sound:
		engine_sound.volume_db = min_volume
		engine_sound.pitch_scale = min_pitch
		engine_sound.play()

func _physics_process(delta):
	check_ground_contact()
	
	current_speed = linear_velocity.length()
	throttle_percentage = (current_engine_power / max_engine_power) * 100.0
	throttle_percentage = clamp(throttle_percentage, 0.0, 100.0)
	
	if AI:
		ai_control(delta)
	else:
		player_control(delta)
	
	apply_aerodynamics(delta)
	limit_rotation_speed()
	limit_speed()
	update_engine_sound(delta)
	
	var thrust = transform.basis.z * current_engine_power
	apply_central_force(thrust)

func player_control(delta):
	if Input.is_action_pressed("Y"):
		current_engine_power = min(current_engine_power + engine_power_change_speed * delta, max_engine_power)
	if Input.is_action_pressed("H"):
		current_engine_power = max(current_engine_power - engine_power_change_speed * delta, 0.0)

	var roll = Input.get_axis("A", "D") * roll_sensitivity
	var yaw = Input.get_axis("E", "Q") * yaw_sensitivity
	var pitch = Input.get_axis("S", "W") * pitch_sensitivity
	
	update_flaps(yaw, pitch, roll, delta)
	var steer_input = Input.get_axis("E", "Q")
	steering = move_toward(steering, steer_input * MAX_STEER_ANGLE, delta * 0.8)
	if is_on_ground:

		if linear_velocity.length() > takeoff_speed and Input.is_action_pressed("W"):
			apply_torque_impulse(transform.basis.x * pitch_sensitivity)
	else:
		if current_engine_power > min_engine_power:
			if Input.is_action_pressed("A") or Input.is_action_pressed("D"):
				apply_torque_impulse(transform.basis.z * roll *3)
			if Input.is_action_pressed("Q") or Input.is_action_pressed("E"):
				apply_torque_impulse(transform.basis.y * yaw*3)
			if Input.is_action_pressed("S") or Input.is_action_pressed("W"):
				apply_torque_impulse(transform.basis.x * pitch*3)
		
		if linear_velocity.length() < stall_speed:
			stabilize_aircraft(delta)

func ai_control(delta):
	if has_node(ignore_player_tag) or is_in_group(ignore_player_tag):
		target_player = null
	if not target_player or not is_instance_valid(target_player):
		find_player()

	current_engine_power = max_engine_power
	
	var target_position: Vector3
	if target_player:
		target_position = target_player.global_transform.origin
	elif waypoint_nodes.size() > 0:
		target_position = waypoint_nodes[current_waypoint_index].global_transform.origin
		if global_transform.origin.distance_to(target_position) < waypoint_reach_distance:
			current_waypoint_index = (current_waypoint_index + 1) % waypoint_nodes.size()
	else:
		target_position = global_transform.origin + global_transform.basis.z * 100.0
	
	var to_target = target_position - global_transform.origin
	var distance_to_target = to_target.length()
	to_target = to_target.normalized()
	
	var local_target = global_transform.basis.inverse() * to_target
	var pitch_angle = atan2(-local_target.y, local_target.z)
	var yaw_angle = atan2(local_target.x, local_target.z)
	var roll_angle = -atan2(local_target.x, local_target.y) * 0.1
	
	var pitch = pitch_angle * pitch_sensitivity * ai_aggressiveness
	var yaw = yaw_angle * yaw_sensitivity * ai_aggressiveness
	var roll = roll_angle * roll_sensitivity * ai_aggressiveness
	
	apply_torque_impulse(transform.basis.x * pitch * delta * 60)
	apply_torque_impulse(transform.basis.y * yaw * delta * 60)
	apply_torque_impulse(transform.basis.z * roll * delta * 60)

func update_flaps(yaw_input: float, pitch_input: float, roll_input: float, delta: float):
	var target_aileron_angle = deg_to_rad(8) * yaw_input
	
	var target_left_aileron = target_aileron_angle
	var target_right_aileron = target_aileron_angle
	
	current_left_aileron_angle = lerp(current_left_aileron_angle, target_left_aileron, FLAP_SPEED * delta)
	current_right_aileron_angle = lerp(current_right_aileron_angle, target_right_aileron, FLAP_SPEED * delta)
	
	if rollFlap.size() >= 2:
		rollFlap[0].rotation.y = current_left_aileron_angle
		rollFlap[1].rotation.y = current_right_aileron_angle
	
	var target_base_angle = deg_to_rad(5) * pitch_input
	var target_differential = deg_to_rad(3) * roll_input
	
	current_base_angle = lerp(current_base_angle, target_base_angle, FLAP_SPEED * delta)
	current_differential = lerp(current_differential, target_differential, FLAP_SPEED * delta)
	
	for flap in leftFlapWing:
		flap.rotation.x = current_base_angle + current_differential
	
	for flap in rightFlapWing:
		flap.rotation.x = current_base_angle - current_differential

func check_ground_contact():
	var ray_length = 2.0
	var space_state = get_world_3d().direct_space_state
	var ray_origin = global_transform.origin
	var ray_end = ray_origin - Vector3.UP * ray_length
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	var result = space_state.intersect_ray(query)
	
	is_on_ground = result.has("collider")
	linear_damp = ground_drag if is_on_ground else air_drag

func apply_aerodynamics(delta):
	var velocity = linear_velocity
	var airspeed = velocity.length()
	var air_direction = velocity.normalized() if airspeed > 0 else Vector3.ZERO

	if airspeed > 0 and not is_on_ground:
		var angle_of_attack = transform.basis.y.angle_to(air_direction)
		var effective_lift = lift_coefficient * cos(angle_of_attack) * airspeed / max_speed
		var lift_dir = -air_direction.cross(transform.basis.x).normalized()
		var lift_magnitude = effective_lift * airspeed * airspeed * delta
		apply_central_force(lift_dir * lift_magnitude)

	var speed_ratio = airspeed / max_speed
	var effective_drag_coefficient = drag_coefficient * (1.0 + speed_ratio * 2.0 + abs(current_differential) * 2.0)
	
	if airspeed > 0:
		var drag = -air_direction * airspeed * airspeed * effective_drag_coefficient * delta
		apply_central_force(drag)

func limit_rotation_speed():
	if angular_velocity.length() > rotation_speed_limit:
		angular_velocity = angular_velocity.normalized() * rotation_speed_limit

func limit_speed():
	var airspeed = linear_velocity.length()
	if airspeed > max_speed:
		var overspeed_ratio = airspeed / max_speed
		var reduction_factor = 1.0 - (overspeed_ratio - 1.0) * 0.1
		linear_velocity = linear_velocity.normalized() * max_speed * reduction_factor

func stabilize_aircraft(delta):
	var stabilization_strength = 1.0 - linear_velocity.length() / stall_speed
	
	var roll_stab = -angular_velocity.z * stabilization_strength * 5.0
	apply_torque_impulse(transform.basis.z * roll_stab * delta * 60)
	
	var pitch_stab = -angular_velocity.x * stabilization_strength * 3.0
	apply_torque_impulse(transform.basis.x * pitch_stab * delta * 60)
	
	if transform.basis.y.dot(Vector3.UP) > 0.5:
		var anti_stall_lift = transform.basis.y * stabilization_strength * lift_coefficient * 100.0 * delta
		apply_central_force(anti_stall_lift)

func find_player():
	if has_node(ignore_player_tag) or is_in_group(ignore_player_tag):
		target_player = null
		return
	
	var players = get_tree().get_nodes_in_group(player_group_name)
	for player in players:
		if is_instance_valid(player) and player is Node3D:
			var distance = global_transform.origin.distance_to(player.global_transform.origin)
			if distance <= detection_radius:
				target_player = player
				return
	target_player = null

func update_engine_sound(delta):
	if not engine_sound:
		return
	
	var normalized_power = (current_engine_power - min_engine_power) / (max_engine_power - min_engine_power)
	normalized_power = clamp(normalized_power, 0.0, 1.0)
	
	var ground_effect = 1.0
	if is_on_ground:
		ground_effect = 0.8
	
	target_volume = lerp(min_volume, max_volume, normalized_power) * ground_effect
	target_pitch = lerp(min_pitch, max_pitch, normalized_power)
	
	engine_sound.volume_db = lerp(engine_sound.volume_db, target_volume, sound_fade_speed * delta)
	engine_sound.pitch_scale = lerp(engine_sound.pitch_scale, target_pitch, sound_fade_speed * delta)
