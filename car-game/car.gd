extends VehicleBody3D

@export var max_engine_force := 1500.0
@export var max_brake := 20.0
@export var max_steer := 0.35

var start_transform: Transform3D


func _ready():
	can_sleep = false
	start_transform = global_transform
	# Put the car's weight low so it doesn't flip
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, -0.5, 0)
	# Springs + stronger shock absorbers (less bouncy)
	for wheel in get_children():
		if wheel is VehicleWheel3D:
			wheel.suspension_stiffness = 40.0
			wheel.wheel_rest_length = 0.3
			wheel.suspension_travel = 0.3
			wheel.damping_compression = 3.0
			wheel.damping_relaxation = 4.0
			wheel.wheel_friction_slip = 3.0
			add_wheel_look(wheel)
	add_car_look()


func _physics_process(delta):
	# Fell off the map, or pressed R? Go back to the start.
	if global_position.y < -10 or Input.is_key_pressed(KEY_R):
		reset_car()
		return

	var throttle = Input.get_axis("ui_down", "ui_up")
	var turn = Input.get_axis("ui_right", "ui_left")

	engine_force = throttle * max_engine_force
	steering = move_toward(steering, turn * max_steer, delta * 2.5)

	if Input.is_action_pressed("ui_accept"):
		brake = max_brake
	else:
		brake = 0.0


func reset_car():
	global_transform = start_transform
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO


# ---------- Making it look like a car ----------

func add_car_look():
	var red = Color(0.85, 0.1, 0.1)
	var glass = Color(0.1, 0.15, 0.25)
	var dark = Color(0.08, 0.08, 0.08)
	var body = get_node_or_null("Body")
	if body:
		body.material_override = make_material(red, 0.3)
	add_box(Vector3(1.4, 0.5, 1.5), red, Vector3(0, 0.55, -0.3))        # roof
	add_box(Vector3(1.42, 0.35, 1.2), glass, Vector3(0, 0.58, -0.3))    # side windows
	add_box(Vector3(1.3, 0.38, 0.05), glass, Vector3(0, 0.56, 0.46))    # windscreen
	add_box(Vector3(1.3, 0.38, 0.05), glass, Vector3(0, 0.56, -1.06))   # back window
	add_box(Vector3(1.65, 0.18, 0.12), dark, Vector3(0, -0.22, 1.62))   # front bumper
	add_box(Vector3(1.65, 0.18, 0.12), dark, Vector3(0, -0.22, -1.62))  # back bumper
	var head = Color(1.0, 0.95, 0.6)
	var tail = Color(1.0, 0.1, 0.05)
	add_box(Vector3(0.35, 0.15, 0.05), head, Vector3(0.5, 0.1, 1.61), true)
	add_box(Vector3(0.35, 0.15, 0.05), head, Vector3(-0.5, 0.1, 1.61), true)
	add_box(Vector3(0.35, 0.12, 0.05), tail, Vector3(0.5, 0.1, -1.61), true)
	add_box(Vector3(0.35, 0.12, 0.05), tail, Vector3(-0.5, 0.1, -1.61), true)


func add_wheel_look(wheel):
	var side = sign(wheel.position.x)
	var tire = MeshInstance3D.new()
	var tire_shape = CylinderMesh.new()
	tire_shape.top_radius = wheel.wheel_radius
	tire_shape.bottom_radius = wheel.wheel_radius
	tire_shape.height = 0.3
	tire_shape.material = make_material(Color(0.05, 0.05, 0.05))
	tire.mesh = tire_shape
	tire.rotation_degrees = Vector3(0, 0, 90)
	tire.position = Vector3(0.1 * side, 0, 0)
	wheel.add_child(tire)

	var hub = MeshInstance3D.new()
	var hub_shape = CylinderMesh.new()
	hub_shape.top_radius = wheel.wheel_radius * 0.5
	hub_shape.bottom_radius = wheel.wheel_radius * 0.5
	hub_shape.height = 0.32
	hub_shape.material = make_material(Color(0.8, 0.8, 0.85), 0.9)
	hub.mesh = hub_shape
	hub.rotation_degrees = Vector3(0, 0, 90)
	hub.position = Vector3(0.1 * side, 0, 0)
	wheel.add_child(hub)


func add_box(size: Vector3, color: Color, pos: Vector3, glow := false):
	var part = MeshInstance3D.new()
	var shape = BoxMesh.new()
	shape.size = size
	var mat = make_material(color)
	if glow:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 2.0
	shape.material = mat
	part.mesh = shape
	part.position = pos
	add_child(part)


func make_material(color: Color, metal := 0.0) -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metal
	mat.roughness = 0.4
	return mat
