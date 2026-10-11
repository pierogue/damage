class_name Player
extends CharacterBody3D
## Игрок от первого лица: ходьба, бег, присед, прыжок, карабканье по стенам,
## шум, бита и пистолет.
##
## Управление: WASD ходьба, Shift бег, C присед, Space прыжок,
## Space + W у стены = карабкаться, ЛКМ атака, 1 бита, 2 пистолет,
## R перезарядка, Esc освободить мышь.
##
## Дерево сцены:
## Player (CharacterBody3D, этот скрипт)
## ├─ CollisionShape3D (CapsuleShape3D: radius 0.4, height 1.8)
## ├─ AimPoint (Marker3D)           <- точка, в которую целятся враги
## └─ Head (Node3D)
##    ├─ Camera3D
##    │  ├─ Bat (узел модели биты)      <- опционально
##    │  └─ Pistol (узел модели пистолета) <- опционально
##    └─ HitArea (Area3D)           <- зона удара битой, BoxShape3D, смещена на -1.1 по Z
##
## Нет узла Bat = биты нет. Нет узла Pistol = пистолета нет.

enum Weapon { BAT, PISTOL }

const WALK_SPEED := 3.5
const SPRINT_SPEED := 6.5
const CROUCH_SPEED := 1.8
const ACCEL := 60.0       # разгон на земле (больше = резче, 1000 = мгновенно)
const DECEL := 80.0       # торможение на земле (больше = останавливается резче)
const AIR_ACCEL := 10.0   # управление в воздухе
const JUMP_VELOCITY := 5.0
const CLIMB_SPEED := 2.5
const STAND_HEIGHT := 1.8
const CROUCH_HEIGHT := 1.1

const PISTOL_RANGE := 80.0
const PISTOL_NOISE := 35.0     # радиус, в котором слышно выстрел
const MAG_SIZE := 12
const START_RESERVE := 36
const RELOAD_TIME := 1.5

@export var mouse_sensitivity := 0.002
@export var max_health := 100.0
@export var max_climb_time := 4.0
@export var pistol_damage := 50.0   # здоровье врага по умолчанию 100 = 2 выстрела

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var collision: CollisionShape3D = $CollisionShape3D
@onready var aim_point: Marker3D = $AimPoint
@onready var hit_area: Area3D = $Head/HitArea
@onready var bat: Node3D = get_node_or_null("Head/Camera3D/Bat")
@onready var pistol: Node3D = get_node_or_null("Head/Camera3D/Pistol")

## Множитель дальности, с которой враги видят игрока (читают враги)
var visibility_multiplier := 1.0
var crouching := false
var climbing := false
var mantling := false
var health: float

var current_weapon := Weapon.BAT
var ammo_in_mag := 0
var ammo_reserve := 0
var reloading := false
var reload_id := 0              # чтобы отменять перезарядку при смене оружия

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var step_timer := 0.0
var climb_noise_timer := 0.0
var climb_time_left := 0.0
var was_on_floor := true
var attack_cooldown := 0.0
var bat_rest_rotation := Vector3.ZERO
var pistol_rest_position := Vector3.ZERO
var pistol_rest_rotation := Vector3.ZERO

var hud_label: Label
var muzzle_light: OmniLight3D


func _ready() -> void:
	add_to_group("player")
	_setup_input()
	# своя копия капсулы, чтобы менять высоту при приседе
	collision.shape = collision.shape.duplicate()
	health = max_health
	climb_time_left = max_climb_time
	ammo_in_mag = MAG_SIZE
	ammo_reserve = START_RESERVE

	if bat:
		bat_rest_rotation = bat.rotation_degrees
	if pistol:
		pistol_rest_position = pistol.position
		pistol_rest_rotation = pistol.rotation_degrees

	_build_hud()
	_build_muzzle_light()
	_set_weapon(Weapon.BAT if bat else Weapon.PISTOL)
	_update_hud()
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
		elif attack_cooldown <= 0.0 and not mantling:
			if current_weapon == Weapon.BAT:
				_bat_attack()
			else:
				_shoot()
	elif event.is_action_pressed("weapon_1"):
		_set_weapon(Weapon.BAT)
	elif event.is_action_pressed("weapon_2"):
		_set_weapon(Weapon.PISTOL)
	elif event.is_action_pressed("reload"):
		_reload()


func _physics_process(delta: float) -> void:
	attack_cooldown = maxf(attack_cooldown - delta, 0.0)
	if mantling:
		return  # во время вылезания на уступ двигает твин

	_update_crouch(delta)
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")

	if is_on_floor():
		climb_time_left = max_climb_time

	# ---- карабканье (приоритет над обычным движением)
	if _handle_climb(delta, input):
		if mantling:
			return
		visibility_multiplier = 1.0
		move_and_slide()
		was_on_floor = false
		_climb_noise(delta)
		return

	# ---- обычное движение
	var dir := (transform.basis * Vector3(input.x, 0.0, input.y)).normalized()
	var moving := input != Vector2.ZERO
	var sprinting := moving and not crouching and Input.is_action_pressed("sprint")

	var speed := WALK_SPEED
	if crouching:
		speed = CROUCH_SPEED
	elif sprinting:
		speed = SPRINT_SPEED

	var accel := AIR_ACCEL
	if is_on_floor():
		accel = ACCEL if moving else DECEL
	velocity.x = move_toward(velocity.x, dir.x * speed, accel * delta)
	velocity.z = move_toward(velocity.z, dir.z * speed, accel * delta)

	if not is_on_floor():
		velocity.y -= gravity * delta
	elif Input.is_action_just_pressed("jump") and not crouching:
		velocity.y = JUMP_VELOCITY
		NoiseBus.emit(global_position, 4.0)

	var fall_speed := -velocity.y
	move_and_slide()

	# приземление шумит тем сильнее, чем выше упал
	if is_on_floor() and not was_on_floor and fall_speed > 4.0:
		NoiseBus.emit(global_position, clampf(fall_speed * 1.5, 4.0, 14.0))
	was_on_floor = is_on_floor()

	camera.fov = lerpf(camera.fov, 82.0 if sprinting else 75.0, 8.0 * delta)

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


# ---------------------------------------------------------------- карабканье

## Луч в мир (слой 1), игрок исключён.
func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, 1, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query)


## Возвращает true, если игрок карабкается в этом кадре.
## Начать: зажать Space и идти вперёд (W) у стены. Продолжать: держать Space.
func _handle_climb(delta: float, input: Vector2) -> bool:
	if crouching or not Input.is_action_pressed("jump") or climb_time_left <= 0.0:
		climbing = false
		return false

	var fwd := -global_transform.basis.z
	var origin := global_position + Vector3.UP * 0.9
	var wall := _ray(origin, origin + fwd * 0.8)

	var is_wall := not wall.is_empty() \
		and absf(wall.normal.y) < 0.3 \
		and not (wall.collider as Node).is_in_group("no_climb")
	if not is_wall or (not climbing and input.y >= 0.0):
		climbing = false
		return false

	climbing = true
	climb_time_left -= delta

	# над головой стены нет, а впереди есть площадка = можно вылезти наверх
	var top := global_position + Vector3.UP * (STAND_HEIGHT + 0.1)
	if _ray(top, top + fwd * 0.8).is_empty():
		var ahead := top + fwd * 0.7
		var ledge := _ray(ahead, ahead + Vector3.DOWN * 1.8)
		if not ledge.is_empty() and ledge.normal.y > 0.7:
			_mantle(ledge.position + Vector3.UP * 0.05)
			return true

	# W вверх, S вниз, A/D в стороны, без ввода просто висим
	var vertical := -input.y * CLIMB_SPEED
	var lateral := transform.basis.x * input.x * CLIMB_SPEED * 0.6
	velocity = Vector3.UP * vertical + lateral - wall.normal * 0.5
	return true


func _mantle(target: Vector3) -> void:
	mantling = true
	climbing = false
	velocity = Vector3.ZERO
	NoiseBus.emit(global_position, 4.0)
	var t := create_tween()
	t.tween_property(self, "global_position:y", target.y, 0.25).set_trans(Tween.TRANS_SINE)
	t.tween_property(self, "global_position", target, 0.2).set_trans(Tween.TRANS_SINE)
	await t.finished
	mantling = false


func _climb_noise(delta: float) -> void:
	if velocity.length() < 0.3:
		return
	climb_noise_timer -= delta
	if climb_noise_timer <= 0.0:
		climb_noise_timer = 0.6
		NoiseBus.emit(global_position, 4.0)


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


# ---------------------------------------------------------------- оружие

func _set_weapon(w: Weapon) -> void:
	if w == Weapon.BAT and bat == null:
		return
	if w == Weapon.PISTOL and pistol == null:
		return
	current_weapon = w
	reload_id += 1          # отменяет идущую перезарядку
	reloading = false
	attack_cooldown = 0.3
	if bat:
		bat.visible = (w == Weapon.BAT)
	if pistol:
		pistol.visible = (w == Weapon.PISTOL)
	_update_hud()


# ---------------------------------------------------------------- бита

func _bat_attack() -> void:
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


# ---------------------------------------------------------------- пистолет

func _shoot() -> void:
	if reloading:
		return
	if ammo_in_mag <= 0:
		attack_cooldown = 0.3
		NoiseBus.emit(global_position, 3.0)  # сухой щелчок
		if ammo_reserve > 0:
			_reload()
		return

	ammo_in_mag -= 1
	attack_cooldown = 0.35
	_play_recoil()
	_flash()

	# пуля летит из центра камеры; маска: слой 1 (мир) + слой 3 (враги) = 1 | 4
	var from := camera.global_position
	var dir := -camera.global_transform.basis.z
	var query := PhysicsRayQueryParameters3D.create(
		from, from + dir * PISTOL_RANGE, 1 | 4, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)

	if not hit.is_empty():
		var col: Object = hit.collider
		if col is Enemy:
			(col as Enemy).receive_shot(self, pistol_damage)
		elif col is RigidBody3D:
			var rb := col as RigidBody3D
			rb.apply_impulse(dir * 4.0 * rb.mass, hit.position - rb.global_position)
		else:
			_spawn_bullet_mark(hit.position, hit.normal)

	# выстрел очень громкий: его слышат враги далеко вокруг
	NoiseBus.emit(global_position, PISTOL_NOISE)
	_update_hud()


func _reload() -> void:
	if current_weapon != Weapon.PISTOL or reloading:
		return
	if ammo_in_mag >= MAG_SIZE or ammo_reserve <= 0:
		return

	reloading = true
	reload_id += 1
	var my_id := reload_id
	NoiseBus.emit(global_position, 3.0)
	_play_reload_anim()
	_update_hud()

	await get_tree().create_timer(RELOAD_TIME).timeout
	if my_id != reload_id:
		return  # отменено сменой оружия

	var take := mini(MAG_SIZE - ammo_in_mag, ammo_reserve)
	ammo_in_mag += take
	ammo_reserve -= take
	reloading = false
	_update_hud()


func _play_recoil() -> void:
	if pistol == null:
		return
	var t := create_tween()
	t.tween_property(pistol, "position", pistol_rest_position + Vector3(0.0, 0.02, 0.1), 0.05)
	t.parallel().tween_property(pistol, "rotation_degrees:x", pistol_rest_rotation.x + 10.0, 0.05)
	t.tween_property(pistol, "position", pistol_rest_position, 0.15)
	t.parallel().tween_property(pistol, "rotation_degrees:x", pistol_rest_rotation.x, 0.15)


func _play_reload_anim() -> void:
	if pistol == null:
		return
	var t := create_tween()
	t.tween_property(pistol, "rotation_degrees:x", pistol_rest_rotation.x - 50.0, 0.25)
	t.tween_interval(RELOAD_TIME - 0.55)
	t.tween_property(pistol, "rotation_degrees:x", pistol_rest_rotation.x, 0.3)


func _flash() -> void:
	muzzle_light.visible = true
	await get_tree().create_timer(0.05).timeout
	muzzle_light.visible = false


func _spawn_bullet_mark(pos: Vector3, normal: Vector3) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var mark := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.04
	sphere.height = 0.08
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.05, 0.05, 0.05)
	sphere.material = mat
	mark.mesh = sphere
	scene.add_child(mark)
	mark.global_position = pos + normal * 0.01
	await get_tree().create_timer(8.0).timeout
	if is_instance_valid(mark):
		mark.queue_free()


func _build_muzzle_light() -> void:
	muzzle_light = OmniLight3D.new()
	muzzle_light.light_color = Color(1.0, 0.7, 0.3)
	muzzle_light.light_energy = 4.0
	muzzle_light.omni_range = 8.0
	muzzle_light.position = Vector3(0.3, -0.2, -1.0)
	muzzle_light.visible = false
	camera.add_child(muzzle_light)


# ---------------------------------------------------------------- HUD

## Прицел и текст со здоровьем и патронами создаются прямо в коде.
func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var cross := Label.new()
	layer.add_child(cross)
	cross.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cross.text = "+"
	cross.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cross.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cross.mouse_filter = Control.MOUSE_FILTER_IGNORE

	hud_label = Label.new()
	layer.add_child(hud_label)
	hud_label.position = Vector2(20.0, 20.0)
	hud_label.add_theme_font_size_override("font_size", 22)
	hud_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	hud_label.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _update_hud() -> void:
	if hud_label == null:
		return
	var weapon_text := "Bat"
	if current_weapon == Weapon.PISTOL:
		weapon_text = "Pistol  %d / %d" % [ammo_in_mag, ammo_reserve]
		if reloading:
			weapon_text += "  (reloading...)"
	hud_label.text = "HP: %d\n%s" % [int(health), weapon_text]


# ---------------------------------------------------------------- здоровье

func take_damage(amount: float) -> void:
	health -= amount
	_update_hud()
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
		"jump": KEY_SPACE,
		"reload": KEY_R,
		"weapon_1": KEY_1,
		"weapon_2": KEY_2,
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
