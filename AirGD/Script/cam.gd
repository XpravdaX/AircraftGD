extends SpringArm3D
class_name CameraController

@export var mouse_sensitivity: float = 0.005
@export_range(-90.0, 0.0) var min_vertical_angle: float = -60.0
@export_range(0.0, 90.0) var max_vertical_angle: float = 45.0
@export var cam: Camera3D
@export var target_path: NodePath

@export var default_fov: float = 75.0
@export var zoom_fov: float = 40.0
@export var zoom_speed: float = 5.0
@export var height_offset: float = 2.0

var target: Node3D
var is_zooming: bool = false

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	target = get_node(target_path) as Node3D

	top_level = true

	if cam:
		cam.fov = default_fov

func _physics_process(delta):
	if target:
		var target_pos = target.global_position
		target_pos.y += height_offset
		global_position = target_pos

	if cam:
		var target_fov = zoom_fov if is_zooming else default_fov
		cam.fov = lerp(cam.fov, target_fov, zoom_speed * delta)

func _unhandled_input(event: InputEvent):
	if event is InputEventMouseMotion:
		rotation.y -= event.relative.x * mouse_sensitivity
		rotation.y = wrapf(rotation.y, 0.0, TAU)
		
		rotation.x -= event.relative.y * mouse_sensitivity
		rotation.x = deg_to_rad(clamp(rad_to_deg(rotation.x), min_vertical_angle, max_vertical_angle))

	if event.is_action_pressed("zoom"):
		is_zooming = true
	if event.is_action_released("zoom"):
		is_zooming = false
