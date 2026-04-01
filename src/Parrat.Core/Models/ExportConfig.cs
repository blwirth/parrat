namespace Parrat.Core.Models;

public class ExportConfig
{
    public string Name { get; set; } = string.Empty;
    public int Version { get; set; } = 25;
    public List<ExportField> Fields { get; set; } = new();
    public string CreatedDate { get; set; } = string.Empty;
}

public class ExportField
{
    public string XmlId { get; set; } = string.Empty;
    public bool IsCustom { get; set; }
    public string? ParentElement { get; set; }
}
