namespace Parrat.Core.Models;

public class SiteCodingRule
{
    public string Code { get; set; } = string.Empty;
    public bool Enabled { get; set; } = true;
    public int Priority { get; set; }
    public string Logic { get; set; } = "AND";
    public List<ExpressionItem> Expression { get; set; } = new();
    public string? ForceLaterality { get; set; }
}

public class ExpressionItem
{
    public string Type { get; set; } = string.Empty; // "term", "group", or "topo-template"
    public string? Value { get; set; }               // for "term" type
    public List<string>? Terms { get; set; }          // for "group" type
    public string? Logic { get; set; }                // for "group" type ("AND" or "OR")
    public string? Template { get; set; }             // for "topo-template" type
}
