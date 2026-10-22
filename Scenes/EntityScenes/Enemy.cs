using Godot;
using System;

public partial class Enemy : CharacterBody3D
{
	public enum EnemyState { Patrol, Suspicious, Search, Chase, Fight, Dead }

	[Export] public VisionComponent Vision { get; set; }
	[Export] public HealthComponent Health { get; set; }
	[Export] public PatrolBehavior PatrolBehavior { get; set; }
	[Export] public ChaseBehavior ChaseBehavior { get; set; }
	[Export] public ShooterBehavior ShooterBehavior { get; set; }
	[Export] public MeleeAttackBehavior MeleeAttackBehavior { get; set; }
	[Export] public NavMover NavMover { get; set; }
	[Export] public PatrolRoute PatrolRoute { get; set; }

	[Export] public float SearchTime { get; set; } = 5f;

	public EnemyState CurrentState { get; private set; } = EnemyState.Patrol;

	private float _gravity = (float)ProjectSettings.GetSetting("physics/3d/default_gravity");
	private double _searchLeft;

	public override void _Ready()
	{
		Vision ??= GetNode<VisionComponent>("VisionComponent");
		Health ??= GetNode<HealthComponent>("HealthComponent");
		ChaseBehavior ??= GetNode<ChaseBehavior>("ChaseBehavior");
		ShooterBehavior ??= GetNode<ShooterBehavior>("ShooterBehavior");
		MeleeAttackBehavior ??= GetNode<MeleeAttackBehavior>("MeleeAttackBehavior");
		NavMover ??= GetNode<NavMover>("NavMover");

		if (Vision != null)
		{
			Vision.TargetSeen += OnTargetSeen;
			Vision.TargetLost += OnTargetLost;
		}

		if (Health != null)
		{
			Health.Died += OnDied;
		}

		if (ChaseBehavior != null)
		{
			ChaseBehavior.InAttackRange += OnInAttackRange;
			ChaseBehavior.ReachedLastKnown += OnReachLastKnown;
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

	public override void _PhysicsProcess(double delta)
	{
		NavMover.Stop(delta);
		RunState(delta);

		if (!IsOnFloor())
			Velocity = Velocity with { Y = Velocity.Y - _gravity * (float)delta };

		MoveAndSlide();
	}

	private void OnTargetSeen(Node3D target)
	{
		GD.Print($"Enemy has seen the target: {target.Name}");
		SetState(EnemyState.Chase);
		ShooterBehavior.isActive = true;
	}

	private void OnTargetLost(Node3D target)
	{
		GD.Print($"Enemy has lost sight of the target: {target.Name}");
		ShooterBehavior.isActive = false;
	}

	private void OnDied()
	{
		GD.Print("Enemy has died.");
	}

	private void OnReachLastKnown()
	{
		GD.Print("Enemy has reached last known target position.");
		SetState(EnemyState.Search);
	}

	private void OnInAttackRange()
	{
	}

	private void OnOutAttackRange()
	{
	}

	public void RunState(double delta)
	{
		switch (CurrentState)
		{
			case EnemyState.Patrol:
				PatrolBehavior.Tick(delta);
				break;
			case EnemyState.Suspicious:
				//to be implemented
				break;
			case EnemyState.Search:
				//to be implemented
				_searchLeft -= (float)delta;
				if (_searchLeft <= 0)
				{
					SetState(EnemyState.Patrol);
				}
				break;
			case EnemyState.Chase:
				ChaseBehavior.Tick(delta, Vision?.IsSeeing ?? false);
				if (ChaseBehavior.IsInAttackRange)
					MeleeAttackBehavior.InitiateAttack();
				break;
			case EnemyState.Dead:
				break;
		}
	}

	public void SetState(EnemyState nextState)
	{
		if (CurrentState == nextState) return;

		switch (nextState)
		{
			case EnemyState.Search:
				_searchLeft = SearchTime;
				break;
		}

		CurrentState = nextState;
	}
}
