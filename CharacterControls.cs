using Godot;
using System;

public partial class CharacterControls : CharacterBody3D
{
	public const float Speed = 5.0f;
	public const float JumpVelocity = 4.5f;
	[Export] public float MouseSensivity = 0.002f;
	[Export] public float MinPitch = -90f;
	[Export] public float MaxPitch = 90f;
	private float _rotationX = 0.0f;
	private float _rotationY = 0.0f;

	public override void _Ready()
	{
		Input.SetMouseMode(Input.MouseModeEnum.Captured);
	}

	public override void _Input(InputEvent @event)
	{
		if (@event is InputEventMouseMotion mouseMotion)
		{
			_rotationY -= mouseMotion.Relative.X * MouseSensivity;
			_rotationX -= mouseMotion.Relative.Y * MouseSensivity;

			float minRad = Mathf.DegToRad(MinPitch);
			float maxRad = Mathf.DegToRad(MaxPitch);

			_rotationX = Mathf.Clamp(_rotationX, minRad, maxRad);

			Transform3D t = Transform;
			t.Basis = Basis.Identity;
			Transform = t;

			RotateObjectLocal(Vector3.Up, _rotationY);
			RotateObjectLocal(Vector3.Right, _rotationX);
		}
	}

	public override void _Process(double delta)
	{
		// Возврат мыши по нажатию Esc
		if (Input.IsActionJustPressed("ui_cancel"))
		{
			if (Input.GetMouseMode() == Input.MouseModeEnum.Captured)
				Input.SetMouseMode(Input.MouseModeEnum.Visible);
			else
				Input.SetMouseMode(Input.MouseModeEnum.Captured);
		}
	}


	public override void _PhysicsProcess(double delta)
	{
		Vector3 velocity = Velocity;

		// Add the gravity.
		if (!IsOnFloor())
		{
		velocity += GetGravity() * (float)delta;
		}

		// Handle Jump.
		if (Input.IsActionJustPressed("ui_accept") && IsOnFloor())
		{
			velocity.Y = JumpVelocity;
		}

		// Get the input direction and handle the movement/deceleration.
		// As good practice, you should replace UI actions with custom gameplay actions.
		Vector2 inputDir = Input.GetVector("ui_left", "ui_right", "ui_up", "ui_down");
		// Vector2 inputDir = Input.GetVector("A", "D", "W", "S");
		Vector3 direction = (Transform.Basis * new Vector3(inputDir.X, 0, inputDir.Y)).Normalized();
		if (direction != Vector3.Zero)
		{
			velocity.X = direction.X * Speed;
			velocity.Z = direction.Z * Speed;
		}
		else
		{
			velocity.X = Mathf.MoveToward(Velocity.X, 0, Speed);
			velocity.Z = Mathf.MoveToward(Velocity.Z, 0, Speed);
		}

		Velocity = velocity;
		MoveAndSlide();
	}
}
