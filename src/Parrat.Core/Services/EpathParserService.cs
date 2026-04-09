using System.Text;
using System.Text.Json;
using Parrat.Core.Helpers;
using Parrat.Core.Interfaces;
using Parrat.Core.Models;

namespace Parrat.Core.Services;

public class EpathParserService : IEpathParserService
{
    private readonly IParratLogger _logger;
    private List<EpathField>? _v22Layout;
    private List<EpathField>? _noahV2Layout;

    public EpathParserService() : this(NullParratLogger.Instance) { }

    public EpathParserService(IParratLogger logger)
    {
        _logger = logger;
    }

    // ── Parse .dat → native EpathRecord ─────────────────────────────────

    public List<EpathRecord> ParseDatFile(string filePath)
    {
        var content = File.ReadAllText(filePath, Encoding.UTF8);
        var lines = content.Replace("\r\n", "\n").Replace("\r", "\n")
            .Split('\n', StringSplitOptions.RemoveEmptyEntries);

        var records = new List<EpathRecord>();

        for (int i = 0; i < lines.Length; i++)
        {
            var line = lines[i].Trim();
            if (string.IsNullOrEmpty(line)) continue;

            try
            {
                var fields = SplitEpathLine(line);
                var isNoahV2 = fields.Length >= 100;
                var layout = isNoahV2 ? LoadNoahV2Layout() : LoadV22Layout();
                var fieldMap = BuildFieldMap(fields, layout);
                var displayFields = BuildDisplayFields(fields, layout);

                var record = new EpathRecord
                {
                    Index = i,
                    RawLine = line,
                    Fields = fieldMap,
                    DisplayFields = displayFields,
                    PatientLastName = Get(fieldMap, 2230),
                    PatientFirstName = Get(fieldMap, 2240),
                    DateOfBirth = Get(fieldMap, 240),
                    Sex = Get(fieldMap, 220),
                    PatientId = Get(fieldMap, 2300),
                    PathReportNumber = Get(fieldMap, 7090),
                    SendingFacility = Get(fieldMap, 7020),
                    FormatVersion = isNoahV2 ? "NOAH v2" : "v2.2"
                };

                records.Add(record);
            }
            catch (Exception ex)
            {
                _logger.LogError($"Failed to parse ePath line {i + 1}", "EPATH_IMPORT", ex);
            }
        }

        _logger.Log("INFO", $"Parsed {records.Count} ePath records from {Path.GetFileName(filePath)}", "EPATH_IMPORT");
        return records;
    }

    // ── Convert EpathRecord → HL7 (explicit user action) ────────────────

    public List<Hl7Message> ConvertToHl7(List<EpathRecord> records)
    {
        var messages = new List<Hl7Message>();

        for (int i = 0; i < records.Count; i++)
        {
            var record = records[i];
            var m = record.Fields;
            var hl7Version = record.FormatVersion == "NOAH v2" ? "2.5.1" : "2.3.1";
            var hl7Text = BuildHl7FromMap(m, hl7Version);

            var segments = new Dictionary<string, List<string>>();
            var allSegments = new List<string>();
            foreach (var segLine in hl7Text.Split('\n', StringSplitOptions.RemoveEmptyEntries))
            {
                var trimmed = segLine.Trim();
                if (trimmed.Length < 3) continue;
                var segType = trimmed[..3];
                if (!segments.ContainsKey(segType))
                    segments[segType] = new List<string>();
                segments[segType].Add(trimmed);
                allSegments.Add(trimmed);
            }

            var ordLast = Get(m, 7110);
            var ordFirst = Get(m, 7120);
            var ordLic = Get(m, 7100);

            messages.Add(new Hl7Message
            {
                Index = i,
                RawContent = hl7Text,
                Segments = segments,
                AllSegments = allSegments,
                PatientId = record.PatientId,
                PatientName = BuildPatientName(record.PatientLastName, record.PatientFirstName, Get(m, 2250)),
                PatientLastName = record.PatientLastName,
                PatientFirstName = record.PatientFirstName,
                DateOfBirth = record.DateOfBirth,
                Sex = record.Sex,
                MessageType = "ORU^R01",
                MessageDateTime = Get(m, 7490),
                SendingApplication = "EPATH",
                SendingFacility = $"{record.SendingFacility}^{Get(m, 7010)}",
                AccessionNumber = record.PathReportNumber,
                OrderDateTime = Get(m, 7320),
                OrderingProvider = BuildProviderDisplay(ordLic, ordLast, ordFirst)
            });
        }

        _logger.Log("INFO", $"Converted {messages.Count} ePath records to HL7", "EPATH_CONVERT");
        return messages;
    }

    // ── Pipe-delimited line splitting ───────────────────────────────────

    public static string[] SplitEpathLine(string line)
    {
        var fields = new List<string>();
        var current = new StringBuilder();

        for (int i = 0; i < line.Length; i++)
        {
            if (line[i] == '|')
            {
                if (i > 0 && line[i - 1] == '\\')
                {
                    current.Length--;
                    current.Append('|');
                }
                else
                {
                    fields.Add(current.ToString());
                    current.Clear();
                }
            }
            else
            {
                current.Append(line[i]);
            }
        }

        fields.Add(current.ToString());
        return fields.ToArray();
    }

    // ── HL7 message construction ────────────────────────────────────────

    public string BuildHl7FromMap(Dictionary<int, string> m, string hl7Version = "2.3.1")
    {
        var sb = new StringBuilder();

        // MSH
        sb.AppendLine(
            $"MSH|^~\\&|EPATH|{Esc(Get(m, 7020))}^{Esc(Get(m, 7010))}|||{Get(m, 7490)}" +
            $"||ORU^R01|{Esc(Get(m, 7500))}|{Get(m, 7510)}|{hl7Version}");

        // PID
        sb.AppendLine(
            $"PID|1||{Esc(Get(m, 2300))}||" +
            $"{Esc(Get(m, 2230))}^{Esc(Get(m, 2240))}^{Esc(Get(m, 2250))}^^{Esc(Get(m, 2220))}" +
            $"|{Esc(Get(m, 2280))}" +
            $"|{Get(m, 240)}|{Get(m, 220)}" +
            $"|{Get(m, 160)}" +
            $"|{Esc(Get(m, 2330))}^^{Esc(Get(m, 70))}^{Get(m, 80)}^{Get(m, 100)}^^{Get(m, 7520)}" +
            $"||{Esc(Get(m, 2360))}" +
            $"||||{Get(m, 150)}" +
            $"|{Get(m, 260)}" +
            $"||||{Get(m, 2320)}" +
            $"||||{Get(m, 190)}" +
            $"||||||{Get(m, 7550)}");

        // PV1
        var physManaging = Get(m, 2460);
        var physSurgeon = Get(m, 2480);
        var physFollowup = Get(m, 2470);
        if (!string.IsNullOrEmpty(physManaging) || !string.IsNullOrEmpty(physSurgeon) || !string.IsNullOrEmpty(physFollowup))
            sb.AppendLine($"PV1|1||||||{physManaging}|{physSurgeon}|{physFollowup}");

        // ORC
        sb.AppendLine(
            $"ORC|RE" +
            $"||||||||||||||||||||" +
            $"{Esc(Get(m, 7200))}^{Esc(Get(m, 7190))}" +
            $"|{Esc(Get(m, 7210))}^^{Esc(Get(m, 7220))}^{Get(m, 7230)}^{Get(m, 7240)}^{Esc(Get(m, 7235))}" +
            $"|{Esc(Get(m, 7250))}" +
            $"|{Esc(Get(m, 7140))}^^{Esc(Get(m, 7150))}^{Get(m, 7160)}^{Get(m, 7170)}^{Esc(Get(m, 7165))}");

        // OBR
        sb.AppendLine(
            $"OBR|1||{Esc(Get(m, 7090))}" +
            $"|PATH^Pathology Report" +
            $"|||{Get(m, 7320)}" +
            $"|||||||{Get(m, 7560)}" +
            $"||{Esc(Get(m, 7100))}^{Esc(Get(m, 7110))}^{Esc(Get(m, 7120))}^{Esc(Get(m, 7130))}" +
            $"|{Esc(Get(m, 7180))}" +
            $"||||" +
            $"|{Esc(Get(m, 7070))}" +
            $"|{Get(m, 7530)}" +
            $"|||{Get(m, 7330)}" +
            $"|||||||||||||" +
            $"{Esc(Get(m, 7300))}^{Esc(Get(m, 7260))}^{Esc(Get(m, 7270))}^{Esc(Get(m, 7280))}^{Esc(Get(m, 7290))}^^^^{Esc(Get(m, 7310))}");

        // OBX segments
        int obxSetId = 1;

        var snomed = Get(m, 7340);
        if (!string.IsNullOrEmpty(snomed))
            sb.AppendLine($"OBX|{obxSetId++}|CE|SNOMED^SNOMED CT Code||{Esc(snomed)}||||||F|||{Get(m, 7350)}");

        var icd = Get(m, 7360);
        if (!string.IsNullOrEmpty(icd))
            sb.AppendLine($"OBX|{obxSetId++}|CE|ICD^ICD-CM Code||{Esc(icd)}||||||F|||{Get(m, 7370)}");

        var cpt = Get(m, 7380);
        if (!string.IsNullOrEmpty(cpt))
            sb.AppendLine($"OBX|{obxSetId++}|CE|CPT^CPT Code||{Esc(cpt)}||||||F|||{Get(m, 7390)}");

        var textFields = new (int item, string code, string name)[]
        {
            (7400, "PATH_DX", "Path Text Diagnosis"),
            (7410, "CLIN_HX", "Clinical History"),
            (7420, "SPECIMEN", "Nature of Specimen"),
            (7430, "GROSS", "Gross Pathology"),
            (7440, "MICRO", "Micro Pathology"),
            (7450, "FINAL_DX", "Final Diagnosis"),
            (7460, "COMMENT", "Comment Section"),
            (7470, "SUPPL", "Supplemental Reports"),
            (2600, "STAGING", "Text Staging"),
        };

        foreach (var (item, code, name) in textFields)
        {
            var text = Get(m, item);
            if (!string.IsNullOrEmpty(text))
                sb.AppendLine($"OBX|{obxSetId++}|TX|{code}^{name}||{Esc(text)}||||||F");
        }

        var producerId = Get(m, 7515);
        if (!string.IsNullOrEmpty(producerId))
            sb.AppendLine($"OBX|{obxSetId++}|CE|PRODUCER^Producer ID (CLIA)||{Esc(producerId)}||||||F");

        var age = Get(m, 7080);
        var ageUnits = Get(m, 7540);
        if (!string.IsNullOrEmpty(age))
            sb.AppendLine($"OBX|{obxSetId++}|NM|AGE^Patient Age at Specimen||{age}|{ageUnits}|||||F");

        var reportType = Get(m, 7480);
        if (!string.IsNullOrEmpty(reportType))
            sb.AppendLine($"OBX|{obxSetId++}|CE|RPT_TYPE^Path Report Type||{reportType}||||||F");

        return sb.ToString().TrimEnd('\r', '\n');
    }

    // ── Internal helpers ────────────────────────────────────────────────

    private static Dictionary<int, string> BuildFieldMap(string[] fields, List<EpathField> layout)
    {
        var map = new Dictionary<int, string>();
        foreach (var field in layout)
        {
            int index = field.Position - 1;
            if (index < 0 || index >= fields.Length) continue;
            var value = fields[index].Trim();
            if (string.IsNullOrEmpty(value)) continue;
            var key = field.ItemNumber > 0 ? field.ItemNumber : -field.Position;
            map[key] = value;
        }
        return map;
    }

    private static List<EpathDisplayField> BuildDisplayFields(string[] fields, List<EpathField> layout)
    {
        var result = new List<EpathDisplayField>();
        foreach (var field in layout)
        {
            int index = field.Position - 1;
            if (index < 0 || index >= fields.Length) continue;
            var value = fields[index].Trim();
            if (string.IsNullOrEmpty(value)) continue;
            result.Add(new EpathDisplayField
            {
                Position = field.Position,
                Name = field.Name,
                Value = value,
                ItemNumber = field.ItemNumber
            });
        }
        return result;
    }

    private List<EpathField> LoadV22Layout()
    {
        if (_v22Layout != null) return _v22Layout;
        _v22Layout = LoadLayoutFile("epath-v22-layout.json");
        return _v22Layout;
    }

    private List<EpathField> LoadNoahV2Layout()
    {
        if (_noahV2Layout != null) return _noahV2Layout;
        _noahV2Layout = LoadLayoutFile("epath-noah-v2-layout.json");
        return _noahV2Layout;
    }

    private static List<EpathField> LoadLayoutFile(string filename)
    {
        var path = PathHelper.GetDictionaryPath(filename);
        var json = File.ReadAllText(path);
        var options = new JsonSerializerOptions { PropertyNameCaseInsensitive = true };
        return JsonSerializer.Deserialize<List<EpathField>>(json, options) ?? new List<EpathField>();
    }

    private static string Get(Dictionary<int, string> map, int itemNumber)
        => map.TryGetValue(itemNumber, out var value) ? value : "";

    private static string BuildPatientName(string lastName, string firstName, string middleName)
    {
        var name = $"{lastName}, {firstName}";
        if (!string.IsNullOrWhiteSpace(middleName))
            name = $"{lastName}, {firstName} {middleName}";
        return name.Trim(',', ' ');
    }

    private static string BuildProviderDisplay(string license, string lastName, string firstName)
    {
        var parts = new List<string>();
        if (!string.IsNullOrEmpty(license)) parts.Add(license);
        if (!string.IsNullOrEmpty(lastName))
        {
            var name = lastName;
            if (!string.IsNullOrEmpty(firstName)) name += $", {firstName}";
            parts.Add(name);
        }
        return string.Join(" - ", parts);
    }

    private static string Esc(string value)
    {
        if (string.IsNullOrEmpty(value)) return "";
        return value
            .Replace("\\", "\\E\\")
            .Replace("|", "\\F\\")
            .Replace("^", "\\S\\")
            .Replace("~", "\\R\\")
            .Replace("&", "\\T\\");
    }
}
