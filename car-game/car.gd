extends VehicleBody3D
# PLAYER CAR
# Controls: Up = gas, Down = brake/reverse, Left/Right = steer
#           Shift = NITRO, Space = handbrake (drift), R = reset

var models = [
	{"name": "Starter Hatch", "price": 0, "power": 2400.0, "top": 150.0, "steer": 0.45,
		"style": "hatch", "color": Color(0.15, 0.35, 0.8), "pitch": 1.15},
	{"name": "City Taxi", "price": 800, "power": 2900.0, "top": 170.0, "steer": 0.42,
		"style": "taxi", "color": Color(1.0, 0.78, 0.05), "pitch": 1.0},
	{"name": "Pickup Truck", "price": 1800, "power": 3400.0, "top": 175.0, "steer": 0.4,
		"style": "truck", "color": Color(0.2, 0.42, 0.25), "pitch": 0.75},
	{"name": "Sports GT", "price": 4000, "power": 4300.0, "top": 235.0, "steer": 0.38,
		"style": "sport", "color": Color(0.85, 0.08, 0.08), "pitch": 1.2},
	{"name": "The Beast", "price": 8000, "power": 5300.0, "top": 265.0, "steer": 0.36,
		"style": "beast", "color": Color(0.06, 0.06, 0.07), "pitch": 0.9},
	{"name": "Hyper X", "price": 15000, "power": 6600.0, "top": 320.0, "steer": 0.34,
		"style": "super", "color": Color(0.93, 0.93, 0.95), "pitch": 1.35},
]

@export var engine_sound := true

var model_index := 0
var engine_power := 2400.0
var top_speed_kmh := 150.0
var max_steer := 0.45
var nitro_power := 1.8
var pitch_scale := 1.0

var start_transform: Transform3D
var wheels: Array = []
var rear_wheels: Array = []
var wheel_parts: Array = []
var flames: Array = []
var look: Node3D
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
			wheels.append(wheel)
			if wheel.use_as_traction:
				rear_wheels.append(wheel)
	var old_body = get_node_or_null("Body")
	if old_body:
		old_body.visible = false
	make_hud()
	cam = get_node_or_null("Camera3D")
	if cam:
		cam.top_level = true
	if engine_sound:
		setup_engine_sound()
	apply_model(0)


# Switch to one of the cars in "models"
func apply_model(index: int):
	model_index = index
	var m = models[index]
	engine_power = m["power"]
	top_speed_kmh = m["top"]
	max_steer = m["steer"]
	pitch_scale = m["pitch"]
	if look:
		look.queue_free()
	for p in wheel_parts:
		p.queue_free()
	wheel_parts.clear()
	flames.clear()
	look = Node3D.new()
	add_child(look)
	build_body(look, m["style"], m["color"])
	var back_z = -style_dims(m["style"])["L"] / 2.0
	for x in [-0.4, 0.4]:
		var flame = add_box(look, Vector3(0.12, 0.12, 0.45), Color(0.2, 0.5, 1.0),
			Vector3(x, -0.22, back_z - 0.35), true)
		flame.visible = false
		flames.append(flame)
	var rim = Color(0.8, 0.8, 0.85)
	if m["style"] == "beast":
		rim = Color(0.9, 0.05, 0.05)
	for wheel in wheels:
		var side = sign(wheel.position.x)
		var r = wheel.wheel_radius
		wheel_parts.append(add_cylinder(wheel, r, 0.34, Color(0.04, 0.04, 0.04),
			Vector3(0.1 * side, 0, 0), Vector3(0, 0, 90)))
		wheel_parts.append(add_cylinder(wheel, r * 0.55, 0.36, rim,
			Vector3(0.1 * side, 0, 0), Vector3(0, 0, 90), 0.8))


func _physics_process(delta):
	if global_position.y < -10 or Input.is_key_pressed(KEY_R):
		reset_car()
		return

	var throttle = Input.get_axis("ui_down", "ui_up")
	var turn = Input.get_axis("ui_right", "ui_left")
	var forward_speed = linear_velocity.dot(global_transform.basis.z)
	var speed = linear_velocity.length()
	var kmh = abs(forward_speed) * 3.6

	boosting = Input.is_key_pressed(KEY_SHIFT) and nitro > 0.0 and throttle > 0.0
	if boosting:
		nitro = max(nitro - 30.0 * delta, 0.0)
	else:
		nitro = min(nitro + 10.0 * delta, 100.0)
	for flame in flames:
		flame.visible = boosting

	var power = engine_power
	var top = top_speed_kmh
	if boosting:
		power *= nitro_power
		top *= 1.3
	if throttle > 0.0 and forward_speed > 0.0:
		power *= clamp(1.0 - kmh / top, 0.0, 1.0)
	engine_force = throttle * power

	var steer_limit = lerp(max_steer, 0.1, clamp(kmh / 200.0, 0.0, 1.0))
	steering = move_toward(steering, turn * steer_limit, delta * 3.0)

	var drifting = Input.is_action_pressed("ui_accept")
	for wheel in rear_wheels:
		wheel.wheel_friction_slip = 1.2 if drifting else 4.0
		wheel.brake = 3.0 if drifting else 0.0

	apply_central_force(Vector3.DOWN * speed * speed * 0.8)

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


func update_camera(delta):
	if cam == null:
		return
	var fwd = global_transform.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.1:
		fwd = Vector3.FORWARD
	fwd = fwd.normalized()
	var target = global_position - fwd * 7.5 + Vector3.UP * 3.0
	cam.global_position = cam.global_position.lerp(target, clamp(delta * 5.0, 0.0, 1.0))
	cam.look_at(global_position + fwd * 3.0 + Vector3.UP * 0.8, Vector3.UP)
	var want_fov = 70.0 + linear_velocity.length() * 0.35
	if boosting:
		want_fov += 12.0
	cam.fov = lerp(cam.fov, min(want_fov, 105.0), clamp(delta * 3.0, 0.0, 1.0))


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
	var gear_rev = fmod(kmh, 55.0) / 55.0
	var target = (45.0 + gear_rev * 110.0 + min(kmh, 220.0) * 0.15) * pitch_scale
	if boosting:
		target += 25.0
	engine_pitch = lerp(engine_pitch, target, clamp(delta * 6.0, 0.0, 1.0))
	var frames = engine_playback.get_frames_available()
	for _i in frames:
		engine_phase = fmod(engine_phase + engine_pitch / 22050.0, 1.0)
		var s = sin(engine_phase * TAU) * 0.5 + (engine_phase * 2.0 - 1.0) * 0.3
		engine_playback.push_frame(Vector2(s, s) * 0.4)


# ---------- CAR LOOKS ----------
# L = length, W = width, hb = lower body height, hc = cabin height,
# cl = cabin length, cz = cabin position, ws = windscreen slope, rs = rear window slope
func style_dims(style: String) -> Dictionary:
	match style:
		"hatch":
			return {"L": 3.5, "W": 1.7, "hb": 0.58, "hc": 0.5, "cl": 1.5, "cz": -0.45, "ws": 0.6, "rs": 0.15}
		"taxi":
			return {"L": 3.9, "W": 1.74, "hb": 0.55, "hc": 0.46, "cl": 1.6, "cz": -0.2, "ws": 0.7, "rs": 0.55}
		"truck":
			return {"L": 4.1, "W": 1.84, "hb": 0.68, "hc": 0.6, "cl": 1.3, "cz": 0.55, "ws": 0.45, "rs": 0.0}
		"sport":
			return {"L": 3.9, "W": 1.8, "hb": 0.5, "hc": 0.38, "cl": 1.3, "cz": -0.35, "ws": 0.85, "rs": 0.7}
		"beast":
			return {"L": 3.6, "W": 1.75, "hb": 0.6, "hc": 0.38, "cl": 1.3, "cz": -0.35, "ws": 0.4, "rs": 0.3}
		_:
			return {"L": 4.0, "W": 1.9, "hb": 0.45, "hc": 0.33, "cl": 1.2, "cz": -0.2, "ws": 1.0, "rs": 0.8}


func build_body(parent: Node3D, style: String, color: Color):
	var d = style_dims(style)
	var L = d["L"]
	var W = d["W"]
	var hb = d["hb"]
	var hc = d["hc"]
	var cl = d["cl"]
	var cz = d["cz"]
	var glass = Color(0.05, 0.08, 0.13)
	var dark = Color(0.03, 0.03, 0.03)
	var chrome = Color(0.8, 0.8, 0.85)
	var top = -0.3 + hb
	var fz = L / 2.0
	var bz = -L / 2.0
	var cab_front = cz + cl / 2.0
	var cab_back = cz - cl / 2.0

	add_box(parent, Vector3(W, hb, L), color, Vector3(0, -0.3 + hb / 2.0, 0), false, 0.5)
	add_box(parent, Vector3(W - 0.12, hc, cl), color, Vector3(0, top + hc / 2.0, cz), false, 0.5)
	add_box(parent, Vector3(W - 0.1, hc * 0.62, cl - 0.25), glass, Vector3(0, top + hc * 0.48, cz))
	add_wedge(parent, d["ws"], hc, W - 0.2, Vector3(0, top + hc / 2.0, cab_front + d["ws"] / 2.0), 1.0, glass)
	if d["rs"] > 0.01:
		add_wedge(parent, d["rs"], hc, W - 0.2, Vector3(0, top + hc / 2.0, cab_back - d["rs"] / 2.0), 0.0, glass)

	add_box(parent, Vector3(W + 0.04, 0.16, 0.14), dark, Vector3(0, -0.24, fz))
	add_box(parent, Vector3(W + 0.04, 0.16, 0.14), dark, Vector3(0, -0.24, bz))
	add_box(parent, Vector3(W * 0.5, 0.14, 0.03), dark, Vector3(0, top - 0.15, fz + 0.01))
	add_box(parent, Vector3(W * 0.5, 0.025, 0.035), chrome, Vector3(0, top - 0.07, fz + 0.012), false, 0.9)
	for s in [-1.0, 1.0]:
		var x = s * (W / 2.0 - 0.28)
		add_box(parent, Vector3(0.36, 0.11, 0.04), Color(0.85, 0.92, 1.0), Vector3(x, top - 0.1, fz + 0.01), true)
		add_box(parent, Vector3(0.36, 0.1, 0.04), Color(1.0, 0.05, 0.02), Vector3(x, top - 0.1, bz - 0.01), true)
		add_box(parent, Vector3(0.16, 0.09, 0.07), color, Vector3(s * (W / 2.0 + 0.05), top + 0.12, cab_front - 0.05))
		add_box(parent, Vector3(0.02, 0.06, L * 0.7), dark, Vector3(s * (W / 2.0 + 0.005), -0.12, 0))
		add_box(parent, Vector3(0.02, hb * 0.75, 0.02), dark, Vector3(s * (W / 2.0 + 0.005), -0.3 + hb / 2.0, cz + cl * 0.1))
	add_box(parent, Vector3(0.42, 0.12, 0.02), Color(0.95, 0.95, 0.9), Vector3(0, -0.16, fz + 0.08))
	add_box(parent, Vector3(0.42, 0.12, 0.02), Color(0.95, 0.95, 0.9), Vector3(0, -0.16, bz - 0.08))

	match style:
		"taxi":
			add_box(parent, Vector3(0.6, 0.18, 0.25), Color(1.0, 0.95, 0.7), Vector3(0, top + hc + 0.09, cz), true)
			for i in range(8):
				if i % 2 == 0:
					for s in [-1.0, 1.0]:
						add_box(parent, Vector3(0.02, 0.08, 0.25), dark, Vector3(s * (W / 2.0 + 0.006), top - 0.18, -1.0 + i * 0.25))
		"truck":
			var bed_len = cab_back - bz - 0.1
			var bed_z = (cab_back + bz) / 2.0 - 0.05
			add_box(parent, Vector3(W - 0.1, 0.05, bed_len), dark, Vector3(0, top + 0.02, bed_z))
			for s in [-1.0, 1.0]:
				add_box(parent, Vector3(0.08, 0.35, bed_len), color, Vector3(s * (W / 2.0 - 0.04), top + 0.175, bed_z), false, 0.5)
			add_box(parent, Vector3(W, 0.35, 0.08), color, Vector3(0, top + 0.175, bz + 0.04), false, 0.5)
			add_box(parent, Vector3(W - 0.3, 0.06, 0.12), Color(1.0, 0.6, 0.1), Vector3(0, top + hc + 0.03, cz + 0.4), true)
		"sport":
			add_box(parent, Vector3(W - 0.2, 0.05, 0.25), dark, Vector3(0, top + 0.05, bz + 0.22))
			for s in [-1.0, 1.0]:
				add_box(parent, Vector3(0.03, 0.12, 0.5), dark, Vector3(s * (W / 2.0 + 0.01), top - 0.2, 0.3))
		"beast":
			var red = Color(0.9, 0.05, 0.05)
			add_box(parent, Vector3(0.5, 0.12, 0.6), dark, Vector3(0, top + 0.06, fz - 0.8))
			for x in [-0.2, 0.2]:
				add_box(parent, Vector3(0.16, 0.02, L + 0.02), red, Vector3(x, top + 0.01, 0))
				add_box(parent, Vector3(0.16, 0.02, cl), red, Vector3(x, top + hc + 0.01, cz))
			for x in [-0.5, 0.5]:
				add_box(parent, Vector3(0.08, 0.3, 0.08), dark, Vector3(x, top + 0.15, bz + 0.35))
			add_box(parent, Vector3(W, 0.06, 0.42), dark, Vector3(0, top + 0.32, bz + 0.3))
			for s in [-1.0, 1.0]:
				add_box(parent, Vector3(0.06, 0.12, L * 0.6), red, Vector3(s * (W / 2.0 + 0.02), -0.25, 0))
		"super":
			for x in [-0.6, 0.6]:
				add_box(parent, Vector3(0.08, 0.35, 0.08), dark, Vector3(x, top + 0.17, bz + 0.35))
			add_box(parent, Vector3(W, 0.05, 0.45), dark, Vector3(0, top + 0.36, bz + 0.3))
			for s in [-1.0, 1.0]:
				add_box(parent, Vector3(0.04, 0.2, 0.6), dark, Vector3(s * (W / 2.0), top - 0.15, -0.6))
			add_box(parent, Vector3(0.1, 0.02, L + 0.02), Color(0.1, 0.1, 0.1), Vector3(0, top + 0.01, 0))


# A triangle-shaped glass piece (used for sloped windscreens)
func add_wedge(parent: Node3D, length: float, height: float, width: float, pos: Vector3, apex: float, color: Color):
	var part = MeshInstance3D.new()
	var shape = PrismMesh.new()
	shape.size = Vector3(length, height, width)
	shape.left_to_right = apex
	shape.material = make_material(color)
	part.mesh = shape
	part.position = pos
	part.rotation_degrees = Vector3(0, 90, 0)
	parent.add_child(part)


func add_box(parent: Node3D, size: Vector3, color: Color, pos: Vector3, glow := false, metal := 0.0) -> MeshInstance3D:
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
	parent.add_child(part)
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
