using Godot;
using System;

public partial class Enemy : CharacterBody3D
{
	[Export] public float WalkSpeed = 2.0f;
	[Export] public float ChaseSpeed = 4.0f;

	[Export] public VisionComponent Vision { get; set; }
	[Export] public HealthComponent Health { get; set; }
	[Export] public PatrolBehavior PatrolBehavior { get; set; }
	[Export] public PatrolRoute PatrolRoute { get; set; }

	private float _gravity = (float)ProjectSettings.GetSetting("physics/3d/default_gravity");

	public override void _Ready()
	{
		Vision ??= GetNode<VisionComponent>("VisionComponent");
		Health ??= GetNode<HealthComponent>("HealthComponent");

		if (Vision != null)
		{
			Vision.TargetSeen += OnTargetSeen;
			Vision.TargetLost += OnTargetLost;
		}

		if (Health != null)
		{
			Health.Died += OnDied;
		}
	}

	public override void _EnterTree()
	{
		PatrolBehavior ??= GetNode<PatrolBehavior>("PatrolBehavior");
		if (PatrolBehavior != null)
		{
			PatrolBehavior.PatrolRoute = PatrolRoute;
		}
	}


	private void OnTargetSeen(Node3D target)
	{
		// Implement behavior when the enemy sees the target
		GD.Print($"Enemy has seen the target: {target.Name}");
	}

	private void OnTargetLost(Node3D target)
	{
		// Implement behavior when the enemy loses sight of the target
		GD.Print($"Enemy has lost sight of the target: {target.Name}");
	}

	private void OnDied()
	{
		// Implement behavior when the enemy dies
		GD.Print("Enemy has died.");
	}

	public override void _PhysicsProcess(double delta)
	{
		// If patrol beahavior assigned do patroling
		if(PatrolBehavior != null) PatrolBehavior.Tick(delta);

		if (!IsOnFloor())
				Velocity = Velocity with { Y = Velocity.Y - _gravity * (float)delta };

		MoveAndSlide();
	}
}
