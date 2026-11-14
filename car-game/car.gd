extends VehicleBody3D
# BEAST CAR
# Controls: Up = gas, Down = brake/reverse, Left/Right = steer
#           Shift = NITRO, Space = handbrake (drift), R = reset

@export var body_color := Color(0.06, 0.06, 0.07)   # change me in the Inspector!
@export var stripe_color := Color(0.9, 0.05, 0.05)
@export var engine_power := 4000.0
@export var top_speed_kmh := 220.0
@export var nitro_power := 1.8          # how much stronger nitro makes the engine
@export var max_steer := 0.4
@export var engine_sound := true

var start_transform: Transform3D
var rear_wheels: Array = []
var flames: Array = []
var nitro := 100.0
var boosting := false
var speed_label: Label
var nitro_bar: ProgressBar
var cam: Camera3D
var engine_playback: AudioStreamGeneratorPlayback
var engine_phase := 0.0
var engine_pitch := 50.0


func _ready():
	can_sleep = false
	start_transform = global_transform
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, -0.5, 0)
	for wheel in get_children():
		if wheel is VehicleWheel3D:
			wheel.suspension_stiffness = 45.0
			wheel.wheel_rest_length = 0.3
			wheel.suspension_travel = 0.3
			wheel.damping_compression = 3.0
			wheel.damping_relaxation = 4.0
			wheel.wheel_friction_slip = 4.0
			if wheel.use_as_traction:
				rear_wheels.append(wheel)
			add_wheel_look(wheel)
	add_car_look()
	make_hud()
	cam = get_node_or_null("Camera3D")
	if cam:
		cam.top_level = true   # camera moves on its own and follows smoothly
	if engine_sound:
		setup_engine_sound()


func _physics_process(delta):
	if global_position.y < -10 or Input.is_key_pressed(KEY_R):
		reset_car()
		return

	var throttle = Input.get_axis("ui_down", "ui_up")
	var turn = Input.get_axis("ui_right", "ui_left")
	var forward_speed = linear_velocity.dot(global_transform.basis.z)
	var speed = linear_velocity.length()
	var kmh = abs(forward_speed) * 3.6

	# NITRO
	boosting = Input.is_key_pressed(KEY_SHIFT) and nitro > 0.0 and throttle > 0.0
	if boosting:
		nitro = max(nitro - 30.0 * delta, 0.0)
	else:
		nitro = min(nitro + 10.0 * delta, 100.0)
	for flame in flames:
		flame.visible = boosting

	# ENGINE (gets weaker near top speed)
	var power = engine_power
	var top = top_speed_kmh
	if boosting:
		power *= nitro_power
		top *= 1.3
	if throttle > 0.0 and forward_speed > 0.0:
		power *= clamp(1.0 - kmh / top, 0.0, 1.0)
	engine_force = throttle * power

	# STEERING (less steering at high speed so you don't spin out)
	var steer_limit = lerp(max_steer, 0.1, clamp(kmh / 200.0, 0.0, 1.0))
	steering = move_toward(steering, turn * steer_limit, delta * 3.0)

	# HANDBRAKE DRIFT: back wheels lose grip
	var drifting = Input.is_action_pressed("ui_accept")
	for wheel in rear_wheels:
		wheel.wheel_friction_slip = 1.2 if drifting else 4.0
		wheel.brake = 3.0 if drifting else 0.0

	# DOWNFORCE: push the car onto the road when it's fast
	apply_central_force(Vector3.DOWN * speed * speed * 0.8)

	# SPEEDOMETER
	speed_label.text = str(int(kmh)) + " km/h"
	nitro_bar.value = nitro


func _process(delta):
	update_camera(delta)
	if engine_playback:
		update_engine_sound(delta)


func reset_car():
	global_transform = start_transform
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	nitro = 100.0


# ---------- Chase camera ----------

func update_camera(delta):
	if cam == null:
		return
	var fwd = global_transform.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.1:
		fwd = Vector3.FORWARD
	fwd = fwd.normalized()
	var target = global_position - fwd * 7.0 + Vector3.UP * 2.8
	cam.global_position = cam.global_position.lerp(target, clamp(delta * 5.0, 0.0, 1.0))
	cam.look_at(global_position + fwd * 3.0 + Vector3.UP * 0.8, Vector3.UP)
	var want_fov = 70.0 + linear_velocity.length() * 0.35
	if boosting:
		want_fov += 12.0
	cam.fov = lerp(cam.fov, min(want_fov, 105.0), clamp(delta * 3.0, 0.0, 1.0))


# ---------- Speedometer + nitro bar ----------

func make_hud():
	var layer = CanvasLayer.new()
	add_child(layer)
	speed_label = Label.new()
	speed_label.add_theme_font_size_override("font_size", 56)
	speed_label.add_theme_color_override("font_outline_color", Color.BLACK)
	speed_label.add_theme_constant_override("outline_size", 10)
	speed_label.position = Vector2(30, 20)
	layer.add_child(speed_label)
	var nitro_text = Label.new()
	nitro_text.text = "NITRO (Shift)"
	nitro_text.add_theme_font_size_override("font_size", 20)
	nitro_text.add_theme_color_override("font_outline_color", Color.BLACK)
	nitro_text.add_theme_constant_override("outline_size", 6)
	nitro_text.position = Vector2(32, 100)
	layer.add_child(nitro_text)
	nitro_bar = ProgressBar.new()
	nitro_bar.min_value = 0.0
	nitro_bar.max_value = 100.0
	nitro_bar.show_percentage = false
	nitro_bar.position = Vector2(30, 130)
	nitro_bar.size = Vector2(260, 22)
	nitro_bar.modulate = Color(0.4, 0.8, 1.0)
	layer.add_child(nitro_bar)


# ---------- Engine sound (made from maths, no sound file needed) ----------

func setup_engine_sound():
	var gen = AudioStreamGenerator.new()
	gen.mix_rate = 22050.0
	gen.buffer_length = 0.1
	var player = AudioStreamPlayer.new()
	player.stream = gen
	player.volume_db = -10.0
	add_child(player)
	player.play()
	engine_playback = player.get_stream_playback()


func update_engine_sound(delta):
	var kmh = linear_velocity.length() * 3.6
	var gear_rev = fmod(kmh, 55.0) / 55.0     # revs climb, then "change gear"
	var target = 45.0 + gear_rev * 110.0 + min(kmh, 220.0) * 0.15
	if boosting:
		target += 25.0
	engine_pitch = lerp(engine_pitch, target, clamp(delta * 6.0, 0.0, 1.0))
	var frames = engine_playback.get_frames_available()
	for _i in frames:
		engine_phase = fmod(engine_phase + engine_pitch / 22050.0, 1.0)
		var s = sin(engine_phase * TAU) * 0.5 + (engine_phase * 2.0 - 1.0) * 0.3
		engine_playback.push_frame(Vector2(s, s) * 0.4)


# ---------- The beast look ----------

func add_car_look():
	var glass = Color(0.05, 0.07, 0.12)
	var dark = Color(0.03, 0.03, 0.03)
	var body = get_node_or_null("Body")
	if body:
		body.material_override = make_material(body_color, 0.6)
	add_box(Vector3(1.3, 0.38, 1.3), body_color, Vector3(0, 0.49, -0.35), false, 0.6)  # low roof
	add_box(Vector3(1.32, 0.26, 1.05), glass, Vector3(0, 0.5, -0.35))                  # side windows
	add_box(Vector3(1.22, 0.3, 0.05), glass, Vector3(0, 0.48, 0.31))                   # windscreen
	add_box(Vector3(1.22, 0.28, 0.05), glass, Vector3(0, 0.48, -1.01))                 # back window
	add_box(Vector3(0.5, 0.12, 0.6), dark, Vector3(0, 0.36, 0.9))                       # hood scoop
	for x in [-0.2, 0.2]:                                                              # racing stripes
		add_box(Vector3(0.16, 0.02, 3.22), stripe_color, Vector3(x, 0.31, 0))
		add_box(Vector3(0.16, 0.02, 1.3), stripe_color, Vector3(x, 0.69, -0.35))
	for x in [-0.5, 0.5]:                                                              # spoiler posts
		add_box(Vector3(0.08, 0.3, 0.08), dark, Vector3(x, 0.45, -1.45))
	add_box(Vector3(1.75, 0.06, 0.42), dark, Vector3(0, 0.62, -1.5))                   # spoiler wing
	for x in [-0.82, 0.82]:                                                            # side skirts
		add_box(Vector3(0.06, 0.12, 2.0), stripe_color, Vector3(x, -0.25, 0))
	add_box(Vector3(1.66, 0.18, 0.12), dark, Vector3(0, -0.22, 1.62))                  # front bumper
	add_box(Vector3(1.66, 0.18, 0.12), dark, Vector3(0, -0.22, -1.62))                 # back bumper
	add_box(Vector3(0.38, 0.1, 0.05), Color(0.8, 0.9, 1.0), Vector3(0.52, 0.12, 1.61), true)   # headlights
	add_box(Vector3(0.38, 0.1, 0.05), Color(0.8, 0.9, 1.0), Vector3(-0.52, 0.12, 1.61), true)
	add_box(Vector3(1.3, 0.07, 0.05), Color(1.0, 0.05, 0.02), Vector3(0, 0.15, -1.61), true)   # tail light bar
	for x in [-0.4, 0.4]:
		add_cylinder(self, 0.07, 0.25, Color(0.7, 0.7, 0.75), Vector3(x, -0.2, -1.7), Vector3(90, 0, 0), 0.9)
		var flame = add_box(Vector3(0.12, 0.12, 0.45), Color(0.2, 0.5, 1.0), Vector3(x, -0.2, -2.0), true)
		flame.visible = false
		flames.append(flame)


func add_wheel_look(wheel):
	var side = sign(wheel.position.x)
	var r = wheel.wheel_radius
	add_cylinder(wheel, r, 0.34, Color(0.04, 0.04, 0.04), Vector3(0.1 * side, 0, 0), Vector3(0, 0, 90))
	add_cylinder(wheel, r * 0.55, 0.36, stripe_color, Vector3(0.1 * side, 0, 0), Vector3(0, 0, 90), 0.7)


# ---------- Helpers that build shapes ----------

func add_box(size: Vector3, color: Color, pos: Vector3, glow := false, metal := 0.0) -> MeshInstance3D:
	var part = MeshInstance3D.new()
	var shape = BoxMesh.new()
	shape.size = size
	var mat = make_material(color, metal)
	if glow:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 3.0
	shape.material = mat
	part.mesh = shape
	part.position = pos
	add_child(part)
	return part


func add_cylinder(parent: Node, radius: float, height: float, color: Color, pos: Vector3, rot: Vector3, metal := 0.0) -> MeshInstance3D:
	var part = MeshInstance3D.new()
	var shape = CylinderMesh.new()
	shape.top_radius = radius
	shape.bottom_radius = radius
	shape.height = height
	shape.material = make_material(color, metal)
	part.mesh = shape
	part.position = pos
	part.rotation_degrees = rot
	parent.add_child(part)
	return part


func make_material(color: Color, metal := 0.0) -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metal
	mat.roughness = 0.35
	return mat
