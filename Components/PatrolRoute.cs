using Godot;
using System.Collections.Generic;

[GlobalClass]
public partial class PatrolRoute : Node3D
{
  // [Export] public bool PingPong { get; set; } = false;

  public IReadOnlyList<Vector3> GetPoints()
  {
    var points = new List<Vector3>();
    foreach (var child in GetChildren())
      if (child is Marker3D m)
        points.Add(m.GlobalPosition);
    return points;
  }
}