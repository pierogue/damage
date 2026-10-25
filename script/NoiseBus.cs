using Godot;
using System;

public partial class NoiseBus : Node
{
	[Signal] public delegate void NoiseEmittedEventHandler(Vector3 position, float loudness);

	public static NoiseBus Instance { get; private set; }

	public override void _EnterTree() => Instance = this;

	public static void EmitNoise(Vector3 position, float loudness)
	{
		Instance?.EmitSignal(SignalName.NoiseEmitted, position, loudness);
	}
}
