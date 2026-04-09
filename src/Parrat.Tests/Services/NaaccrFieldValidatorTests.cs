using Parrat.Core.Models;
using Parrat.Core.Services;
using Xunit;

namespace Parrat.Tests.Services;

public class NaaccrFieldValidatorTests
{
    // ── Length Validation ────────────────────────────────────────────────

    [Fact]
    public void ValidateValue_WithinLength_NoWarning()
    {
        var item = new NaaccrItem { XmlId = "primarySite", Length = 4, DataType = "text" };
        var warnings = NaaccrFieldValidator.ValidateValue("C509", item);
        Assert.Empty(warnings);
    }

    [Fact]
    public void ValidateValue_ExceedsLength_Warning()
    {
        var item = new NaaccrItem { XmlId = "primarySite", Length = 4, DataType = "text" };
        var warnings = NaaccrFieldValidator.ValidateValue("C5099", item);
        Assert.Single(warnings, w => w.Contains("Exceeds max length"));
    }

    [Fact]
    public void ValidateValue_ExactLength_NoWarning()
    {
        var item = new NaaccrItem { XmlId = "dateOfDiagnosis", Length = 8, DataType = "date" };
        var warnings = NaaccrFieldValidator.ValidateValue("20240115", item);
        Assert.Empty(warnings);
    }

    [Fact]
    public void ValidateValue_NoLengthDefined_NoLengthWarning()
    {
        var item = new NaaccrItem { XmlId = "custom", Length = null, DataType = "text" };
        var warnings = NaaccrFieldValidator.ValidateValue("any length value here", item);
        Assert.Empty(warnings);
    }

    // ── Date Validation ─────────────────────────────────────────────────

    [Theory]
    [InlineData("20240115")]  // Full date
    [InlineData("202401")]    // Year + month
    [InlineData("2024")]      // Year only
    public void ValidateValue_ValidDate_NoWarning(string value)
    {
        var item = new NaaccrItem { XmlId = "dateOfDiagnosis", Length = 8, DataType = "date" };
        var warnings = NaaccrFieldValidator.ValidateValue(value, item);
        Assert.Empty(warnings);
    }

    [Theory]
    [InlineData("2024-01-15")]   // Wrong format (dashes)
    [InlineData("01/15/2024")]   // US format
    [InlineData("abc")]          // Not numeric
    [InlineData("123")]          // 3 digits
    [InlineData("12345")]        // 5 digits
    [InlineData("1234567")]      // 7 digits
    [InlineData("123456789")]    // 9 digits
    public void ValidateValue_InvalidDateFormat_Warning(string value)
    {
        var item = new NaaccrItem { XmlId = "dateOfDiagnosis", Length = 8, DataType = "date" };
        var warnings = NaaccrFieldValidator.ValidateValue(value, item);
        Assert.Contains(warnings, w => w.Contains("date format"));
    }

    [Fact]
    public void ValidateValue_DateWithInvalidMonth_Warning()
    {
        var item = new NaaccrItem { XmlId = "dateOfDiagnosis", Length = 8, DataType = "date" };
        var warnings = NaaccrFieldValidator.ValidateValue("20241315", item);
        Assert.Contains(warnings, w => w.Contains("Invalid month"));
    }

    [Fact]
    public void ValidateValue_DateWithInvalidDay_Warning()
    {
        var item = new NaaccrItem { XmlId = "dateOfDiagnosis", Length = 8, DataType = "date" };
        var warnings = NaaccrFieldValidator.ValidateValue("20240132", item);
        Assert.Contains(warnings, w => w.Contains("Invalid day"));
    }

    [Fact]
    public void ValidateValue_DateMonth00_Warning()
    {
        var item = new NaaccrItem { XmlId = "dateOfDiagnosis", Length = 8, DataType = "date" };
        var warnings = NaaccrFieldValidator.ValidateValue("202400", item);
        Assert.Contains(warnings, w => w.Contains("Invalid month"));
    }

    [Fact]
    public void ValidateValue_DateDay00_Warning()
    {
        var item = new NaaccrItem { XmlId = "dateOfDiagnosis", Length = 8, DataType = "date" };
        var warnings = NaaccrFieldValidator.ValidateValue("20240100", item);
        Assert.Contains(warnings, w => w.Contains("Invalid day"));
    }

    // ── Digits Validation ───────────────────────────────────────────────

    [Fact]
    public void ValidateValue_DigitsOnly_NoWarning()
    {
        var item = new NaaccrItem { XmlId = "accessionNumberHosp", Length = 9, DataType = "digits" };
        var warnings = NaaccrFieldValidator.ValidateValue("123456789", item);
        Assert.Empty(warnings);
    }

    [Fact]
    public void ValidateValue_DigitsWithLetters_Warning()
    {
        var item = new NaaccrItem { XmlId = "accessionNumberHosp", Length = 9, DataType = "digits" };
        var warnings = NaaccrFieldValidator.ValidateValue("12345abc", item);
        Assert.Contains(warnings, w => w.Contains("digits only"));
    }

    [Fact]
    public void ValidateValue_DigitsWithSpecialChars_Warning()
    {
        var item = new NaaccrItem { XmlId = "accessionNumberHosp", Length = 9, DataType = "digits" };
        var warnings = NaaccrFieldValidator.ValidateValue("123-456", item);
        Assert.Contains(warnings, w => w.Contains("digits only"));
    }

    // ── Alpha Validation ────────────────────────────────────────────────

    [Fact]
    public void ValidateValue_AlphaOnly_NoWarning()
    {
        var item = new NaaccrItem { XmlId = "addrAtDxCountry", Length = 3, DataType = "alpha" };
        var warnings = NaaccrFieldValidator.ValidateValue("USA", item);
        Assert.Empty(warnings);
    }

    [Fact]
    public void ValidateValue_AlphaWithDigits_Warning()
    {
        var item = new NaaccrItem { XmlId = "addrAtDxCountry", Length = 3, DataType = "alpha" };
        var warnings = NaaccrFieldValidator.ValidateValue("U5A", item);
        Assert.Contains(warnings, w => w.Contains("alpha"));
    }

    // ── Numeric Validation ──────────────────────────────────────────────

    [Theory]
    [InlineData("42")]
    [InlineData("3.14")]
    [InlineData("-1")]
    [InlineData("0")]
    public void ValidateValue_ValidNumeric_NoWarning(string value)
    {
        var item = new NaaccrItem { XmlId = "someNumeric", Length = 10, DataType = "numeric" };
        var warnings = NaaccrFieldValidator.ValidateValue(value, item);
        Assert.Empty(warnings);
    }

    [Theory]
    [InlineData("abc")]
    [InlineData("12.34.56")]
    [InlineData("1,234")]
    public void ValidateValue_InvalidNumeric_Warning(string value)
    {
        var item = new NaaccrItem { XmlId = "someNumeric", Length = 10, DataType = "numeric" };
        var warnings = NaaccrFieldValidator.ValidateValue(value, item);
        Assert.Contains(warnings, w => w.Contains("numeric"));
    }

    // ── Text and Mixed — No Type Warnings ───────────────────────────────

    [Theory]
    [InlineData("text")]
    [InlineData("mixed")]
    public void ValidateValue_TextOrMixed_NoTypeWarning(string dataType)
    {
        var item = new NaaccrItem { XmlId = "someField", Length = 100, DataType = dataType };
        var warnings = NaaccrFieldValidator.ValidateValue("Anything goes! 123 @#$", item);
        Assert.Empty(warnings);
    }

    [Fact]
    public void ValidateValue_TextExceedsLength_StillWarns()
    {
        var item = new NaaccrItem { XmlId = "someField", Length = 5, DataType = "text" };
        var warnings = NaaccrFieldValidator.ValidateValue("too long value", item);
        Assert.Single(warnings, w => w.Contains("Exceeds max length"));
    }

    // ── ValidateDataSet ─────────────────────────────────────────────────

    [Fact]
    public void ValidateDataSet_ReturnsWarningsForBadData()
    {
        var csv = new CsvParseResult
        {
            Headers = new[] { "dateOfDiagnosis", "primarySite" },
            Rows = new List<string[]>
            {
                new[] { "20240115", "C509" },   // valid
                new[] { "not-a-date", "C5099" }, // both invalid
                new[] { "202401", "C180" }       // valid
            }
        };

        var mappings = new List<CsvImportMapping>
        {
            new() { CsvColumnIndex = 0, CsvHeader = "dateOfDiagnosis", MappedNaaccrId = "dateOfDiagnosis" },
            new() { CsvColumnIndex = 1, CsvHeader = "primarySite", MappedNaaccrId = "primarySite" }
        };

        var dictionary = new StubDictionary(new Dictionary<string, NaaccrItem>
        {
            ["dateOfDiagnosis"] = new() { XmlId = "dateOfDiagnosis", Length = 8, DataType = "date" },
            ["primarySite"] = new() { XmlId = "primarySite", Length = 4, DataType = "text" }
        });

        var warnings = NaaccrFieldValidator.ValidateDataSet(csv, mappings, dictionary);

        // Row 1: dateOfDiagnosis bad format, primarySite too long
        Assert.Contains(warnings, w => w.NaaccrId == "dateOfDiagnosis" && w.RowIndex == 1);
        Assert.Contains(warnings, w => w.NaaccrId == "primarySite" && w.RowIndex == 1);

        // Row 0 and 2 should be clean
        Assert.DoesNotContain(warnings, w => w.RowIndex == 0);
        Assert.DoesNotContain(warnings, w => w.RowIndex == 2);
    }

    [Fact]
    public void ValidateDataSet_SkipsIncompatibleMappings()
    {
        var csv = new CsvParseResult
        {
            Headers = new[] { "badField" },
            Rows = new List<string[]> { new[] { "value" } }
        };

        var mappings = new List<CsvImportMapping>
        {
            new() { CsvColumnIndex = 0, CsvHeader = "badField", MappedNaaccrId = "badField", IsIncompatible = true }
        };

        var dictionary = new StubDictionary(new Dictionary<string, NaaccrItem>());
        var warnings = NaaccrFieldValidator.ValidateDataSet(csv, mappings, dictionary);
        Assert.Empty(warnings);
    }

    [Fact]
    public void ValidateDataSet_SkipsEmptyValues()
    {
        var csv = new CsvParseResult
        {
            Headers = new[] { "dateOfDiagnosis" },
            Rows = new List<string[]> { new[] { "" } }
        };

        var mappings = new List<CsvImportMapping>
        {
            new() { CsvColumnIndex = 0, CsvHeader = "dateOfDiagnosis", MappedNaaccrId = "dateOfDiagnosis" }
        };

        var dictionary = new StubDictionary(new Dictionary<string, NaaccrItem>
        {
            ["dateOfDiagnosis"] = new() { XmlId = "dateOfDiagnosis", Length = 8, DataType = "date" }
        });

        var warnings = NaaccrFieldValidator.ValidateDataSet(csv, mappings, dictionary);
        Assert.Empty(warnings);
    }

    [Fact]
    public void ValidateDataSet_RespectsMaxRows()
    {
        var csv = new CsvParseResult
        {
            Headers = new[] { "primarySite" },
            Rows = new List<string[]>
            {
                new[] { "TOOLONG" },
                new[] { "TOOLONG" },
                new[] { "TOOLONG" }
            }
        };

        var mappings = new List<CsvImportMapping>
        {
            new() { CsvColumnIndex = 0, CsvHeader = "primarySite", MappedNaaccrId = "primarySite" }
        };

        var dictionary = new StubDictionary(new Dictionary<string, NaaccrItem>
        {
            ["primarySite"] = new() { XmlId = "primarySite", Length = 4, DataType = "text" }
        });

        var warnings = NaaccrFieldValidator.ValidateDataSet(csv, mappings, dictionary, maxRows: 2);
        Assert.Equal(2, warnings.Count);
    }

    // ── Summarize ───────────────────────────────────────────────────────

    [Fact]
    public void Summarize_GroupsByFieldAndMessage()
    {
        var warnings = new List<ValidationWarning>
        {
            new() { NaaccrId = "dateOfDiagnosis", CsvHeader = "DOD", RowIndex = 0, Message = "bad format" },
            new() { NaaccrId = "dateOfDiagnosis", CsvHeader = "DOD", RowIndex = 1, Message = "bad format" },
            new() { NaaccrId = "primarySite", CsvHeader = "Site", RowIndex = 2, Message = "too long" }
        };

        var summaries = NaaccrFieldValidator.Summarize(warnings);

        Assert.Equal(2, summaries.Count);
        Assert.Contains(summaries, s => s.Contains("DOD") && s.Contains("2 rows"));
        Assert.Contains(summaries, s => s.Contains("Site") && s.Contains("row 3"));
    }

    [Fact]
    public void Summarize_SingleWarning_ShowsRowNumber()
    {
        var warnings = new List<ValidationWarning>
        {
            new() { NaaccrId = "primarySite", CsvHeader = "Site", RowIndex = 4, Message = "too long" }
        };

        var summaries = NaaccrFieldValidator.Summarize(warnings);
        Assert.Single(summaries);
        Assert.Contains("row 5", summaries[0]); // 0-indexed to 1-indexed
    }

    // ── Stub Dictionary ─────────────────────────────────────────────────

    private class StubDictionary : Parrat.Core.Interfaces.INaaccrDictionary
    {
        private readonly Dictionary<string, NaaccrItem> _items;

        public StubDictionary(Dictionary<string, NaaccrItem> items) => _items = items;

        public void Initialize(int version = 25) { }
        public int ActiveVersion => 25;
        public Dictionary<string, NaaccrItem> GetDictionary() => _items;
        public NaaccrItem? GetItemByXmlId(string xmlId) => _items.TryGetValue(xmlId, out var item) ? item : null;
        public string GetParentElement(string xmlId, Dictionary<string, string>? customFields = null) => "Tumor";
        public List<NaaccrItem> Search(string searchText) => new();
        public string GetDisplayName(string xmlId) => xmlId;
    }
}
