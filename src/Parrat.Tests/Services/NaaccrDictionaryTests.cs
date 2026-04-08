using Parrat.Core.Helpers;
using Parrat.Core.Services;
using Parrat.Tests.Helpers;
using Xunit;

namespace Parrat.Tests.Services;

public class NaaccrDictionaryTests
{
    private NaaccrDictionary CreateDictionary(int version = 25)
    {
        PathHelper.SetRepoRoot(TestEnvironment.FindRepoRoot());
        var dict = new NaaccrDictionary();
        dict.Initialize(version);
        return dict;
    }

    [Fact]
    public void Initialize_LoadsDictionaryItems()
    {
        var dict = CreateDictionary();

        var items = dict.GetDictionary();
        Assert.True(items.Count > 100,
            $"NAACCR dictionary should contain hundreds of items, got {items.Count}");
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
        Assert.True(results.Count >= 2,
            $"Need at least 2 results to verify sort order, got {results.Count}");

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

    // ── XML Dictionary Enrichment ───────────────────────────────────────

    [Theory]
    [InlineData(25)]
    [InlineData(26)]
    public void Initialize_EnrichesLengthFromXmlDictionary(int version)
    {
        var dict = CreateDictionary(version);

        var item = dict.GetItemByXmlId("primarySite");
        Assert.NotNull(item);
        Assert.Equal(4, item!.Length);
    }

    [Theory]
    [InlineData(25)]
    [InlineData(26)]
    public void Initialize_EnrichesDataTypeFromXmlDictionary(int version)
    {
        var dict = CreateDictionary(version);

        var dateItem = dict.GetItemByXmlId("dateOfDiagnosis");
        Assert.NotNull(dateItem);
        Assert.Equal("date", dateItem!.DataType);
        Assert.Equal(8, dateItem.Length);

        var digitsItem = dict.GetItemByXmlId("patientIdNumber");
        Assert.NotNull(digitsItem);
        Assert.Equal("digits", digitsItem!.DataType);
    }

    [Theory]
    [InlineData(25)]
    [InlineData(26)]
    public void Initialize_TextFieldsHaveDefaultDataType(int version)
    {
        var dict = CreateDictionary(version);

        // nameLast has no explicit dataType in XML, should default to "text"
        var item = dict.GetItemByXmlId("nameLast");
        Assert.NotNull(item);
        Assert.Equal("text", item!.DataType);
        Assert.NotNull(item.Length);
    }
}
