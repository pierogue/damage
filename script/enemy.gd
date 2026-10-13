class_name Enemy
extends CharacterBody3D
## Враг со стелс-ИИ: зрение, слух, шкала подозрения, патруль, поиск, погоня.
##
## Дерево сцены:
## Enemy (CharacterBody3D, этот скрипт, группа "enemy" добавится сама)
## ├─ CollisionShape3D (CapsuleShape3D: radius 0.4, height 1.8, position.y = 0.9)
## ├─ MeshInstance3D (CapsuleMesh, position.y = 0.9)
## ├─ Eye (Node3D, position.y = 1.6)    <- глаза, смотрят в -Z
## ├─ NavigationAgent3D
## └─ Label3D                           <- индикатор "? / !" над головой

enum State { PATROL, SUSPICIOUS, SEARCH, CHASE, DEAD }

@export var patrol_points: Array[Node3D] = []
@export var view_distance := 15.0
@export var view_half_angle := 55.0     # градусы, половина конуса зрения
@export var walk_speed := 2.0
@export var chase_speed := 4.5
@export var turn_speed := 6.0
@export var attack_range := 1.6
@export var attack_damage := 20.0
@export var max_health := 100.0
@export var bat_damage := 50.0          # урон от обычного удара (не со спины)
@export var hearing_multiplier := 1.0   # >1 = чуткий слух
@export var wait_time := 1.5            # пауза на точке патруля
@export var search_time := 5.0          # сколько осматривается на месте шума

@onready var eye: Node3D = $Eye
@onready var agent: NavigationAgent3D = $NavigationAgent3D
@onready var label: Label3D = $Label3D

var state := State.PATROL
var awareness := 0.0                    # 0..1, шкала подозрения
var sees_player := false
var last_known_position := Vector3.ZERO
var health: float
var player: Player

var patrol_index := 0
var wait_timer := 0.0
var search_timer := 0.0
var attack_cooldown := 0.0
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _ready() -> void:
	add_to_group("enemy")
	health = max_health
	NoiseBus.noise_made.connect(_on_noise)

	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.pixel_size = 0.01
	label.font_size = 48
	label.position.y = 2.3
	label.hide()


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	if not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as Player
		if player == null:
			return

	attack_cooldown = maxf(attack_cooldown - delta, 0.0)
	sees_player = can_see_player()
	_update_awareness(delta)
	_update_state()

	match state:
		State.PATROL: _do_patrol(delta)
		State.SUSPICIOUS: _do_suspicious(delta)
		State.SEARCH: _do_search(delta)
		State.CHASE: _do_chase(delta)

	if not is_on_floor():
		velocity.y -= gravity * delta
	move_and_slide()
	_update_label()


# ---------------------------------------------------------------- зрение

func can_see_player() -> bool:
	var target := player.get_aim_point()
	var to_player := target - eye.global_position
	var dist := to_player.length()

	# 1. дальность (присел или стоит на месте = виден хуже)
	if dist > view_distance * player.visibility_multiplier:
		return false

	# 2. конус зрения
	var forward := -eye.global_transform.basis.z
	if rad_to_deg(forward.angle_to(to_player)) > view_half_angle:
		return false

	# 3. прямая видимость (стены закрывают); маска: слой 1 (мир) + слой 2 (игрок)
	var query := PhysicsRayQueryParameters3D.create(
		eye.global_position, target, 1 | 2, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit.collider == player


# ---------------------------------------------------------------- подозрение

func _update_awareness(delta: float) -> void:
	if sees_player:
		var dist := global_position.distance_to(player.global_position)
		var closeness := 1.0 - clampf(dist / view_distance, 0.0, 1.0)
		awareness += delta * lerpf(0.4, 2.5, closeness)  # ближе = заметил быстрее
		last_known_position = player.global_position
	else:
		awareness -= delta * 0.15
	awareness = clampf(awareness, 0.0, 1.0)


func _update_state() -> void:
	match state:
		State.PATROL:
			if awareness >= 1.0:
				_set_state(State.CHASE)
			elif awareness >= 0.3:
				_set_state(State.SUSPICIOUS)
		State.SUSPICIOUS:
			if awareness >= 1.0:
				_set_state(State.CHASE)
			elif awareness <= 0.05:
				_set_state(State.PATROL)
		State.SEARCH:
			if awareness >= 1.0:
				_set_state(State.CHASE)
			elif search_timer <= 0.0:
				_set_state(State.PATROL)
		State.CHASE:
			if not sees_player and awareness < 0.5:
				_set_state(State.SEARCH)


func _set_state(new_state: State) -> void:
	if state == new_state:
		return
	state = new_state
	if new_state == State.SEARCH:
		search_timer = search_time
	elif new_state == State.PATROL:
		awareness = 0.0


# ---------------------------------------------------------------- слух

func _on_noise(pos: Vector3, loudness: float) -> void:
	if state == State.DEAD or state == State.CHASE:
		return
	if global_position.distance_to(pos) > loudness * hearing_multiplier:
		return
	last_known_position = pos
	awareness = maxf(awareness, 0.5)
	_set_state(State.SEARCH)
	search_timer = search_time


# ---------------------------------------------------------------- поведение

func _do_patrol(delta: float) -> void:
	if patrol_points.is_empty():
		_stop(delta)
		return
	if wait_timer > 0.0:
		wait_timer -= delta
		_stop(delta)
		return
	var target := patrol_points[patrol_index].global_position
	if _move_towards(target, walk_speed, delta):
		wait_timer = wait_time
		patrol_index = (patrol_index + 1) % patrol_points.size()


func _do_suspicious(delta: float) -> void:
	_stop(delta)
	var dir := last_known_position - global_position
	dir.y = 0.0
	_face(dir.normalized(), delta)


func _do_search(delta: float) -> void:
	if _move_towards(last_known_position, walk_speed * 1.3, delta):
		search_timer -= delta
		# осматривается по сторонам
		rotation.y += sin(Time.get_ticks_msec() / 1000.0 * 2.0) * 1.5 * delta


func _do_chase(delta: float) -> void:
	var dist := global_position.distance_to(player.global_position)
	if sees_player and dist <= attack_range:
		_stop(delta)
		var dir := player.global_position - global_position
		dir.y = 0.0
		_face(dir.normalized(), delta)
		if attack_cooldown <= 0.0:
			attack_cooldown = 1.2
			player.take_damage(attack_damage)
	else:
		_move_towards(last_known_position, chase_speed, delta)


# ---------------------------------------------------------------- движение

## Возвращает true, когда враг дошёл до цели.
func _move_towards(target: Vector3, speed: float, delta: float) -> bool:
	if agent.target_position.distance_to(target) > 0.3:
		agent.target_position = target
	if agent.is_navigation_finished():
		_stop(delta)
		return true
	var dir := agent.get_next_path_position() - global_position
	dir.y = 0.0
	dir = dir.normalized()
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	_face(dir, delta)
	return false


func _stop(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 20.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 20.0 * delta)


func _face(dir: Vector3, delta: float) -> void:
	if dir.length() < 0.01:
		return
	var target_yaw := atan2(-dir.x, -dir.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, clampf(turn_speed * delta, 0.0, 1.0))


# ---------------------------------------------------------------- удар битой

## Совместимость со старым кодом: удар битой.
func receive_bat_hit(attacker: Player) -> float:
	return receive_melee_hit(attacker, bat_damage, 12.0, 3.0)


## Вызывается игроком при ударе холодным оружием (бита, финка).
## Возвращает громкость шума: hit_noise за обычный удар, kill_noise за убийство.
func receive_melee_hit(attacker: Player, damage: float, hit_noise: float, kill_noise: float) -> float:
	if state == State.DEAD:
		return 0.0

	var to_attacker := attacker.global_position - global_position
	to_attacker.y = 0.0
	var forward := -global_transform.basis.z
	var from_behind := forward.dot(to_attacker.normalized()) < -0.3

	# убийство со спины: тихо и сразу, если враг не в погоне
	if from_behind and state != State.CHASE:
		_die()
		return kill_noise

	health -= damage
	if health <= 0.0:
		_die()
		return hit_noise

	# выжил: сразу знает, где игрок
	last_known_position = attacker.global_position
	awareness = 1.0
	_set_state(State.CHASE)
	return hit_noise


## Вызывается игроком при попадании из пистолета.
func receive_shot(attacker: Player, damage: float) -> void:
	if state == State.DEAD:
		return
	health -= damage
	if health <= 0.0:
		_die()
		return
	# выжил: сразу знает, где игрок
	last_known_position = attacker.global_position
	awareness = 1.0
	_set_state(State.CHASE)


func _die() -> void:
	state = State.DEAD
	label.hide()
	remove_from_group("enemy")
	collision_layer = 0
	collision_mask = 0
	var t := create_tween()
	t.tween_property(self, "rotation_degrees:x", -90.0, 0.4).set_trans(Tween.TRANS_QUAD)


# ---------------------------------------------------------------- индикатор

func _update_label() -> void:
	var symbol := ""
	var color := Color.WHITE
	match state:
		State.PATROL:
			if awareness > 0.02:
				symbol = "..."
		State.SUSPICIOUS:
			symbol = "?"
			color = Color.YELLOW
		State.SEARCH:
			symbol = "?"
			color = Color.ORANGE
		State.CHASE:
			symbol = "!"
			color = Color.RED
	label.visible = symbol != ""
	label.text = "%s %d%%" % [symbol, int(awareness * 100.0)]
	label.modulate = color
