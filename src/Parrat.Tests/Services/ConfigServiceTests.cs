using Parrat.Core.Helpers;
using Parrat.Core.Models;
using Parrat.Core.Services;
using Xunit;

namespace Parrat.Tests.Services;

public class ConfigServiceTests : IDisposable
{
    private readonly string _tempDir;
    private readonly string _originalRepoRoot;
    private readonly string _originalUserDir;

    public ConfigServiceTests()
    {
        _tempDir = Path.Combine(Path.GetTempPath(), $"parrat_config_test_{Guid.NewGuid():N}");
        Directory.CreateDirectory(_tempDir);
        Directory.CreateDirectory(Path.Combine(_tempDir, "config"));
        Directory.CreateDirectory(Path.Combine(_tempDir, "config", "export-configs"));
        Directory.CreateDirectory(Path.Combine(_tempDir, "data"));

        _originalRepoRoot = PathHelper.RepoRoot;
        _originalUserDir = PathHelper.UserDir;
        PathHelper.SetRepoRoot(_tempDir);
        PathHelper.SetUserDir(_tempDir);
    }

    public void Dispose()
    {
        PathHelper.SetRepoRoot(_originalRepoRoot);
        PathHelper.SetUserDir(_originalUserDir);
        try { Directory.Delete(_tempDir, true); } catch { }
    }

    #region GetDefaultFieldList

    [Fact]
    public void GetDefaultFieldList_ReturnsExpectedFields()
    {
        var svc = new ConfigService();
        var fields = svc.GetDefaultFieldList();

        Assert.True(fields.Count > 5, "Default field list should have multiple fields");
        var xmlIds = fields.Select(f => f.XmlId).ToList();
        Assert.Contains("patientIdNumber", xmlIds);
        Assert.Contains("nameLast", xmlIds);
        Assert.Contains("primarySite", xmlIds);
        Assert.All(fields, f => Assert.False(f.IsCustom));
    }

    #endregion

    #region NewExportConfig

    [Fact]
    public void NewExportConfig_CreatesWithDefaults()
    {
        var svc = new ConfigService();
        var config = svc.NewExportConfig();

        Assert.Equal("Unnamed Configuration", config.Name);
        Assert.Equal(25, config.Version);
        Assert.NotNull(config.Fields);
        Assert.NotNull(config.CreatedDate);
    }

    [Fact]
    public void NewExportConfig_UsesProvidedValues()
    {
        var svc = new ConfigService();
        var fields = new List<ExportField> { new() { XmlId = "test" } };
        var config = svc.NewExportConfig("My Config", fields, 24);

        Assert.Equal("My Config", config.Name);
        Assert.Equal(24, config.Version);
        Assert.Single(config.Fields);
    }

    #endregion

    #region SaveExportConfig / GetExportConfig roundtrip

    [Fact]
    public void SaveAndLoadExportConfig_Roundtrips()
    {
        var svc = new ConfigService();
        var config = svc.NewExportConfig("Test Config", svc.GetDefaultFieldList());
        var configDir = svc.GetExportConfigPath();

        var (success, path, _) = svc.SaveExportConfig(config, "test.json", configDir);
        Assert.True(success);

        var loaded = svc.GetExportConfig(path);
        Assert.Equal("Test Config", loaded.Name);
        Assert.Equal(config.Fields.Count, loaded.Fields.Count);
    }

    [Fact]
    public void SaveExportConfig_SanitizesFileName()
    {
        var svc = new ConfigService();
        var config = svc.NewExportConfig("My Config!@#$");
        var configDir = svc.GetExportConfigPath();

        var (success, path, _) = svc.SaveExportConfig(config, path: configDir);
        Assert.True(success);
        Assert.DoesNotContain("!", Path.GetFileName(path));
    }

    [Fact]
    public void GetExportConfig_ThrowsForMissingFile()
    {
        var svc = new ConfigService();
        Assert.Throws<FileNotFoundException>(() => svc.GetExportConfig("/nonexistent/config.json"));
    }

    #endregion

    #region GetAvailableExportConfigs

    [Fact]
    public void GetAvailableExportConfigs_ListsSavedConfigs()
    {
        var svc = new ConfigService();
        var configDir = svc.GetExportConfigPath();

        var config1 = svc.NewExportConfig("Config A");
        var config2 = svc.NewExportConfig("Config B");
        svc.SaveExportConfig(config1, "a.json", configDir);
        svc.SaveExportConfig(config2, "b.json", configDir);

        var available = svc.GetAvailableExportConfigs();
        Assert.Equal(2, available.Count);
        Assert.Contains(available, c => c.Name == "Config A");
        Assert.Contains(available, c => c.Name == "Config B");
    }

    #endregion

    #region ConvertFieldListToXmlIds

    [Fact]
    public void ConvertFieldListToXmlIds_ExtractsIds()
    {
        var svc = new ConfigService();
        var fields = new List<ExportField>
        {
            new() { XmlId = "nameLast" },
            new() { XmlId = "primarySite" },
        };

        var ids = svc.ConvertFieldListToXmlIds(fields);
        Assert.Equal(new[] { "nameLast", "primarySite" }, ids);
    }

    #endregion

    #region GetCustomFieldsFromConfig

    [Fact]
    public void GetCustomFieldsFromConfig_ReturnsOnlyCustomFields()
    {
        var svc = new ConfigService();
        var fields = new List<ExportField>
        {
            new() { XmlId = "nameLast", IsCustom = false },
            new() { XmlId = "myCustomField", IsCustom = true, ParentElement = "Patient" },
            new() { XmlId = "anotherCustom", IsCustom = true },
        };

        var custom = svc.GetCustomFieldsFromConfig(fields);
        Assert.Equal(2, custom.Count);
        Assert.Equal("Patient", custom["myCustomField"]);
        Assert.Equal("Tumor", custom["anotherCustom"]); // defaults to Tumor
    }

    #endregion

    #region ObxSkipConfig

    [Fact]
    public void GetObxSkipConfig_ReturnsDefaultsWhenNoFile()
    {
        var svc = new ConfigService();
        var config = svc.GetObxSkipConfig();

        Assert.Equal(1, config.Version);
        Assert.NotEmpty(config.SkipCodes);
        Assert.Contains("Gross Description", config.SkipCodes);
    }

    [Fact]
    public void SaveAndLoadObxSkipConfig_Roundtrips()
    {
        var svc = new ConfigService();
        var config = new ObxSkipConfig
        {
            Version = 1,
            SkipCodes = new List<string> { "Custom Code" },
            SkipCodeDescriptions = new Dictionary<string, string> { ["Custom Code"] = "My Custom" }
        };

        svc.SaveObxSkipConfig(config);
        var loaded = svc.GetObxSkipConfig();

        Assert.Single(loaded.SkipCodes);
        Assert.Equal("Custom Code", loaded.SkipCodes[0]);
    }

    #endregion
}
