	using Godot;

public partial class DamageFlash : Control
{
	[Export] public HealthComponent Health { get; set; }
	[Export] public ColorRect Overlay { get; set; }
	[Export] public float BaseAlpha { get; set; } = 0.4f;
	[Export] public float BaseDuration { get; set; } = 0.3f;
	[Export] public float BaseMultiplier { get; set; } = 1f;
	[Export] public float CriticalHealthThreshold { get; set; } = 50f;
	[Export] public float CriticalHealthMultiplier { get; set; } = 2f;

	private int _lastHealth;
	private Tween _tween;

	public override void _Ready()
	{
		Overlay ??= GetNode<ColorRect>("Overlay");
		if (Overlay == null) return;

		SetAlpha(0f);

		Health ??= GetTree().GetFirstNodeInGroup("player")?.FindChild("HealthComponent") as HealthComponent;
		if (Health == null) return;

		_lastHealth = Health.CurrentHealth;
		Health.HealthChanged += OnHealthChanged;
	}

	public override void _ExitTree()
	{
		if (IsInstanceValid(Health))
			Health.HealthChanged -= OnHealthChanged;
	}

	private void OnHealthChanged(int current, int max)
	{
		if (current < _lastHealth)
		{
			var mul = GetFlashMultiplier(current, _lastHealth, max);
			Flash(mul);
		}

		_lastHealth = current;
	}

	private void Flash(float multiplier = 1f)
	{
		_tween?.Kill();

		var alpha = BaseAlpha * multiplier;
		var duration = BaseDuration * multiplier;

		SetAlpha(alpha);

		_tween = CreateTween();
		_tween.TweenMethod(Callable.From<float>(SetAlpha), alpha, 0f, duration)
					.SetTrans(Tween.TransitionType.Quad)
					.SetEase(Tween.EaseType.Out);
	}

	private float GetFlashMultiplier(int currentHealth, int lastHealth, int maxHealth)
	{
		var delta = lastHealth - currentHealth;
		var criticality = BaseMultiplier * (float)delta / maxHealth;

		if(currentHealth <= CriticalHealthThreshold)
		{
			criticality *= CriticalHealthMultiplier; 
		}

		return 1 + criticality;
	}

	private void SetAlpha(float a)
	{
		var c = Overlay.Color;
		c.A = a;
		Overlay.Color = c;
	}
}