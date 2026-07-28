using System.Text;
using System.Xml;

namespace Parrat.Core.Services;

/// <summary>
/// Validates file content against expected format before parsing.
/// Returns structured results so callers can surface issues to the user.
/// </summary>
public static class FileFormatValidator
{
    public record ValidationResult(bool IsValid, List<string> Errors, List<string> Warnings)
    {
        public string Summary => string.Join("\n", Errors.Concat(Warnings));
    }

    // ── HL7 ─────────────────────────────────────────────────────────────

    /// <summary>
    /// Validates that content looks like a valid HL7 v2.x file.
    /// Checks: MSH presence, encoding characters, message type, PID presence.
    /// </summary>
    public static ValidationResult ValidateHl7(string content)
    {
        var errors = new List<string>();
        var warnings = new List<string>();

        if (string.IsNullOrWhiteSpace(content))
        {
            errors.Add("File is empty.");
            return new ValidationResult(false, errors, warnings);
        }

        // Must contain at least one MSH segment
        if (!content.Contains("MSH|"))
        {
            errors.Add("No MSH segment found. This does not appear to be an HL7 file.");
            return new ValidationResult(false, errors, warnings);
        }

        // Validate each message
        var normalized = content.Replace("\r\n", "\n").Replace("\r", "\n");
        var lines = normalized.Split('\n', StringSplitOptions.RemoveEmptyEntries);

        int messageCount = 0;
        int messagesWithPid = 0;
        int messagesWithObr = 0;

        string? currentMsh = null;

        foreach (var rawLine in lines)
        {
            var line = rawLine.Trim();
            if (string.IsNullOrEmpty(line)) continue;

            if (line.StartsWith("MSH|"))
            {
                // Validate previous message if any
                if (currentMsh != null)
                    messageCount++;

                currentMsh = line;
                var mshFields = line.Split('|');

                // MSH-2: Encoding characters should be ^~\&
                if (mshFields.Length > 1)
                {
                    var encoding = mshFields[1];
                    if (encoding != "^~\\&")
                        warnings.Add($"Message {messageCount + 1}: Non-standard encoding characters '{encoding}' (expected '^~\\&').");
                }

                // MSH-9: Message type should be present
                if (mshFields.Length <= 8 || string.IsNullOrWhiteSpace(mshFields[8]))
                    warnings.Add($"Message {messageCount + 1}: Missing message type (MSH-9).");
            }
            else if (line.StartsWith("PID|"))
            {
                messagesWithPid++;
            }
            else if (line.StartsWith("OBR|"))
            {
                messagesWithObr++;
            }
            else if (line.Length >= 3)
            {
                // Segment IDs should be 3 uppercase letters
                var segId = line[..3];
                if (segId != "MSH" && currentMsh != null)
                {
                    if (!IsValidSegmentId(segId))
                        warnings.Add($"Unexpected segment identifier '{segId}'. Expected 3-letter segment ID.");
                }
            }
        }

        // Count the last message
        if (currentMsh != null)
            messageCount++;

        if (messageCount == 0)
        {
            errors.Add("No complete HL7 messages found.");
            return new ValidationResult(false, errors, warnings);
        }

        if (messagesWithPid == 0)
            warnings.Add("No PID (patient identification) segments found in any message.");

        // Limit warnings to avoid flooding
        if (warnings.Count > 5)
        {
            var count = warnings.Count;
            warnings = warnings.Take(5).ToList();
            warnings.Add($"... and {count - 5} more warning(s).");
        }

        return new ValidationResult(errors.Count == 0, errors, warnings);
    }

    /// <summary>Validates raw file bytes as HL7.</summary>
    public static ValidationResult ValidateHl7File(string filePath)
    {
        var content = File.ReadAllText(filePath, Encoding.ASCII);
        return ValidateHl7(content);
    }

    // ── NAACCR XML ──────────────────────────────────────────────────────

    /// <summary>
    /// Validates that content looks like a valid NAACCR XML file.
    /// Checks: well-formed XML, NaaccrData root, namespace, Patient/Tumor structure.
    /// </summary>
    public static ValidationResult ValidateNaaccrXml(string content)
    {
        var errors = new List<string>();
        var warnings = new List<string>();

        if (string.IsNullOrWhiteSpace(content))
        {
            errors.Add("File is empty.");
            return new ValidationResult(false, errors, warnings);
        }

        // Check well-formed XML
        XmlDocument doc;
        try
        {
            doc = new XmlDocument();
            doc.XmlResolver = null;
            doc.LoadXml(content);
        }
        catch (XmlException ex)
        {
            errors.Add($"Not valid XML: {ex.Message}");
            return new ValidationResult(false, errors, warnings);
        }

        var root = doc.DocumentElement;
        if (root == null)
        {
            errors.Add("XML document has no root element.");
            return new ValidationResult(false, errors, warnings);
        }

        // Root element must be NaaccrData
        if (root.LocalName != "NaaccrData")
        {
            errors.Add($"Root element is '{root.LocalName}', expected 'NaaccrData'. This does not appear to be a NAACCR XML file.");
            return new ValidationResult(false, errors, warnings);
        }

        // Namespace check
        const string expectedNs = "http://naaccr.org/naaccrxml";
        if (root.NamespaceURI != expectedNs)
        {
            if (string.IsNullOrEmpty(root.NamespaceURI))
                warnings.Add("NaaccrData element has no namespace (expected 'http://naaccr.org/naaccrxml').");
            else
                warnings.Add($"NaaccrData namespace is '{root.NamespaceURI}' (expected '{expectedNs}').");
        }

        // baseDictionaryUri attribute
        var dictUri = root.GetAttribute("baseDictionaryUri");
        if (string.IsNullOrEmpty(dictUri))
            warnings.Add("Missing 'baseDictionaryUri' attribute on NaaccrData.");

        // recordType attribute
        var recordType = root.GetAttribute("recordType");
        if (string.IsNullOrEmpty(recordType))
            warnings.Add("Missing 'recordType' attribute on NaaccrData.");

        // Check for Patient elements
        var nsUri = root.NamespaceURI;
        var nsMgr = new XmlNamespaceManager(doc.NameTable);
        nsMgr.AddNamespace("n", string.IsNullOrEmpty(nsUri) ? "urn:dummy" : nsUri);

        var patients = string.IsNullOrEmpty(nsUri)
            ? root.GetElementsByTagName("Patient")
            : doc.SelectNodes("//n:Patient", nsMgr);

        if (patients == null || patients.Count == 0)
        {
            errors.Add("No Patient elements found in NaaccrData.");
            return new ValidationResult(false, errors, warnings);
        }

        // Check for Tumor elements within Patients
        var tumors = string.IsNullOrEmpty(nsUri)
            ? root.GetElementsByTagName("Tumor")
            : doc.SelectNodes("//n:Tumor", nsMgr);

        if (tumors == null || tumors.Count == 0)
            warnings.Add("No Tumor elements found within Patient elements.");

        return new ValidationResult(errors.Count == 0, errors, warnings);
    }

    /// <summary>Validates a NAACCR XML file from disk.</summary>
    public static ValidationResult ValidateNaaccrXmlFile(string filePath)
    {
        var content = File.ReadAllText(filePath, Encoding.UTF8);
        return ValidateNaaccrXml(content);
    }

    // ── ePath .dat ──────────────────────────────────────────────────────

    /// <summary>
    /// Validates that content looks like an ePath pipe-delimited flat file.
    /// Checks: non-empty, pipe-delimited, minimum field count, record type.
    /// </summary>
    public static ValidationResult ValidateEpathDat(string content)
    {
        var errors = new List<string>();
        var warnings = new List<string>();

        if (string.IsNullOrWhiteSpace(content))
        {
            errors.Add("File is empty.");
            return new ValidationResult(false, errors, warnings);
        }

        var lines = content.Replace("\r\n", "\n").Replace("\r", "\n")
            .Split('\n', StringSplitOptions.RemoveEmptyEntries);

        if (lines.Length == 0)
        {
            errors.Add("File contains no data lines.");
            return new ValidationResult(false, errors, warnings);
        }

        // Check first non-empty line for pipe-delimited format
        var firstLine = lines[0].Trim();
        if (!firstLine.Contains('|'))
        {
            errors.Add("First line contains no pipe (|) delimiters. This does not appear to be an ePath flat file.");
            return new ValidationResult(false, errors, warnings);
        }

        var firstFields = EpathParserService.SplitEpathLine(firstLine);

        // v2.2 has 85 fields, NOAH v2 has 100+. Minimum reasonable is ~20.
        if (firstFields.Length < 20)
        {
            errors.Add($"First record has only {firstFields.Length} fields (expected at least 85 for ePath v2.2). This may not be an ePath file.");
            return new ValidationResult(false, errors, warnings);
        }

        // Record type (field 1) should be "L" (laboratory) for ePath
        var recordType = firstFields[0].Trim();
        if (!string.IsNullOrEmpty(recordType) && recordType != "L")
            warnings.Add($"First record type is '{recordType}' (expected 'L' for laboratory ePath record).");

        // Check field count consistency across records
        bool hasInconsistentCounts = false;
        int expectedCount = firstFields.Length;
        for (int i = 1; i < Math.Min(lines.Length, 10); i++)
        {
            var line = lines[i].Trim();
            if (string.IsNullOrEmpty(line)) continue;
            var fieldCount = EpathParserService.SplitEpathLine(line).Length;
            if (fieldCount != expectedCount)
            {
                hasInconsistentCounts = true;
                break;
            }
        }

        if (hasInconsistentCounts)
            warnings.Add("Records have inconsistent field counts. Some records may not parse correctly.");

        return new ValidationResult(errors.Count == 0, errors, warnings);
    }

    /// <summary>Validates an ePath .dat file from disk.</summary>
    public static ValidationResult ValidateEpathDatFile(string filePath)
    {
        var content = File.ReadAllText(filePath, Encoding.UTF8);
        return ValidateEpathDat(content);
    }

    // ── Helpers ──────────────────────────────────────────────────────────

    /// <summary>
    /// Tests whether a segment identifier is well-formed per HL7 v2 chapter 2:
    /// exactly three uppercase alphanumeric characters, beginning with a letter.
    /// Digits are legal in positions 2 and 3 (PV1, NK1, IN1, DG1, GT1, AL1, FT1, ...),
    /// and Z-prefixed IDs are locally defined but follow the same shape.
    /// </summary>
    private static bool IsValidSegmentId(string segId)
    {
        if (segId.Length != 3) return false;
        if (segId[0] is < 'A' or > 'Z') return false;
        return segId.All(c => c is >= 'A' and <= 'Z' or >= '0' and <= '9');
    }
}
