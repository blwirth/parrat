namespace Parrat.Tests.Helpers;

/// <summary>
/// Helper for building NAACCR XML strings in tests.
/// Ported from test patterns in tests/xml-helpers.Tests.ps1.
/// </summary>
public static class NaaccrXmlTestHelper
{
    public const string NaaccrNamespace = "http://naaccr.org/naaccrxml";

    /// <summary>
    /// Builds a minimal NAACCR XML document string with the given patients/tumors.
    /// </summary>
    public static string BuildNaaccrXml(
        string baseDictionaryUri = "http://naaccr.org/naaccrxml/naaccr-dictionary-230.xml",
        string recordType = "I",
        Dictionary<string, string>? naaccrDataItems = null,
        params PatientData[] patients)
    {
        var patientElements = string.Join("\n", patients.Select(BuildPatientElement));

        var naaccrDataItemElements = "";
        if (naaccrDataItems != null)
        {
            naaccrDataItemElements = "\n" + string.Join("\n",
                naaccrDataItems.Select(kvp => $@"  <Item naaccrId=""{kvp.Key}"">{kvp.Value}</Item>"));
        }

        return $@"<?xml version=""1.0"" encoding=""UTF-8""?>
<NaaccrData xmlns=""{NaaccrNamespace}"" baseDictionaryUri=""{baseDictionaryUri}"" recordType=""{recordType}"">{naaccrDataItemElements}
{patientElements}
</NaaccrData>";
    }

    /// <summary>
    /// Builds a simple NAACCR XML with one patient and one tumor.
    /// </summary>
    public static string BuildSimpleNaaccrXml(
        string nameLast = "Smith",
        string nameFirst = "John",
        string dateOfBirth = "19800101",
        string primarySite = "C509",
        string dateOfDiagnosis = "20240101")
    {
        return BuildNaaccrXml(patients: new PatientData
        {
            NameLast = nameLast,
            NameFirst = nameFirst,
            DateOfBirth = dateOfBirth,
            Tumors = new[]
            {
                new TumorData
                {
                    PrimarySite = primarySite,
                    DateOfDiagnosis = dateOfDiagnosis
                }
            }
        });
    }

    /// <summary>
    /// Builds a minimal XML string (no namespace) for Format-Xml testing.
    /// </summary>
    public static string BuildMinifiedXml(string rootElement = "root", string childContent = "<child attr=\"value\">text</child>")
    {
        return $"<{rootElement}>{childContent}</{rootElement}>";
    }

    /// <summary>
    /// Builds an XML string with the NAACCR namespace for namespace handling tests.
    /// </summary>
    public static string BuildNamespacedXml(string nameLast = "Doe")
    {
        return $@"<NaaccrData xmlns=""{NaaccrNamespace}""><Patient><Item naaccrId=""nameLast"">{nameLast}</Item></Patient></NaaccrData>";
    }

    private static string BuildPatientElement(PatientData patient)
    {
        var items = new List<string>();

        if (!string.IsNullOrEmpty(patient.NameLast))
            items.Add($@"    <Item naaccrId=""nameLast"">{patient.NameLast}</Item>");
        if (!string.IsNullOrEmpty(patient.NameFirst))
            items.Add($@"    <Item naaccrId=""nameFirst"">{patient.NameFirst}</Item>");
        if (!string.IsNullOrEmpty(patient.DateOfBirth))
            items.Add($@"    <Item naaccrId=""dateOfBirth"">{patient.DateOfBirth}</Item>");
        if (!string.IsNullOrEmpty(patient.PatientIdNumber))
            items.Add($@"    <Item naaccrId=""patientIdNumber"">{patient.PatientIdNumber}</Item>");
        if (patient.Items != null)
            items.AddRange(patient.Items.Select(kvp => $@"    <Item naaccrId=""{kvp.Key}"">{kvp.Value}</Item>"));

        var tumorElements = string.Join("\n", (patient.Tumors ?? Array.Empty<TumorData>()).Select(BuildTumorElement));

        var itemsStr = items.Count > 0 ? "\n" + string.Join("\n", items) : "";
        var tumorsStr = !string.IsNullOrEmpty(tumorElements) ? "\n" + tumorElements : "";

        return $"  <Patient>{itemsStr}{tumorsStr}\n  </Patient>";
    }

    private static string BuildTumorElement(TumorData tumor)
    {
        var items = new List<string>();

        if (!string.IsNullOrEmpty(tumor.PrimarySite))
            items.Add($@"      <Item naaccrId=""primarySite"">{tumor.PrimarySite}</Item>");
        if (!string.IsNullOrEmpty(tumor.DateOfDiagnosis))
            items.Add($@"      <Item naaccrId=""dateOfDiagnosis"">{tumor.DateOfDiagnosis}</Item>");
        if (!string.IsNullOrEmpty(tumor.PathReportNumber1))
            items.Add($@"      <Item naaccrId=""pathReportNumber1"">{tumor.PathReportNumber1}</Item>");
        if (tumor.Items != null)
            items.AddRange(tumor.Items.Select(kvp => $@"      <Item naaccrId=""{kvp.Key}"">{kvp.Value}</Item>"));

        var itemsStr = items.Count > 0 ? "\n" + string.Join("\n", items) + "\n    " : "";

        return $"    <Tumor>{itemsStr}</Tumor>";
    }

    public class PatientData
    {
        public string? NameLast { get; set; }
        public string? NameFirst { get; set; }
        public string? DateOfBirth { get; set; }
        public string? PatientIdNumber { get; set; }

        /// <summary>Additional patient-level items by naaccrId.</summary>
        public Dictionary<string, string>? Items { get; set; }

        public TumorData[]? Tumors { get; set; }
    }

    public class TumorData
    {
        public string? PrimarySite { get; set; }
        public string? DateOfDiagnosis { get; set; }
        public string? PathReportNumber1 { get; set; }

        /// <summary>Additional tumor-level items by naaccrId.</summary>
        public Dictionary<string, string>? Items { get; set; }
    }
}
