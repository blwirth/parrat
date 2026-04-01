using Parrat.Core.Helpers;
using Parrat.Core.Services;
using Xunit;

namespace Parrat.Tests.Services;

public class NaaccrDictionaryTests
{
    private static readonly string RepoRoot = FindRepoRoot();

    private static string FindRepoRoot()
    {
        var dir = AppDomain.CurrentDomain.BaseDirectory;
        for (int i = 0; i < 10; i++)
        {
            if (Directory.Exists(Path.Combine(dir, "data", "dictionaries")))
                return dir;
            var parent = Directory.GetParent(dir);
            if (parent == null) break;
            dir = parent.FullName;
        }
        return Path.GetFullPath(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "..", "..", "..", "..", ".."));
    }

    private NaaccrDictionary CreateDictionary(int version = 25)
    {
        PathHelper.SetRepoRoot(RepoRoot);
        var dict = new NaaccrDictionary();
        dict.Initialize(version);
        return dict;
    }

    [Fact]
    public void Initialize_LoadsDictionaryItems()
    {
        var dict = CreateDictionary();

        var items = dict.GetDictionary();
        Assert.NotEmpty(items);
    }

    [Fact]
    public void GetItemByXmlId_ReturnsCorrectItem()
    {
        var dict = CreateDictionary();

        var item = dict.GetItemByXmlId("patientIdNumber");
        Assert.NotNull(item);
        Assert.Equal("Patient ID Number", item.Name);
        Assert.Equal("20", item.Number);
        Assert.Equal("Patient", item.ParentElement);
    }

    [Fact]
    public void GetItemByXmlId_ReturnsNullForUnknown()
    {
        var dict = CreateDictionary();

        var item = dict.GetItemByXmlId("nonExistentField_xyz");
        Assert.Null(item);
    }

    [Fact]
    public void GetParentElement_ReturnsCorrectParent()
    {
        var dict = CreateDictionary();

        Assert.Equal("Patient", dict.GetParentElement("patientIdNumber"));
        Assert.Equal("Tumor", dict.GetParentElement("primarySite"));
        Assert.Equal("NaaccrData", dict.GetParentElement("recordType"));
    }

    [Fact]
    public void GetParentElement_DefaultsToTumorForUnknown()
    {
        var dict = CreateDictionary();

        Assert.Equal("Tumor", dict.GetParentElement("unknownField_xyz"));
    }

    [Fact]
    public void GetParentElement_PrefersCustomFieldsOverDictionary()
    {
        var dict = CreateDictionary();

        var custom = new Dictionary<string, string>
        {
            ["patientIdNumber"] = "NaaccrData"
        };

        Assert.Equal("NaaccrData", dict.GetParentElement("patientIdNumber", custom));
    }

    [Fact]
    public void Search_FindsByName()
    {
        var dict = CreateDictionary();

        var results = dict.Search("Patient ID Number");
        Assert.NotEmpty(results);
        Assert.Contains(results, r => r.XmlId == "patientIdNumber");
    }

    [Fact]
    public void Search_FindsByXmlId()
    {
        var dict = CreateDictionary();

        var results = dict.Search("patientIdNumber");
        Assert.NotEmpty(results);
        Assert.Contains(results, r => r.XmlId == "patientIdNumber");
    }

    [Fact]
    public void Search_FindsByNumber()
    {
        var dict = CreateDictionary();

        var results = dict.Search("20");
        Assert.NotEmpty(results);
        Assert.Contains(results, r => r.XmlId == "patientIdNumber");
    }

    [Fact]
    public void Search_ResultsSortedByNumber()
    {
        var dict = CreateDictionary();

        var results = dict.Search("patient");
        Assert.NotEmpty(results);

        for (int i = 1; i < results.Count; i++)
        {
            Assert.True(results[i - 1].NumberInt <= results[i].NumberInt,
                $"Results not sorted: {results[i - 1].NumberInt} > {results[i].NumberInt}");
        }
    }

    [Fact]
    public void GetDisplayName_ReturnsFormattedName()
    {
        var dict = CreateDictionary();

        var name = dict.GetDisplayName("patientIdNumber");
        Assert.Equal("Patient ID Number (patientIdNumber)", name);
    }

    [Fact]
    public void GetDisplayName_ReturnsCustomForUnknown()
    {
        var dict = CreateDictionary();

        var name = dict.GetDisplayName("unknownField");
        Assert.Equal("unknownField (custom)", name);
    }
}
