class_name Player
extends CharacterBody3D
## Игрок от первого лица: ходьба, бег, присед, прыжок, карабканье по стенам,
## шум и три вида оружия: финка, пистолет, пистолет-пулемёт.
##
## Управление: WASD ходьба, Shift бег, C присед, Space прыжок,
## Space + W у стены = карабкаться, ЛКМ атака (у ПП можно зажать),
## 1-3 или колёсико мыши смена оружия, R перезарядка, Esc освободить мышь,
## Q / E наклон влево / вправо (выглядывание из-за угла).
##
## Дерево сцены:
## Player (CharacterBody3D, этот скрипт)
## ├─ CollisionShape3D (CapsuleShape3D: radius 0.4, height 1.8)
## ├─ AimPoint (Marker3D)
## └─ Head (Node3D)
##    ├─ Camera3D
##    │  ├─ Knife    (модель финки)         <- любой из трёх узлов
##    │  ├─ Pistol   (модель пистолета)        можно не добавлять,
##    │  └─ SMG      (модель пистолета-пулемёта) тогда этого оружия просто нет
##    └─ HitArea (Area3D)  <- зона удара ближнего боя, BoxShape3D, смещена на -1.1 по Z

# ------------------------------------------------------------------ ОРУЖИЕ
# Здесь настраивается всё оружие. melee = ближний бой, иначе стрельба.
#   node      имя узла модели под Camera3D
#   cooldown  пауза между атаками (сек)
#   damage    урон (здоровье врага по умолчанию 100)
#   ближний бой: delay (момент попадания в замахе), reach (дальность в метрах),
#                swing (угол замаха), lunge (выпад вперёд), push (сила толчка предметов),
#                hit_noise (шум удара), kill_noise (шум убийства со спины)
#   стрельба:    auto (зажатая кнопка), mag (обойма), reserve (запас патронов),
#                reload (время перезарядки), noise (радиус слышимости выстрела),
#                spread (разброс в градусах), recoil (отдача модели), kick (подброс камеры)
const WEAPONS := {
	"knife": {
		"name": "Knife", "node": "Knife", "melee": true,
		"cooldown": 0.4, "damage": 35.0, "delay": 0.08, "reach": 1.7,
		"swing": 30.0, "lunge": 0.25, "push": 2.0,
		"hit_noise": 5.0, "kill_noise": 1.0,
	},
	"pistol": {
		"name": "Pistol", "node": "Pistol", "melee": false,
		"cooldown": 0.35, "damage": 50.0, "auto": false,
		"mag": 12, "reserve": 36, "reload": 1.5,
		"noise": 35.0, "spread": 0.0, "recoil": 10.0, "kick": 1.2,
	},
	"smg": {
		"name": "SMG", "node": "SMG", "melee": false,
		"cooldown": 0.08, "damage": 20.0, "auto": true,
		"mag": 30, "reserve": 90, "reload": 2.0,
		"noise": 40.0, "spread": 2.5, "recoil": 4.0, "kick": 0.5,
	},
}
const ORDER := ["knife", "pistol", "smg"]           # порядок клавиш 1-3
const RANGE := 80.0                                 # дальность пули

# ------------------------------------------------------------------ ДВИЖЕНИЕ
const WALK_SPEED := 3.5
const SPRINT_SPEED := 6.5
const CROUCH_SPEED := 1.8
const PRONE_SPEED := 0.5
const ACCEL := 60.0       # разгон на земле (больше = резче, 1000 = мгновенно)
const DECEL := 80.0       # торможение на земле
const AIR_ACCEL := 10.0   # управление в воздухе
const JUMP_VELOCITY := 5.0
const CLIMB_SPEED := 2.5
const STAND_HEIGHT := 1.8
const CROUCH_HEIGHT := 1.1
const PRONE_HEIGHT := 0.8
const LEAN_DISTANCE := 0.6   # на сколько метров голова уходит в сторону
const LEAN_ANGLE := 15.0     # наклон камеры в градусах
const LEAN_SPEED := 10.0     # скорость наклона (больше = резче)
const RECOIL_RECOVERY := 10.0  # как быстро прицел возвращается после отдачи
const RECOIL_DELAY := 0.1      # пауза после выстрела перед возвратом (сек)
const MAX_RECOIL := 0.21       # максимум накопленной отдачи, радианы (~12 градусов)
const STAMINA_DRAIN := 20.0
const STAMINA_REGEN := 15.0
const STAMINA_REGEN_DELAY := 1.0


@export var mouse_sensitivity := 0.002
@export var max_health := 100.0
@export var max_stamina := 100.0
@export var max_climb_time := 4.0

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var collision: CollisionShape3D = $CollisionShape3D
@onready var aim_point: Marker3D = $AimPoint
@onready var hit_area: Area3D = $Head/HitArea

## Множитель дальности, с которой враги видят игрока (читают враги)
var visibility_multiplier := 1.0
var crouching := false
var proning := false
var climbing := false
var lean := 0.0                 # -1 влево ... 1 вправо, плавно меняется
var recoil_offset := 0.0        # на сколько отдача подняла прицел (радианы)
var recoil_timer := 0.0
var mantling := false
var health: float
var stamina: float

var current_weapon := "knife"
var weapon_nodes := {}          # id -> узел модели (только те, что есть в сцене)
var rest_pos := {}              # id -> исходная позиция модели
var rest_rot := {}              # id -> исходный поворот модели
var ammo_mag := {}              # id -> патронов в обойме
var ammo_reserve := {}          # id -> патронов в запасе
var weapon_tween: Tween
var reloading := false
var reload_id := 0              # чтобы отменять перезарядку при смене оружия

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var step_timer := 0.0
var climb_noise_timer := 0.0
var climb_time_left := 0.0
var was_on_floor := true
var attack_cooldown := 0.0

var hud_label: Label
var muzzle_light: OmniLight3D
var stamina_regen_timer := 0.0


func _ready() -> void:
	add_to_group("player")
	_setup_input()
	# своя копия капсулы, чтобы менять высоту при приседе
	collision.shape = collision.shape.duplicate()
	health = max_health
	stamina = max_stamina
	climb_time_left = max_climb_time

	# находим модели оружия и запоминаем их исходное положение
	for id in ORDER:
		var data: Dictionary = WEAPONS[id]
		var node := get_node_or_null("Head/Camera3D/" + String(data["node"])) as Node3D
		if node:
			weapon_nodes[id] = node
			rest_pos[id] = node.position
			rest_rot[id] = node.rotation_degrees
			node.visible = false
		if not data["melee"]:
			ammo_mag[id] = data["mag"]
			ammo_reserve[id] = data["reserve"]

	_build_hud()
	_build_muzzle_light()
	for id in ORDER:           # стартуем с первого доступного оружия
		if weapon_nodes.has(id):
			_set_weapon(id)
			break
	_update_hud()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if event is InputEventMouseMotion and captured:
		rotate_y(-event.relative.x * mouse_sensitivity)
		head.rotate_x(-event.relative.y * mouse_sensitivity)
		# если игрок сам опускает прицел, это гасит отдачу, и возврат не перелетит
		var pitch_change: float = -event.relative.y * mouse_sensitivity
		if pitch_change < 0.0 and recoil_offset > 0.0:
			recoil_offset = maxf(recoil_offset + pitch_change, 0.0)
		head.rotation.x = clampf(head.rotation.x, deg_to_rad(-85.0), deg_to_rad(85.0))
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event.is_action_pressed("attack") and not captured:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		attack_cooldown = 0.2   # этот клик только захватывает мышь
	elif event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_WHEEL_UP:
		_cycle_weapon(-1)
	elif event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_cycle_weapon(1)
	elif event.is_action_pressed("weapon_1"):
		_set_weapon("knife")
	elif event.is_action_pressed("weapon_2"):
		_set_weapon("pistol")
	elif event.is_action_pressed("weapon_3"):
		_set_weapon("smg")
	elif event.is_action_pressed("reload"):
		_reload()


func _physics_process(delta: float) -> void:
	attack_cooldown = maxf(attack_cooldown - delta, 0.0)
	_update_recoil(delta)
	if mantling:
		return  # во время вылезания на уступ двигает твин

	_handle_attack()
	_update_crouch(delta)
	_update_prone(delta)
	_update_lean(delta)
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
	var wants_sprint := moving and not crouching and not proning and Input.is_action_pressed("sprint")
	var sprinting := wants_sprint and stamina > 0.0

	var speed := WALK_SPEED
	if crouching:
		speed = CROUCH_SPEED
	elif sprinting:
		speed = SPRINT_SPEED
	if proning:
		speed = PRONE_SPEED
	elif sprinting:
		speed = SPRINT_SPEED
	# расход и восстановление стамины
	if sprinting and moving:
		stamina = maxf(stamina - STAMINA_DRAIN * delta, 0.0)
		stamina_regen_timer = STAMINA_REGEN_DELAY
	else:
		stamina_regen_timer = maxf(stamina_regen_timer - delta, 0.0)
		if stamina_regen_timer <= 0.0:
			stamina = minf(stamina + STAMINA_REGEN * delta, max_stamina)
	_update_hud()

	var accel := AIR_ACCEL
	if is_on_floor():
		accel = ACCEL if moving else DECEL
	velocity.x = move_toward(velocity.x, dir.x * speed, accel * delta)
	velocity.z = move_toward(velocity.z, dir.z * speed, accel * delta)

	if not is_on_floor():
		velocity.y -= gravity * delta
	elif Input.is_action_just_pressed("jump") and not crouching and not proning:
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
	if proning:
		visibility_multiplier = 0.1
	elif crouching:
		visibility_multiplier = 0.5
	else:
		visibility_multiplier = 1.0
	if not moving:
		visibility_multiplier *= 0.8

	_footsteps(delta, moving, sprinting)


func get_aim_point() -> Vector3:
	return aim_point.global_position

# ---------------------------------------------------------------- лежачка
func _update_prone(delta: float) -> void:
	if Input.is_action_just_pressed("prone"):
		proning = not proning
		if proning:
			crouching = false   # лёжа не сидим
	var target_height := PRONE_HEIGHT if proning else STAND_HEIGHT
	var shape := collision.shape as CapsuleShape3D
	shape.height = lerpf(shape.height, target_height, 10.0 * delta)
	collision.position.y = shape.height / 2.0
	# лёжа голова опускается ещё ниже формы капсулы
	var head_y: float = 0.25 if proning else shape.height - 0.2
	head.position.y = lerpf(head.position.y, head_y, 10.0 * delta)
	aim_point.position.y = lerpf(aim_point.position.y, head_y - 0.2, 10.0 * delta)
# ---------------------------------------------------------------- присед

func _update_crouch(delta: float) -> void:
	if Input.is_action_just_pressed("crouch"):
		crouching = not crouching
	# TODO: проверять потолок над головой перед вставанием
	if crouching:
		proning = false
	var target_height := CROUCH_HEIGHT if crouching else STAND_HEIGHT
	var shape := collision.shape as CapsuleShape3D
	shape.height = lerpf(shape.height, target_height, 10.0 * delta)
	collision.position.y = shape.height / 2.0
	head.position.y = shape.height - 0.2
	aim_point.position.y = shape.height - 0.4


# ---------------------------------------------------------------- наклоны (lean)

## Q / E: голова смещается в сторону и камера кренится.
## Если сбоку стена, наклон ограничивается, чтобы камера не пролезла внутрь.
func _update_lean(delta: float) -> void:
	var target := 0.0
	if not climbing:
		target = Input.get_axis("lean_left", "lean_right")

	if target != 0.0:
		var origin := global_position + Vector3.UP * head.position.y
		var side := global_transform.basis.x * signf(target)
		var wall := _ray(origin, origin + side * (LEAN_DISTANCE + 0.3))
		if not wall.is_empty():
			var free := maxf(origin.distance_to(wall.position) - 0.3, 0.0)
			target *= clampf(free / LEAN_DISTANCE, 0.0, 1.0)

	lean = lerpf(lean, target, LEAN_SPEED * delta)
	head.position.x = lean * LEAN_DISTANCE
	head.rotation.z = -lean * deg_to_rad(LEAN_ANGLE)
	# враги целятся в AimPoint, поэтому он тоже выглядывает вместе с головой
	aim_point.position.x = lean * LEAN_DISTANCE


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
	if proning:
		step_timer = 1
		NoiseBus.emit(global_position, 1.0)
	elif crouching:
		step_timer = 0.7
		NoiseBus.emit(global_position, 1.5)
	else:
		step_timer = 0.5
		NoiseBus.emit(global_position, 5.0)


# ---------------------------------------------------------------- смена оружия

func _set_weapon(id: String) -> void:
	if not weapon_nodes.has(id):
		return  # такого оружия нет в сцене
	if weapon_tween:
		weapon_tween.kill()
	for other in weapon_nodes:
		var node: Node3D = weapon_nodes[other]
		node.visible = (other == id)
		node.position = rest_pos[other]
		node.rotation_degrees = rest_rot[other]
	current_weapon = id
	reload_id += 1          # отменяет идущую перезарядку
	reloading = false
	attack_cooldown = 0.3   # время "доставания" оружия
	_update_hud()


## Колёсико мыши: следующее/предыдущее из доступных видов оружия.
func _cycle_weapon(step: int) -> void:
	var idx := ORDER.find(current_weapon)
	for i in ORDER.size():
		idx = posmod(idx + step, ORDER.size())
		if weapon_nodes.has(ORDER[idx]):
			_set_weapon(ORDER[idx])
			return


# ---------------------------------------------------------------- атака

func _handle_attack() -> void:
	if attack_cooldown > 0.0 or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	var data: Dictionary = WEAPONS[current_weapon]
	var wants := false
	if data.get("auto", false):
		wants = Input.is_action_pressed("attack")       # зажатая кнопка (ПП)
	else:
		wants = Input.is_action_just_pressed("attack")  # один клик = одна атака
	if not wants:
		return
	if data["melee"]:
		_melee_attack(data)
	else:
		_fire(data)


# ---- ближний бой (финка)

func _melee_attack(data: Dictionary) -> void:
	attack_cooldown = data["cooldown"]
	_play_melee_anim(data)
	await get_tree().create_timer(data["delay"]).timeout  # момент "контакта" в замахе

	var hit_noise: float = data["hit_noise"]
	var loudness := hit_noise * 0.2   # свист оружия в воздухе
	for body in hit_area.get_overlapping_bodies():
		if body == self:
			continue
		var l := hit_noise * 0.7      # удар по статике (стена, пол)
		if body is Enemy:
			var flat := Vector2(
				body.global_position.x - global_position.x,
				body.global_position.z - global_position.z)
			if flat.length() > float(data["reach"]):
				continue              # враг дальше, чем достаёт это оружие
			l = (body as Enemy).receive_melee_hit(
				self, data["damage"], hit_noise, data["kill_noise"])
		elif body is RigidBody3D:
			var rb := body as RigidBody3D
			var push := -camera.global_transform.basis.z * float(data["push"]) + Vector3.UP * 1.5
			rb.apply_central_impulse(push * rb.mass)
			l = hit_noise
		elif body.has_method("hit"):
			body.hit(self)  # совместимость с твоими старыми объектами
			l = hit_noise
		loudness = maxf(loudness, l)

	NoiseBus.emit(hit_area.global_position, loudness)


func _play_melee_anim(data: Dictionary) -> void:
	var node: Node3D = weapon_nodes.get(current_weapon)
	if node == null:
		return
	var rp: Vector3 = rest_pos[current_weapon]
	var rr: Vector3 = rest_rot[current_weapon]
	if weapon_tween:
		weapon_tween.kill()
	weapon_tween = create_tween()
	weapon_tween.tween_property(
		node, "rotation_degrees:x", rr.x - float(data["swing"]), 0.1).set_ease(Tween.EASE_OUT)
	weapon_tween.parallel().tween_property(
		node, "position:z", rp.z - float(data["lunge"]), 0.1)
	weapon_tween.tween_property(node, "rotation_degrees:x", rr.x, 0.25)
	weapon_tween.parallel().tween_property(node, "position:z", rp.z, 0.25)


# ---- стрельба (пистолет, ПП)

func _fire(data: Dictionary) -> void:
	if reloading:
		return
	var id := current_weapon
	if ammo_mag[id] <= 0:
		attack_cooldown = 0.3
		NoiseBus.emit(global_position, 3.0)  # сухой щелчок
		if ammo_reserve[id] > 0:
			_reload()
		return

	ammo_mag[id] -= 1
	attack_cooldown = data["cooldown"]
	_play_recoil(data)
	_flash()
	var kick := minf(deg_to_rad(float(data["kick"])), MAX_RECOIL - recoil_offset)
	if kick > 0.0:
		head.rotation.x = minf(head.rotation.x + kick, deg_to_rad(85.0))
		recoil_offset += kick
	recoil_timer = RECOIL_DELAY

	# пуля летит из центра камеры, с разбросом (в приседе он вдвое меньше)
	var cam_basis := camera.global_transform.basis
	var dir := -cam_basis.z
	var spread := deg_to_rad(float(data["spread"]))
	if crouching:
		spread *= 0.5
	if spread > 0.0:
		dir = dir.rotated(cam_basis.x, randf_range(-spread, spread))
		dir = dir.rotated(cam_basis.y, randf_range(-spread, spread))

	# маска: слой 1 (мир) + слой 3 (враги) = 1 | 4
	var from := camera.global_position
	var query := PhysicsRayQueryParameters3D.create(
		from, from + dir * RANGE, 1 | 4, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)

	if not hit.is_empty():
		var col: Object = hit.collider
		if col is Enemy:
			(col as Enemy).receive_shot(self, data["damage"])
		elif col is RigidBody3D:
			var rb := col as RigidBody3D
			rb.apply_impulse(dir * 3.0 * rb.mass, hit.position - rb.global_position)
		else:
			_spawn_bullet_mark(hit.position, hit.normal)

	# выстрел очень громкий: его слышат враги далеко вокруг
	NoiseBus.emit(global_position, data["noise"])
	_update_hud()


func _reload() -> void:
	var data: Dictionary = WEAPONS[current_weapon]
	if data["melee"] or reloading:
		return
	var id := current_weapon
	if ammo_mag[id] >= int(data["mag"]) or ammo_reserve[id] <= 0:
		return

	reloading = true
	reload_id += 1
	var my_id := reload_id
	NoiseBus.emit(global_position, 3.0)
	_play_reload_anim(data)
	_update_hud()

	await get_tree().create_timer(data["reload"]).timeout
	if my_id != reload_id:
		return  # отменено сменой оружия

	var take := mini(int(data["mag"]) - int(ammo_mag[id]), int(ammo_reserve[id]))
	ammo_mag[id] += take
	ammo_reserve[id] -= take
	reloading = false
	_update_hud()


## Прицел плавно возвращается туда, где был до стрельбы.
func _update_recoil(delta: float) -> void:
	recoil_timer -= delta
	if recoil_offset <= 0.0 or recoil_timer > 0.0:
		return
	var step := maxf(recoil_offset * RECOIL_RECOVERY * delta, deg_to_rad(4.0) * delta)
	step = minf(step, recoil_offset)
	head.rotation.x -= step
	recoil_offset -= step


func _play_recoil(data: Dictionary) -> void:
	var node: Node3D = weapon_nodes.get(current_weapon)
	if node == null:
		return
	var rp: Vector3 = rest_pos[current_weapon]
	var rr: Vector3 = rest_rot[current_weapon]
	if weapon_tween:
		weapon_tween.kill()
	weapon_tween = create_tween()
	weapon_tween.tween_property(node, "position", rp + Vector3(0.0, 0.02, 0.1), 0.04)
	weapon_tween.parallel().tween_property(
		node, "rotation_degrees:x", rr.x + float(data["recoil"]), 0.04)
	weapon_tween.tween_property(node, "position", rp, 0.1)
	weapon_tween.parallel().tween_property(node, "rotation_degrees:x", rr.x, 0.1)


func _play_reload_anim(data: Dictionary) -> void:
	var node: Node3D = weapon_nodes.get(current_weapon)
	if node == null:
		return
	var rr: Vector3 = rest_rot[current_weapon]
	if weapon_tween:
		weapon_tween.kill()
	weapon_tween = create_tween()
	weapon_tween.tween_property(node, "rotation_degrees:x", rr.x - 50.0, 0.25)
	weapon_tween.tween_interval(maxf(float(data["reload"]) - 0.55, 0.0))
	weapon_tween.tween_property(node, "rotation_degrees:x", rr.x, 0.3)


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
	await get_tree().create_timer(5.0).timeout
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

## Прицел и текст со здоровьем, оружием и патронами создаются прямо в коде.
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
	var text := "HP: %d" % int(health)

	# список доступного оружия, текущее в скобках
	var slots: PackedStringArray = []
	for i in ORDER.size():
		var id: String = ORDER[i]
		if not weapon_nodes.has(id):
			continue
		var slot := "%d %s" % [i + 1, WEAPONS[id]["name"]]
		if id == current_weapon:
			slot = "[" + slot + "]"
		slots.append(slot)
	if not slots.is_empty():
		text += "\n" + "   ".join(slots)

	var data: Dictionary = WEAPONS[current_weapon]
	if not data["melee"]:
		text += "\nAmmo: %d / %d" % [ammo_mag[current_weapon], ammo_reserve[current_weapon]]
		if reloading:
			text += "  (reloading...)"
	hud_label.text = text


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
		"prone": KEY_Z,
		"jump": KEY_SPACE,
		"lean_left": KEY_Q,
		"lean_right": KEY_E,
		"reload": KEY_R,
		"weapon_1": KEY_1,
		"weapon_2": KEY_2,
		"weapon_3": KEY_3,
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
