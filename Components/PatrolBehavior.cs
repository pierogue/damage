using System.Collections.Generic;
using Godot;

[GlobalClass]
public partial class PatrolBehavior : Node3D
{
  [Export] public PatrolRoute PatrolRoute { get; set; }
  [Export] public NavMover NavMover { get; set; }
  [Export] public float PatrolSpeed { get; set; } = 2.0f;
  [Export] public float WaitTimeAtPoint { get; set; } = 1.0f;

  private CharacterBody3D _assignee => GetParent<CharacterBody3D>();
  private IReadOnlyList<Vector3> _points = System.Array.Empty<Vector3>();
  private int _currentPatrolIndex = 0;
  private float _waitTimer = 0.0f;
  private bool _isWaiting = false;

  public override void _Ready()
  {
    if (PatrolRoute == null)
    {
      GD.PrintErr("PatrolRoute is not assigned in PatrolBehavior.");
      return;
    }
    _points = PatrolRoute.GetPoints();

    if (_points == null || _points.Count == 0)
    {
      GD.PrintErr("No patrol points exist in the assigned PatrolRoute.");
      return;
    }

    _currentPatrolIndex = 0;
    _waitTimer = WaitTimeAtPoint;
    _isWaiting = true;
  }

  // public override void _PhysicsProcess(double delta)
  // {
  //   if (_points == null || _points.Count == 0) return;

  //   if (_isWaiting)
  //   {
  //     _waitTimer -= (float)delta;
  //     if (_waitTimer <= 0)
  //     {
  //       _isWaiting = false;
  //       _currentPatrolIndex = (_currentPatrolIndex + 1) % _points.Count;
  //     }
  //     return;
  //   }

  //   var targetPoint = _points[_currentPatrolIndex];
  //   var direction = (targetPoint - _assignee.GlobalPosition).Normalized();
  //   _assignee.Velocity = direction * PatrolSpeed;
  //   _assignee.MoveAndSlide();

  //   if (_assignee.GlobalPosition.DistanceTo(targetPoint) < 0.5f)
  //   {
  //     _isWaiting = true;
  //     _waitTimer = WaitTimeAtPoint;
  //   }
  // }

  public void Tick(double delta)
  {
    if (_points.Count == 0)
    {
      NavMover.Stop(delta);
      return;
    }

    if (_waitTimer > 0)
    {
      _waitTimer -= (float)delta;
      NavMover.Stop(delta);
      return;
    }

    if (NavMover.MoveTowards(_points[_currentPatrolIndex], PatrolSpeed, delta))
    {
      _waitTimer = WaitTimeAtPoint;
      _currentPatrolIndex = (_currentPatrolIndex + 1) % _points.Count;
    }
  }
}