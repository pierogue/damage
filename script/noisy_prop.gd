extends RigidBody3D
## Предмет, который шумит при ударе о что-то (бутылка, ящик, ведро).
## Игрок может ударить по нему битой и отвлечь врагов.

@export var min_speed := 2.5   # ниже этой скорости не шумит

var prev_speed := 0.0
var cooldown := 0.0


func _ready() -> void:
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	cooldown = maxf(cooldown - delta, 0.0)
	prev_speed = linear_velocity.length()


func _on_body_entered(_body: Node) -> void:
	if cooldown > 0.0 or prev_speed < min_speed:
		return
	cooldown = 0.3
	NoiseBus.EmitNoise(global_position, clampf(prev_speed * 2.5, 3.0, 14.0))
