namespace Parrat.Core.Models;

public class DiffLine
{
    public int? LineNumA { get; set; }
    public int? LineNumB { get; set; }
    public DiffStatus Status { get; set; }
    public string ContentA { get; set; } = string.Empty;
    public string ContentB { get; set; } = string.Empty;
}

public enum DiffStatus
{
    Unchanged,
    Added,
    Deleted
}
