using Godot;
using System;

public partial class Bullet : Area3D
{
    [Export] public float Speed { get; set; } = 25f;
    [Export] public int Damage { get; set; } = 10;
    [Export] public float Lifetime { get; set; } = 5f;

    private float _age;

    public override void _Ready()
    {
        BodyEntered += OnBodyEntered;
    }

    public override void _PhysicsProcess(double delta)
    {
        float dt = (float)delta;

        GlobalPosition += -GlobalTransform.Basis.Z * Speed * dt;

        _age += dt;
        if (_age >= Lifetime) QueueFree();
    }

    private void OnBodyEntered(Node3D body)
    {
        var bodyHealth = body.FindChild("HealthComponent") as HealthComponent;
        bodyHealth?.TakeDamage(Damage);

        QueueFree();
    }
}
