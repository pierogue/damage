class_name Player
extends CharacterBody3D
## Игрок от первого лица: ходьба, бег, присед, шум шагов, удар битой.
##
## Дерево сцены:
## Player (CharacterBody3D, этот скрипт)
## ├─ CollisionShape3D (CapsuleShape3D: radius 0.4, height 1.8)
## ├─ AimPoint (Marker3D)           <- точка, в которую целятся враги
## └─ Head (Node3D)
##    ├─ Camera3D
##    │  └─ Bat (MeshInstance3D)    <- бита (опционально)
##    └─ HitArea (Area3D)           <- зона удара, BoxShape3D, смещена на -1.1 по Z

const WALK_SPEED := 3.5
const SPRINT_SPEED := 6.0
const CROUCH_SPEED := 1.8
const ACCEL := 12.0
const STAND_HEIGHT := 1.8
const CROUCH_HEIGHT := 1.1

@export var mouse_sensitivity := 0.002
@export var max_health := 100.0

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var collision: CollisionShape3D = $CollisionShape3D
@onready var aim_point: Marker3D = $AimPoint
@onready var hit_area: Area3D = $Head/HitArea
@onready var bat: Node3D = get_node_or_null("Head/Camera3D/Bat")

## Множитель дальности, с которой враги видят игрока (читают враги)
var visibility_multiplier := 1.0
var crouching := false
var health: float

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var step_timer := 0.0
var attack_cooldown := 0.0
var bat_rest_rotation := Vector3.ZERO


func _ready() -> void:
	add_to_group("player")
	_setup_input()
	# своя копия капсулы, чтобы менять высоту при приседе
	collision.shape = collision.shape.duplicate()
	health = max_health
	if bat:
		bat_rest_rotation = bat.rotation_degrees
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if event is InputEventMouseMotion and captured:
		rotate_y(-event.relative.x * mouse_sensitivity)
		head.rotate_x(-event.relative.y * mouse_sensitivity)
		head.rotation.x = clampf(head.rotation.x, deg_to_rad(-85.0), deg_to_rad(85.0))
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event.is_action_pressed("attack"):
		if not captured:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif attack_cooldown <= 0.0:
			_attack()


func _physics_process(delta: float) -> void:
	attack_cooldown = maxf(attack_cooldown - delta, 0.0)
	_update_crouch(delta)

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := (transform.basis * Vector3(input.x, 0.0, input.y)).normalized()
	var moving := input != Vector2.ZERO
	var sprinting := moving and not crouching and Input.is_action_pressed("sprint")

	var speed := WALK_SPEED
	if crouching:
		speed = CROUCH_SPEED
	elif sprinting:
		speed = SPRINT_SPEED

	velocity.x = move_toward(velocity.x, dir.x * speed, ACCEL * delta)
	velocity.z = move_toward(velocity.z, dir.z * speed, ACCEL * delta)
	if not is_on_floor():
		velocity.y -= gravity * delta
	move_and_slide()

	# заметность: присел = виден хуже, стоишь на месте = ещё чуть хуже
	visibility_multiplier = 0.5 if crouching else 1.0
	if not moving:
		visibility_multiplier *= 0.8

	_footsteps(delta, moving, sprinting)


func get_aim_point() -> Vector3:
	return aim_point.global_position


# ---------------------------------------------------------------- присед

func _update_crouch(delta: float) -> void:
	crouching = Input.is_action_pressed("crouch")
	# TODO: проверять потолок над головой перед вставанием
	var target_height := CROUCH_HEIGHT if crouching else STAND_HEIGHT
	var shape := collision.shape as CapsuleShape3D
	shape.height = lerpf(shape.height, target_height, 10.0 * delta)
	collision.position.y = shape.height / 2.0
	head.position.y = shape.height - 0.2
	aim_point.position.y = shape.height - 0.4


# ---------------------------------------------------------------- шум шагов

func _footsteps(delta: float, moving: bool, sprinting: bool) -> void:
	if not moving or not is_on_floor():
		step_timer = 0.0
		return
	step_timer -= delta
	if step_timer > 0.0:
		return
	if sprinting:
		step_timer = 0.3
		NoiseBus.emit(global_position, 10.0)
	elif crouching:
		step_timer = 0.7
		NoiseBus.emit(global_position, 1.5)
	else:
		step_timer = 0.5
		NoiseBus.emit(global_position, 5.0)


# ---------------------------------------------------------------- атака

func _attack() -> void:
	attack_cooldown = 0.7
	_play_swing()
	await get_tree().create_timer(0.15).timeout  # момент "контакта" в замахе

	var loudness := 2.0  # свист биты в воздухе
	for body in hit_area.get_overlapping_bodies():
		if body == self:
			continue
		var l := 8.0  # удар по статике (стена, пол)
		if body is Enemy:
			l = (body as Enemy).receive_bat_hit(self)
		elif body is RigidBody3D:
			var rb := body as RigidBody3D
			var push := -camera.global_transform.basis.z * 6.0 + Vector3.UP * 1.5
			rb.apply_central_impulse(push * rb.mass)
			l = 12.0
		elif body.has_method("hit"):
			body.hit(self)  # совместимость с твоими старыми объектами
			l = 10.0
		loudness = maxf(loudness, l)

	NoiseBus.emit(hit_area.global_position, loudness)


func _play_swing() -> void:
	if bat == null:
		return
	var t := create_tween()
	t.tween_property(bat, "rotation_degrees:x", bat_rest_rotation.x - 70.0, 0.12) \
		.set_ease(Tween.EASE_OUT)
	t.tween_property(bat, "rotation_degrees:x", bat_rest_rotation.x, 0.3)


# ---------------------------------------------------------------- здоровье

func take_damage(amount: float) -> void:
	health -= amount
	if health <= 0.0:
		get_tree().reload_current_scene()


# ---------------------------------------------------------------- ввод

## Регистрирует клавиши в коде, чтобы не настраивать Input Map руками.
func _setup_input() -> void:
	var keys := {
		"move_forward": KEY_W,
		"move_back": KEY_S,
		"move_left": KEY_A,
		"move_right": KEY_D,
		"sprint": KEY_SHIFT,
		"crouch": KEY_C,
	}
	for action in keys:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var ev := InputEventKey.new()
		ev.physical_keycode = keys[action]
		InputMap.action_add_event(action, ev)

	if not InputMap.has_action("attack"):
		InputMap.add_action("attack")
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("attack", mb)
