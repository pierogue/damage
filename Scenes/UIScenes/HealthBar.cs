using Godot;
using System;

public partial class HealthBar : Control
{

	[Export] public HealthComponent HealthComponent { get; set; }
	[Export] public ProgressBar ProgressBar { get; set; }

	// Called when the node enters the scene tree for the first time.
	public override void _Ready()
	{
    var player = GetTree().GetFirstNodeInGroup("player") as Node;
    HealthComponent ??= player?.FindChild("HealthComponent") as HealthComponent;
		ProgressBar ??= FindChild("ProgressBar") as ProgressBar;

		if (HealthComponent == null) return;

		HealthComponent.HealthChanged += OnHealthChanged;
		OnHealthChanged(HealthComponent.CurrentHealth, HealthComponent.MaxHealth);

	}

	private void OnHealthChanged(int currentHealth, int maxHealth)
	{
		if (ProgressBar == null) return;

		ProgressBar.MaxValue = maxHealth;
		ProgressBar.Value = currentHealth;
	}
}
