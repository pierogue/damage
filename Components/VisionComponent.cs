using System;
using Godot;

[GlobalClass]
public partial class VisionComponent : Node3D
{
  [Signal] public delegate void TargetSeenEventHandler(Node3D target);
  [Signal] public delegate void TargetLostEventHandler(Node3D target);

  [Export] public float VisionRange { get; set; } = 100f;
  [Export] public float VisionAngle { get; set; } = 60f;
  [Export] public float CheckInterval { get; set; } = 0.1f;
  [Export] public Node3D Target { get; set; }
  [Export] public Node3D EyeNode { get; set; }


  public bool IsSeeing { get; private set; } = false;
  private float _visionHalfAngle => VisionAngle / 2f;
  private double _checkTimer;

  // ************************for debug purposes only*********************************
  [Export] public bool DrawDebug { get; set; } = false;
  private MeshInstance3D _debugCone;
  private Color IdleColor = new(1f, 1f, 0f, 0.2f);
  private Color AlertColor = new(1f, 0f, 0f, 0.35f);
  // ********************************************************************************

  public bool CanSee(Node3D target, Node3D eyeNode = null)
  {
    eyeNode ??= EyeNode ?? this;
    Vector3 toTarget = target.GlobalPosition - eyeNode.GlobalPosition;

    // Vector3 forward = -GlobalTransform.Basis.Z;
    Vector3 forward = -eyeNode.GlobalTransform.Basis.Z;

    if (toTarget.Length() > VisionRange) return false;
    if (Mathf.RadToDeg(forward.AngleTo(toTarget)) > _visionHalfAngle) return false;

    var ray = PhysicsRayQueryParameters3D.Create(eyeNode.GlobalPosition, target.GlobalPosition);
    // ray.Exclude = new Godot.Collections.Array<Rid> { this.GetRid() };

    var hit = GetWorld3D().DirectSpaceState.IntersectRay(ray);

    return hit.Count > 0 && hit["collider"].AsGodotObject() == target;
  }

  public override void _Ready()
  {
    var player = GetTree().GetFirstNodeInGroup("player") as Node3D;
    if (player != null) Target = player;

    if (DrawDebug) InstansiateDebugCone();
  }

  public override void _PhysicsProcess(double delta)
  {
    _checkTimer -= delta;
    if (_checkTimer > 0) return;
    _checkTimer = CheckInterval;

    if (!IsInstanceValid(Target)) return;

    bool sees = CanSee(Target, EyeNode);
    if (sees == IsSeeing) return;

    IsSeeing = sees;
    EmitSignal(sees ? SignalName.TargetSeen : SignalName.TargetLost, Target);
  }

  private void OnTargetSeenDebug(Node3D target)
  {
    if (IsSeeing)
    {
      _debugCone.MaterialOverride = new StandardMaterial3D
      {
        Transparency = BaseMaterial3D.TransparencyEnum.Alpha,
        AlbedoColor = AlertColor,
        CullMode = BaseMaterial3D.CullModeEnum.Disabled,
        ShadingMode = BaseMaterial3D.ShadingModeEnum.Unshaded
      };
    }
    else
    {
      _debugCone.MaterialOverride = new StandardMaterial3D
      {
        Transparency = BaseMaterial3D.TransparencyEnum.Alpha,
        AlbedoColor = IdleColor,
        CullMode = BaseMaterial3D.CullModeEnum.Disabled,
        ShadingMode = BaseMaterial3D.ShadingModeEnum.Unshaded
      };
    }
  }

  private void InstansiateDebugCone()
  {
    float radius = VisionRange * Mathf.Tan(Mathf.DegToRad(_visionHalfAngle));

    var mesh = new CylinderMesh
    {
      TopRadius = 0f,
      BottomRadius = radius,
      Height = VisionRange,
      RadialSegments = 32,
      Rings = 1
    };

    var _material = new StandardMaterial3D
    {
      Transparency = BaseMaterial3D.TransparencyEnum.Alpha,
      AlbedoColor = IdleColor,
      CullMode = BaseMaterial3D.CullModeEnum.Disabled,
      ShadingMode = BaseMaterial3D.ShadingModeEnum.Unshaded
    };

    var cone = new MeshInstance3D
    {
      Mesh = mesh,
      MaterialOverride = _material,
      Position = new Vector3(0, -VisionRange / 2f, 0),
    };

    var pivot = new Node3D { RotationDegrees = new Vector3(90f, 0f, 0f) };
    if (EyeNode != null) EyeNode.AddChild(pivot);
    else AddChild(pivot);

    pivot.AddChild(cone);

    _debugCone = cone;

    TargetSeen += OnTargetSeenDebug;
    TargetLost += OnTargetSeenDebug;
  }
}