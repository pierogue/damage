using Godot;
using System;

public partial class EnemyBehavior : CharacterBody3D
{
	[Export] public float Speed { get; set; } = 4.0f;
	[Export] public float AttackDist { get; set; } = 2.0f;

	public enum State { Idle, Chase, Attack }
	private State _currentState = State.Idle;

	private CharacterBody3D _targetPlayer = null;

	private NavigationAgent3D _navAgent;
	private RayCast3D _rayCast;

	public override void _Ready()
	{
		_navAgent = GetNode<NavigationAgent3D>("NavigationAgent3D");
		_rayCast = GetNode<RayCast3D>("RayCast3D");
	}

	public override void _PhysicsProcess(double delta)
	{
		switch (_currentState)
		{
			case State.Idle:
				ProcessIdleState();
				break;
			case State.Chase:
				ProcessChaseState(delta);
				break;
			case State.Attack:
				ProcessAttackState();
				break;
		}

		MoveAndSlide();
	}

	private void ProcessAttackState()
	{
		Velocity = Vector3.Zero;
		// MoveAndSlide();

		// Тут вызывается ваша анимация атаки
		GD.Print("Враг атакует!");

		// Если игрок успел отбежать — снова переходим в погоню
		if (_targetPlayer != null)
		{
			float dist = GlobalPosition.DistanceTo(_targetPlayer.GlobalPosition);
			if (dist > AttackDist)
			{
				_currentState = State.Chase;
			}
		}
	}

	private bool CanSeePlayer()
	{
		if (_targetPlayer == null) return false;

		_rayCast.LookAt(_targetPlayer.GlobalPosition, Vector3.Up);

		float distanceToPlayer = GlobalPosition.DistanceTo(_targetPlayer.GlobalPosition);

		_rayCast.TargetPosition = new Vector3(0, 0, -distanceToPlayer);
		_rayCast.ForceRaycastUpdate();

		var collider = _rayCast.GetCollider();
		// Проверяем, перекрывает ли стену луч
		if (_rayCast.IsColliding() && _rayCast.GetCollider() == _targetPlayer)
		{
			return true;
		}
		return false;
	}

	private void ProcessChaseState(double delta)
	{
		if (_targetPlayer == null || !CanSeePlayer())
		{
			_currentState = State.Idle;
			return;
		}

		// Проверяем дистанцию до игрока
		float dist = GlobalPosition.DistanceTo(_targetPlayer.GlobalPosition);
		if (dist <= AttackDist)
		{
			_currentState = State.Attack;
			return;
		}

		// Задаем цель для навигации
		_navAgent.TargetPosition = _targetPlayer.GlobalPosition;

		if (!_navAgent.IsNavigationFinished())
		{
			Vector3 nextPathPos = _navAgent.GetNextPathPosition();
			Vector3 direction = GlobalPosition.DirectionTo(nextPathPos);

			// Разворачиваем врага лицом к игроку (только по оси Y, чтобы он не наклонялся)
			Vector3 lookTarget = new Vector3(_targetPlayer.GlobalPosition.X, GlobalPosition.Y, _targetPlayer.GlobalPosition.Z);
			if (GlobalPosition.DistanceSquaredTo(lookTarget) > 0.001f)
			{
				LookAt(lookTarget, Vector3.Up);
			}

			Velocity = direction * Speed;
			// MoveAndSlide();
		}
	}


	private void ProcessIdleState()
	{
		Velocity = new Vector3(0, 0, Speed * 0.1f);
		// MoveAndSlide();

		if (_targetPlayer != null && CanSeePlayer())
		{
			_currentState = State.Chase;
		}
	}

	private void OnDetectionAreaBodyEntered(Node3D body)
	{
		if (body.IsInGroup("player") && body is CharacterBody3D player)
		{
			_targetPlayer = player;
		}
	}

	private void OnDetectionAreaBodyExited(Node3D body)
	{

		{
			_targetPlayer = null;
		}
	}

}
