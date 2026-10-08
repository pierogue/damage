using Godot;
using System;

public partial class SwordControls : Node3D
{
	[Export] AnimationPlayer AnimationPlayer;

	// Called when the node enters the scene tree for the first time.
	public override void _Ready()
	{
	}

	public override void _Input(InputEvent @event)
	{
		if (@event is InputEventMouseButton mouseButton)
		{
			if (mouseButton.ButtonIndex is MouseButton.Left)
			{
				AnimationPlayer.Play("sword_slash_1");
			}
		}
	}

	// Called every frame. 'delta' is the elapsed time since the previous frame.
	public override void _Process(double delta)
	{
	}
}
