using System.Data;
using System.Xml;
using Parrat.Core.Models;
using Parrat.Core.Services;
using Parrat.Tests.Helpers;
using Xunit;

namespace Parrat.Tests.Services;

public class SearchServiceTests
{
    #region BuildSearchIndex — XML

    [Fact]
    public void BuildSearchIndex_Xml_IndexesPatientAndTumorItems()
    {
        var xml = NaaccrXmlTestHelper.BuildNaaccrXml(patients: new NaaccrXmlTestHelper.PatientData
        {
            NameLast = "Smith",
            NameFirst = "John",
            Tumors = new[]
            {
                new NaaccrXmlTestHelper.TumorData { PrimarySite = "C509", DateOfDiagnosis = "20240101" }
            }
        });

        var (tumors, nsMgr) = LoadTumors(xml);
        var service = new SearchService(tumors, nsMgr);

        var index = service.BuildSearchIndex("xml");
        Assert.Single(index);
        Assert.Contains("smith", index[0]);
        Assert.Contains("john", index[0]);
        Assert.Contains("c509", index[0]);
    }

    [Fact]
    public void BuildSearchIndex_Xml_ReturnsEmptyWhenNoTumors()
    {
        var service = new SearchService();
        var index = service.BuildSearchIndex("xml");
        Assert.Empty(index);
    }

    [Fact]
    public void BuildSearchIndex_Xml_MultiTumorIndex()
    {
        var xml = NaaccrXmlTestHelper.BuildNaaccrXml(patients: new NaaccrXmlTestHelper.PatientData
        {
            NameLast = "Smith",
            Tumors = new[]
            {
                new NaaccrXmlTestHelper.TumorData { PrimarySite = "C509" },
                new NaaccrXmlTestHelper.TumorData { PrimarySite = "C189" },
            }
        });

        var (tumors, nsMgr) = LoadTumors(xml);
        var service = new SearchService(tumors, nsMgr);

        var index = service.BuildSearchIndex("xml");
        Assert.Equal(2, index.Length);
        Assert.Contains("c509", index[0]);
        Assert.Contains("c189", index[1]);
    }

    #endregion

    #region BuildSearchIndex — HL7

    [Fact]
    public void BuildSearchIndex_Hl7_IndexesMessageFields()
    {
        var messages = new List<Hl7Message>
        {
            new()
            {
                PatientId = "12345",
                PatientLastName = "Jones",
                PatientFirstName = "Jane",
                MessageType = "ORU^R01",
                Segments = new Dictionary<string, List<string>>
                {
                    ["OBX"] = new() { "OBX|1|TX|CODE^Desc|sub|Adenocarcinoma" }
                }
            }
        };

        var service = new SearchService(null, null, messages);
        var index = service.BuildSearchIndex("hl7");

        Assert.Single(index);
        Assert.Contains("jones", index[0]);
        Assert.Contains("12345", index[0]);
        Assert.Contains("adenocarcinoma", index[0]);
    }

    [Fact]
    public void BuildSearchIndex_Hl7_ReturnsEmptyWhenNoMessages()
    {
        var service = new SearchService();
        var index = service.BuildSearchIndex("hl7");
        Assert.Empty(index);
    }

    #endregion

    #region BuildSearchIndex — Unknown type

    [Fact]
    public void BuildSearchIndex_UnknownType_ReturnsEmpty()
    {
        var service = new SearchService();
        var index = service.BuildSearchIndex("csv");
        Assert.Empty(index);
    }

    #endregion

    #region ApplyFilter

    [Fact]
    public void ApplyFilter_FiltersToMatchingRows()
    {
        var table = new DataTable();
        table.Columns.Add("Index", typeof(int));
        table.Columns.Add("Name", typeof(string));
        table.Rows.Add(1, "Smith");
        table.Rows.Add(2, "Jones");
        table.Rows.Add(3, "Brown");

        var searchIndex = new[] { "smith john c509", "jones jane c189", "brown bob c341" };

        var service = new SearchService();
        service.ApplyFilter("jones", table, searchIndex);

        var filtered = table.DefaultView.ToTable();
        Assert.Equal(1, filtered.Rows.Count);
        Assert.Equal(2, filtered.Rows[0]["Index"]);
    }

    [Fact]
    public void ApplyFilter_ClearsFilterOnEmpty()
    {
        var table = new DataTable();
        table.Columns.Add("Index", typeof(int));
        table.Rows.Add(1);
        table.Rows.Add(2);

        var service = new SearchService();
        service.ApplyFilter("a", table, new[] { "a", "b" });
        service.ApplyFilter("", table, new[] { "a", "b" });

        Assert.Equal(2, table.DefaultView.Count);
    }

    [Fact]
    public void ApplyFilter_NoMatches_ShowsNoRows()
    {
        var table = new DataTable();
        table.Columns.Add("Index", typeof(int));
        table.Rows.Add(1);

        var service = new SearchService();
        service.ApplyFilter("zzzzz", table, new[] { "smith" });

        var filtered = table.DefaultView.ToTable();
        Assert.Equal(0, filtered.Rows.Count);
    }

    #endregion

    private static (XmlNodeList tumors, XmlNamespaceManager nsMgr) LoadTumors(string xml)
    {
        var doc = new XmlDocument();
        doc.XmlResolver = null;
        doc.LoadXml(xml);
        var nsMgr = new XmlNamespaceManager(doc.NameTable);
        nsMgr.AddNamespace("n", NaaccrXmlTestHelper.NaaccrNamespace);
        return (doc.SelectNodes("//n:Tumor", nsMgr)!, nsMgr);
    }
}
