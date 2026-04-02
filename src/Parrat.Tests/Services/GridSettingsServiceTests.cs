using Parrat.Core.Helpers;
using Parrat.Core.Models;
using Parrat.Core.Services;
using Xunit;

namespace Parrat.Tests.Services;

public class GridSettingsServiceTests : IDisposable
{
    private readonly string _tempDir;
    private readonly string _originalRepoRoot;
    private readonly string _originalUserDir;

    public GridSettingsServiceTests()
    {
        _tempDir = Path.Combine(Path.GetTempPath(), $"parrat_grid_test_{Guid.NewGuid():N}");
        Directory.CreateDirectory(_tempDir);
        Directory.CreateDirectory(Path.Combine(_tempDir, "config"));
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

    #region Load

    [Fact]
    public void Load_ReturnsDefaultsWhenNoFileExists()
    {
        var service = new GridSettingsService();
        var settings = service.Load();

        Assert.NotNull(settings);
        Assert.Equal(1, settings.Version);
        Assert.NotNull(settings.Xml);
        Assert.NotNull(settings.Hl7);
        Assert.True(settings.Xml!.Columns.Count > 0, "Default XML columns should not be empty");
        Assert.True(settings.Hl7!.Columns.Count > 0, "Default HL7 columns should not be empty");
    }

    [Fact]
    public void Load_ReturnsDefaultsForMalformedJson()
    {
        File.WriteAllText(PathHelper.GetConfigPath("grid-settings.json"), "not valid json {{{");

        var service = new GridSettingsService();
        var settings = service.Load();

        Assert.Equal(1, settings.Version);
        Assert.NotNull(settings.Xml);
    }

    [Fact]
    public void Load_ReturnsDefaultsForInvalidVersion()
    {
        var json = """{"version": 99, "xml": {"columns": [{"id": "test"}]}, "hl7": {"columns": [{"id": "test"}]}}""";
        File.WriteAllText(PathHelper.GetConfigPath("grid-settings.json"), json);

        var service = new GridSettingsService();
        var settings = service.Load();

        Assert.Equal(1, settings.Version);
    }

    #endregion

    #region Save + Load roundtrip

    [Fact]
    public void Save_PersistsSettingsToFile()
    {
        var service = new GridSettingsService();
        var settings = new GridSettings
        {
            Version = 1,
            Xml = new GridColumnsConfig
            {
                Columns = new List<GridColumnDef>
                {
                    new() { Id = "nameLast", Width = 200 },
                    new() { Id = "primarySite", Width = 100 },
                }
            },
            Hl7 = new GridColumnsConfig
            {
                Columns = new List<GridColumnDef>
                {
                    new() { Id = "patientId", Width = 150 },
                }
            }
        };

        service.Save(settings);

        var loaded = service.Load();
        Assert.Equal(1, loaded.Version);
        Assert.Equal(2, loaded.Xml!.Columns.Count);
        Assert.Equal("nameLast", loaded.Xml.Columns[0].Id);
        Assert.Equal(200, loaded.Xml.Columns[0].Width);
        Assert.Single(loaded.Hl7!.Columns);
        Assert.Equal("patientId", loaded.Hl7.Columns[0].Id);
    }

    #endregion

    #region GetDefaultXmlColumns / GetDefaultHl7Columns

    [Fact]
    public void GetDefaultXmlColumns_ContainsExpectedFields()
    {
        var service = new GridSettingsService();
        var config = service.GetDefaultXmlColumns();

        var ids = config.Columns.Select(c => c.Id).ToList();
        Assert.Contains("nameLast", ids);
        Assert.Contains("primarySite", ids);
        Assert.Contains("dateOfDiagnosis", ids);
    }

    [Fact]
    public void GetDefaultHl7Columns_ContainsExpectedFields()
    {
        var service = new GridSettingsService();
        var config = service.GetDefaultHl7Columns();

        var ids = config.Columns.Select(c => c.Id).ToList();
        Assert.Contains("nameLast", ids);
        Assert.Contains("patientId", ids);
        Assert.Contains("messageType", ids);
    }

    #endregion
}
