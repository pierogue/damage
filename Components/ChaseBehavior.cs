using Godot;
using System;

[GlobalClass]
public partial class ChaseBehavior : Node
{
  [Signal] public delegate void InAttackRangeEventHandler();
  [Signal] public delegate void OutAttackRangeEventHandler();
  [Signal] public delegate void ReachedLastKnownEventHandler();

  [Export] public Node3D Target { get; set; }
  [Export] public float ChaseSpeed { get; set; } = 3.0f;
  [Export] public NavMover Mover { get; set; }
  [Export] public float AttackRange { get; set; } = 1.5f;

  public Node3D Assignee { get; private set; }
  public Vector3 LastKnownPosition { get; private set; }

  public bool IsInAttackRange = false;

  public void SetLastKnown(Vector3 position) => LastKnownPosition = position;
  public override void _Ready()
  {
    Assignee = GetParent<CharacterBody3D>();
    Mover ??= Assignee?.GetNode<NavMover>("NavMover");
    Target ??= GetTree().GetFirstNodeInGroup("player") as Node3D;
  }

  public void Tick(double delta, bool seesTarget)
  {
    if (seesTarget && IsInstanceValid(Target))
    {
      LastKnownPosition = Target.GlobalPosition;

      float dist = Assignee.GlobalPosition.DistanceTo(Target.GlobalPosition);
      if (dist <= AttackRange)
      {
        Mover.Stop(delta);

        Vector3 dir = Target.GlobalPosition - Assignee.GlobalPosition;
        dir.Y = 0;
        Mover.Face(dir.Normalized(), delta);

        if (IsInAttackRange == false)
        {
          EmitSignal(SignalName.InAttackRange);
          IsInAttackRange = true;
        }
        return;
      }
      if (IsInAttackRange == true)
      {
        IsInAttackRange = false;
        EmitSignal(SignalName.OutAttackRange);
      }
    }

    if (Mover.MoveTowards(LastKnownPosition, ChaseSpeed, delta) && !seesTarget)
    {
      EmitSignal(SignalName.ReachedLastKnown);
    }
  }
}