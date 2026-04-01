using Parrat.Core.Models;

namespace Parrat.Core.Interfaces;

public interface IGridSettingsService
{
    /// <summary>Load settings from disk. Returns defaults if file missing or malformed.</summary>
    GridSettings Load();

    /// <summary>Save settings to disk.</summary>
    void Save(GridSettings settings);

    /// <summary>Get default XML grid columns.</summary>
    GridColumnsConfig GetDefaultXmlColumns();

    /// <summary>Get default HL7 grid columns.</summary>
    GridColumnsConfig GetDefaultHl7Columns();
}
