using Godot;
using System;

[GlobalClass]
public partial class ShooterBehavior : Node3D
{
	[Export] public Node3D ShootingTarget { get; set; }
	[Export] public Node3D Muzzle { get; set; }
	[Export] public PackedScene BulletScene { get; set; }
	[Export] public float Cooldown { get; set; } = 2f;
	[Export] public bool isActive = false;
	[Export] public float ShootingRange = 100;
	[Export] public Vector3 AimOffset { get; set; } = new Vector3(0, 1f, 0);

	private double _timeLeft;

	// check if enemy is visible to the shooter, if not, don't shoot
	private bool _isTargetVisible(Vector3 shooter, Vector3 target)
	{
		// Vector3 from = this.GlobalPosition;
		// Vector3 to = ShootingTarget.GlobalPosition + AimOffset;

		var rayQuery = PhysicsRayQueryParameters3D.Create(shooter, target);
		rayQuery.CollisionMask = 1 | 2;

		var hit = GetWorld3D().DirectSpaceState.IntersectRay(rayQuery);

		if (hit.Count == 0) return false;

		var collider = hit["collider"].AsGodotObject() as Node3D;
		return collider == ShootingTarget;
	}

	// Called when the node enters the scene tree for the first time.
	public override void _Ready()
	{
    ShootingTarget ??= GetTree().GetFirstNodeInGroup("player") as Node3D;
	}

	// Called every frame. 'delta' is the elapsed time since the previous frame.
	public override void _PhysicsProcess(double delta)
	{
		_timeLeft -= delta;

		if (!IsInstanceValid(ShootingTarget)) return;
		if (_timeLeft > 0) return;

		Vector3 origin = (Muzzle ?? this).GlobalPosition;
		Vector3 aimPoint = ShootingTarget.GlobalPosition + AimOffset;

		if (origin.DistanceTo(aimPoint) > ShootingRange) return;
		if (!_isTargetVisible(origin, -this.GlobalTransform.Basis.Z * ShootingRange)) return;

		// if (!_isTargetVisible(origin, aimPoint)) return;

		_shoot(origin, aimPoint);
		_timeLeft = Cooldown;
	}

	public void _shoot(Vector3 origin, Vector3 aimPoint)
	{
		if (BulletScene == null) return;

		var bullet = BulletScene.Instantiate<Node3D>();

		GetTree().CurrentScene.AddChild(bullet);

		bullet.GlobalPosition = origin;
		bullet.LookAt(ShootingTarget.GlobalPosition, Vector3.Up);
		if (!origin.IsEqualApprox(aimPoint))
		{
			// var up = Mathf.Abs((aimPoint - origin).Normalized().Y) > 0.99f
			// 		? Vector3.Right
			// 		: Vector3.Up;
			bullet.LookAt(aimPoint, Vector3.Up);
		}
	}
}
