using System.Text.Json.Serialization;

namespace Parat.Core.Models;

/// <summary>
/// Persisted grid column configuration for the navigation grid.
/// Stored in config/grid-settings.json.
/// </summary>
public class GridSettings
{
    public int Version { get; set; } = 1;
    public GridColumnsConfig Xml { get; set; } = new();
    public GridColumnsConfig Hl7 { get; set; } = new();
    public PanelLayout Layout { get; set; } = new();
}

/// <summary>
/// Saved splitter positions for the 3-panel layout.
/// Values are percentages (0.0 to 1.0) of the parent container width.
/// -1 means use default.
/// </summary>
public class PanelLayout
{
    /// <summary>Outer splitter: grid panel vs content panels.</summary>
    public double OuterSplitRatio { get; set; } = -1;

    /// <summary>Inner splitter: path text panel vs items panel.</summary>
    public double InnerSplitRatio { get; set; } = -1;
}

/// <summary>
/// Column configuration for a specific file type (XML or HL7).
/// </summary>
public class GridColumnsConfig
{
    /// <summary>
    /// Ordered list of columns to display. Order determines display order.
    /// </summary>
    public List<GridColumnDef> Columns { get; set; } = new();
}

/// <summary>
/// Definition for a single grid column.
/// </summary>
public class GridColumnDef
{
    /// <summary>The NAACCR xmlId (for XML) or field key (for HL7).</summary>
    public string Id { get; set; } = string.Empty;

    /// <summary>Display width in pixels. -1 means auto-size.</summary>
    public int Width { get; set; } = -1;
}
