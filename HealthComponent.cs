using Godot;
using System;

public partial class HealthComponent : Node
{

	[Export] public int MaxHealth { get; set; } = 100;
	[Export] public int CurrentHealth { get; set; } = 100;
	[Export] public bool IsInvincible { get; set; } = false;
	[Export] public bool ShowInterface { get; set; } = false;

	[Signal] public delegate void HealthChangedEventHandler(int currentHealth, int maxHealth);
	[Signal] public delegate void DiedEventHandler();

	// Called when the node enters the scene tree for the first time.
	public override void _Ready()
	{
	}

	// Called every frame. 'delta' is the elapsed time since the previous frame.
	public override void _Process(double delta)
	{
	}

	public void TakeDamage(int damage)
	{
		if (IsInvincible) return;

		CurrentHealth -= damage;
		EmitSignal(SignalName.HealthChanged, CurrentHealth, MaxHealth);

		if (CurrentHealth <= 0)
		{
			CurrentHealth = 0;
			Die();
		}
	}

	private void Die()
	{
		EmitSignal(SignalName.Died);
		QueueFree();
	}
}
