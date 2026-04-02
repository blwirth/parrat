using System.Text.Json;
using System.Text.RegularExpressions;
using Parrat.Core.Helpers;
using Parrat.Core.Interfaces;
using Parrat.Core.Models;

namespace Parrat.Core.Services;

public partial class ConfigService : IConfigService
{
    private readonly IParratLogger _logger;

    public ConfigService() : this(NullParratLogger.Instance) { }

    public ConfigService(IParratLogger logger)
    {
        _logger = logger;
    }

    private static readonly JsonSerializerOptions JsonWriteOptions = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };

    private static readonly JsonSerializerOptions JsonReadOptions = new()
    {
        PropertyNameCaseInsensitive = true
    };

    [GeneratedRegex(@"[^\w\-]")]
    private static partial Regex SafeNamePattern();

    // ─── Export Configs ──────────────────────────────────────────

    public string GetExportConfigPath()
    {
        var path = PathHelper.ExportConfigDir;
        PathHelper.EnsureDirectoryExists(path);
        return path;
    }

    public List<ExportField> GetDefaultFieldList()
    {
        return new List<ExportField>
        {
            new() { XmlId = "patientIdNumber", IsCustom = false },
            new() { XmlId = "nameLast", IsCustom = false },
            new() { XmlId = "nameFirst", IsCustom = false },
            new() { XmlId = "nameMiddle", IsCustom = false },
            new() { XmlId = "dateOfBirth", IsCustom = false },
            new() { XmlId = "reportingFacility", IsCustom = false },
            new() { XmlId = "dateOfDiagnosis", IsCustom = false },
            new() { XmlId = "pathReportNumber1", IsCustom = false },
            new() { XmlId = "primarySite", IsCustom = false },
            new() { XmlId = "histologicTypeIcdO3", IsCustom = false },
            new() { XmlId = "behaviorCodeIcdO3", IsCustom = false }
        };
    }

    public ExportConfig NewExportConfig(string? name = null, List<ExportField>? fields = null, int version = 25)
    {
        return new ExportConfig
        {
            Name = name ?? "Unnamed Configuration",
            Version = version,
            Fields = fields ?? new List<ExportField>(),
            CreatedDate = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss")
        };
    }

    public (bool Success, string Path, string Message) SaveExportConfig(ExportConfig config, string? fileName = null, string? path = null)
    {
        try
        {
            path ??= GetExportConfigPath();

            if (string.IsNullOrWhiteSpace(fileName))
            {
                var safeName = SafeNamePattern().Replace(config.Name, "_");
                fileName = $"{safeName}.json";
            }

            if (!fileName.EndsWith(".json", StringComparison.OrdinalIgnoreCase))
            {
                fileName = $"{fileName}.json";
            }

            var fullPath = System.IO.Path.Combine(path, fileName);

            var json = JsonSerializer.Serialize(config, JsonWriteOptions);
            File.WriteAllText(fullPath, json, System.Text.Encoding.UTF8);

            return (true, fullPath, "Configuration saved successfully");
        }
        catch (Exception ex)
        {
            _logger.LogError("Failed to save export configuration", "CONFIG_SAVE", ex);
            return (false, string.Empty, $"Error saving configuration: {ex.Message}");
        }
    }

    public ExportConfig GetExportConfig(string filePath)
    {
        if (!File.Exists(filePath))
        {
            throw new FileNotFoundException($"Configuration file not found: {filePath}");
        }

        var jsonContent = File.ReadAllText(filePath, System.Text.Encoding.UTF8);
        var config = JsonSerializer.Deserialize<ExportConfig>(jsonContent, JsonReadOptions);

        return config ?? throw new InvalidOperationException("Failed to deserialize export config");
    }

    public List<(string Name, string Path)> GetAvailableExportConfigs()
    {
        var configPath = GetExportConfigPath();
        var results = new List<(string Name, string Path)>();

        if (!Directory.Exists(configPath)) return results;

        foreach (var file in Directory.GetFiles(configPath, "*.json"))
        {
            try
            {
                var config = GetExportConfig(file);
                results.Add((config.Name, file));
            }
            catch (Exception ex)
            {
                _logger.Log("WARN", $"Skipping invalid export config file: {file}", "CONFIG_LOAD_SKIP", ex.Message);
            }
        }

        return results;
    }

    public List<string> ConvertFieldListToXmlIds(List<ExportField> fields)
    {
        return fields.Select(f => f.XmlId).ToList();
    }

    public Dictionary<string, string> GetCustomFieldsFromConfig(List<ExportField> fields)
    {
        var customFields = new Dictionary<string, string>();

        foreach (var field in fields)
        {
            if (field.IsCustom)
            {
                customFields[field.XmlId] = field.ParentElement ?? "Tumor";
            }
        }

        return customFields;
    }

    public void InitializeDefaultExportConfig()
    {
        var configPath = GetExportConfigPath();
        var defaultPath = System.IO.Path.Combine(configPath, "default.json");

        if (!File.Exists(defaultPath))
        {
            var defaultConfig = NewExportConfig("Default", GetDefaultFieldList(), 25);
            SaveExportConfig(defaultConfig, "default.json");
        }
    }

    // ─── OBX Skip Config ────────────────────────────────────────

    public ObxSkipConfig GetObxSkipConfig()
    {
        var configPath = PathHelper.GetConfigPath("obx-skip-config.json");

        var defaultConfig = new ObxSkipConfig
        {
            Version = 1,
            SkipCodes = new List<string> { "Gross Description", "Microscopic Description", "Clinical History" },
            SkipCodeDescriptions = new Dictionary<string, string>
            {
                ["Gross Description"] = "Gross Description",
                ["Microscopic Description"] = "Microscopic Description",
                ["Clinical History"] = "Clinical History"
            }
        };

        if (!File.Exists(configPath))
        {
            return defaultConfig;
        }

        try
        {
            var json = File.ReadAllText(configPath);
            var config = JsonSerializer.Deserialize<ObxSkipConfig>(json, JsonReadOptions);
            return config ?? defaultConfig;
        }
        catch (Exception ex)
        {
            _logger.LogError("Failed to load OBX skip config, using defaults", "CONFIG_OBX_SKIP_LOAD", ex);
            return defaultConfig;
        }
    }

    public void SaveObxSkipConfig(ObxSkipConfig config)
    {
        var configPath = PathHelper.GetConfigPath("obx-skip-config.json");
        PathHelper.EnsureDirectoryExists(Path.GetDirectoryName(configPath)!);

        var json = JsonSerializer.Serialize(config, JsonWriteOptions);
        File.WriteAllText(configPath, json, System.Text.Encoding.UTF8);
    }
}
