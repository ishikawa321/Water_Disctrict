using Avalonia;
using Avalonia.Controls;
using Avalonia.Layout;
using Avalonia.Media;

namespace WaterDistrict.Desktop.Views;

/// <summary>The mobile status palette, with a text label that also conveys the state.</summary>
public sealed class StatusBadge : Border
{
    public static readonly StyledProperty<string?> StatusProperty =
        AvaloniaProperty.Register<StatusBadge, string?>(nameof(Status));

    private readonly TextBlock label = new() { FontSize = 12, FontWeight = FontWeight.SemiBold, TextWrapping = TextWrapping.Wrap };
    public string? Status { get => GetValue(StatusProperty); set => SetValue(StatusProperty, value); }

    public StatusBadge()
    {
        Child = label;
        CornerRadius = new CornerRadius(12);
        Padding = new Thickness(10, 6);
        HorizontalAlignment = HorizontalAlignment.Left;
        Update();
    }

    protected override void OnPropertyChanged(AvaloniaPropertyChangedEventArgs change)
    {
        base.OnPropertyChanged(change);
        if (change.Property == StatusProperty) Update();
    }

    private void Update()
    {
        var (foreground, background) = Status switch
        {
            "Paid" or "Resolved" or "Completed" or "Published" or "Active" or "Verified" => ("#176442", "#EAF1EE"),
            "Overdue" or "Service interruption" or "Rejected" => ("#A02C24", "#F6ECEB"),
            "Assigned" or "In progress" or "Under review" => ("#2563EB", "#EFF4FF"),
            _ => ("#78520A", "#F4EFE5")
        };
        label.Text = Status;
        label.Foreground = Brush.Parse(foreground);
        Background = Brush.Parse(background);
        IsVisible = !string.IsNullOrWhiteSpace(Status);
    }
}
