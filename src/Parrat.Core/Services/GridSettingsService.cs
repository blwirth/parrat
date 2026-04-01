using System.Text.Json;
using Parrat.Core.Helpers;
using Parrat.Core.Interfaces;
using Parrat.Core.Models;

namespace Parrat.Core.Services;

public class GridSettingsService : IGridSettingsService
{
    private static readonly string SettingsFileName = "grid-settings.json";
    private static readonly JsonSerializerOptions JsonOpts = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = true
    };

    private string SettingsPath => PathHelper.GetConfigPath(SettingsFileName);

    public GridSettings Load()
    {
        try
        {
            var path = SettingsPath;
            if (!File.Exists(path))
                return CreateDefaults();

            var json = File.ReadAllText(path);
            var settings = JsonSerializer.Deserialize<GridSettings>(json, JsonOpts);

            if (settings == null)
                return CreateDefaults();

            // Validate and fix up
            if (!Validate(settings))
                return CreateDefaults();

            return settings;
        }
        catch
        {
            // Malformed JSON, permission error, etc. — fall back to defaults
            return CreateDefaults();
        }
    }

    public void Save(GridSettings settings)
    {
        try
        {
            PathHelper.EnsureDirectoryExists(PathHelper.ConfigDir);
            var json = JsonSerializer.Serialize(settings, JsonOpts);
            File.WriteAllText(SettingsPath, json);
        }
        catch
        {
            // Swallow — saving user prefs should never crash the app
        }
    }

    public GridColumnsConfig GetDefaultXmlColumns()
    {
        return new GridColumnsConfig
        {
            Columns = new List<GridColumnDef>
            {
                new() { Id = "nameLast", Width = -1 },
                new() { Id = "nameFirst", Width = -1 },
                new() { Id = "dateOfBirth", Width = -1 },
                new() { Id = "pathReportNumber1", Width = -1 },
                new() { Id = "primarySite", Width = -1 },
                new() { Id = "dateOfDiagnosis", Width = -1 },
            }
        };
    }

    public GridColumnsConfig GetDefaultHl7Columns()
    {
        return new GridColumnsConfig
        {
            Columns = new List<GridColumnDef>
            {
                new() { Id = "nameLast", Width = -1 },
                new() { Id = "nameFirst", Width = -1 },
                new() { Id = "dateOfBirth", Width = -1 },
                new() { Id = "patientId", Width = -1 },
                new() { Id = "messageType", Width = -1 },
                new() { Id = "orderDateTime", Width = -1 },
            }
        };
    }

    /// <summary>
    /// Validates that settings have the expected structure. Returns false if
    /// anything looks wrong (missing columns, unknown version, etc.).
    /// </summary>
    private bool Validate(GridSettings settings)
    {
        if (settings.Version != 1)
            return false;

        if (settings.Xml?.Columns == null || settings.Xml.Columns.Count == 0)
            return false;

        if (settings.Hl7?.Columns == null || settings.Hl7.Columns.Count == 0)
            return false;

        // Ensure all columns have a non-empty Id
        foreach (var col in settings.Xml.Columns)
            if (string.IsNullOrWhiteSpace(col.Id)) return false;

        foreach (var col in settings.Hl7.Columns)
            if (string.IsNullOrWhiteSpace(col.Id)) return false;

        return true;
    }

    private GridSettings CreateDefaults()
    {
        return new GridSettings
        {
            Version = 1,
            Xml = GetDefaultXmlColumns(),
            Hl7 = GetDefaultHl7Columns()
        };
    }
}
