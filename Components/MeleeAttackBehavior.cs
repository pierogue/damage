using Godot;

[GlobalClass]
public partial class MeleeAttackBehavior : Node
{
  [Signal] public delegate void WindUpStartedEventHandler();
  [Signal] public delegate void MeleeAttackPerformedEventHandler(float damage);

  [Export] public Node3D Target { get; set; }
  [Export] public float AttackRange { get; set; } = 2f;
  [Export] public int Damage { get; set; } = 10;
  [Export] public float Cooldown { get; set; } = 3f;
  [Export] public float WindUpTime { get; set; } = 1f;

  private Node3D Assignee;
  private float _windUpLeft;
  private float _cooldownLeft;
  private bool isAttacking = false;

  public override void _Ready()
  {
    Target ??= GetTree().GetFirstNodeInGroup("player") as Node3D;
    Assignee = GetParent<Node3D>();
  }

  public void InitiateAttack()
  {
    if (_cooldownLeft > 0) return;
    if (isAttacking) return;

    _windUpLeft = WindUpTime;
    EmitSignal(SignalName.WindUpStarted);
    isAttacking = true;

    GD.Print("Enemy melee attack wind-up started");
  }

  private bool RunAttack()
  {
    var origin = Assignee.GlobalPosition;
    var target = Target.GlobalPosition;
    bool targetHit = false;

    if (origin.DistanceTo(target) <= AttackRange)
    {
      var health = Target.GetNode<HealthComponent>("HealthComponent");
      health?.TakeDamage(Damage);
      targetHit = true;
    }

    EmitSignal(SignalName.MeleeAttackPerformed, Damage);

    isAttacking = false;
    GD.Print("Enemy has attacked");

    return targetHit;
  }

  public override void _Process(double delta)
  {

    if (isAttacking)
    {
      _windUpLeft -= (float)delta;

      if (_windUpLeft <= 0)
      {

        RunAttack();

        _cooldownLeft = Cooldown;
      }
    }
    else if (_cooldownLeft > 0)
    {
      _cooldownLeft -= (float)delta;
    }

  }

}