using Godot;
using System;

[GlobalClass]
public partial class ShooterBehavior : Node3D
{
	[Export] public bool ShootingEnabled { get; set; } = true;
	[Export] public Node3D ShootingTarget { get; set; }
	[Export] public Node3D Muzzle { get; set; }
	[Export] public PackedScene BulletScene { get; set; }
	[Export] public VisionComponent Vision { get; set; }
	[Export] public float Cooldown { get; set; } = 2f;
	[Export] public bool isActive = false;
	[Export] public float ShootingRange = 100;
	[Export] public Vector3 AimOffset { get; set; } = new Vector3(0, 1f, 0);

	private double _timeLeft;

	// Called when the node enters the scene tree for the first time.
	public override void _Ready()
	{
		ShootingTarget ??= GetTree().GetFirstNodeInGroup("player") as Node3D;
		Vision ??= GetParent<CharacterBody3D>().GetNode("VisionComponent") as VisionComponent;
	}

	// Called every frame. 'delta' is the elapsed time since the previous frame.
	public override void _PhysicsProcess(double delta)
	{
		_timeLeft -= delta;
		if (!ShootingEnabled) return;
		if (!isActive) return;
		if (!IsInstanceValid(ShootingTarget)) return;
		if (_timeLeft > 0) return;

		Vector3 origin = (Muzzle ?? this).GlobalPosition;
		Vector3 aimPoint = ShootingTarget.GlobalPosition + AimOffset;

		if (origin.DistanceTo(aimPoint) > ShootingRange) return;

		Shoot(origin, aimPoint);
		_timeLeft = Cooldown;
	}

	public void Shoot(Vector3 origin, Vector3 aimPoint)
	{
		if (!ShootingEnabled) return;
		if (BulletScene == null) return;

		var bullet = BulletScene.Instantiate<Node3D>();

		GetTree().CurrentScene.AddChild(bullet);

		bullet.GlobalPosition = origin;
		bullet.LookAt(ShootingTarget.GlobalPosition, Vector3.Up);
		if (!origin.IsEqualApprox(aimPoint))
		{
			// Might be used in future if there will be any bug with shooting vertically
			// var up = Mathf.Abs((aimPoint - origin).Normalized().Y) > 0.99f
			// 		? Vector3.Right
			// 		: Vector3.Up;
			bullet.LookAt(aimPoint, Vector3.Up);
		}
	}
}
