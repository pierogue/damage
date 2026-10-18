using Godot;

[GlobalClass]
public partial class NavMover : Node
{
  [Export] public CharacterBody3D Body { get; set; }
  [Export] public NavigationAgent3D Agent { get; set; }
  [Export] public float TurnSpeed { get; set; } = 6f;
  [Export] public float Deceleration { get; set; } = 20f;

  private Vector3 _lastTarget = new(float.NaN, 0, 0);

  private const float moveThreshold = 0.3f;
  private const float faceThreshold = 0.01f;

  public override void _Ready()
  {
    Body ??= GetParent<CharacterBody3D>();
    Agent ??= Body.GetNode<NavigationAgent3D>("NavigationAgent3D");
  }

  public bool MoveTowards(Vector3 target, float speed, double delta)
  {
    if (float.IsNaN(_lastTarget.X) || _lastTarget.DistanceTo(target) > moveThreshold)
    {
      Agent.TargetPosition = target;
      _lastTarget = target;
    }

    if (Agent.IsNavigationFinished())
    {
      Stop(delta);
      return true;
    }

    Vector3 dir = Agent.GetNextPathPosition() - Body.GlobalPosition;
    dir.Y = 0;
    dir = dir.Normalized();

    Body.Velocity = Body.Velocity with { X = dir.X * speed, Z = dir.Z * speed };
    Face(dir, delta);
    return false;
  }

  public void Stop(double delta)
  {
    float dt = (float)delta;
    Body.Velocity = Body.Velocity with
    {
      X = Mathf.MoveToward(Body.Velocity.X, 0, Deceleration * dt),
      Z = Mathf.MoveToward(Body.Velocity.Z, 0, Deceleration * dt)
    };
  }

  public void Face(Vector3 dir, double delta)
  {
    if (dir.Length() < faceThreshold) return;
    float targetYaw = Mathf.Atan2(-dir.X, -dir.Z);
    Body.Rotation = Body.Rotation with
    {
      Y = Mathf.LerpAngle(Body.Rotation.Y, targetYaw, Mathf.Clamp(TurnSpeed * (float)delta, 0, 1))
    };
  }
}