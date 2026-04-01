using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;
using Parrat.Core.Interfaces;

namespace Parrat.Core.Services;

/// <summary>
/// Converts pathology text reports to HL7 format.
/// Supports facility-specific parsing for Parkland, Portsmouth, Frisbie, and SJH.
/// Ported from lib/convert-txt.ps1.
/// </summary>
public class ConvertTxtService : IConvertTxtService
{
    private const string UnknownDate = "99999999";

    private static readonly Dictionary<string, FacilityConfig> FacilityConfigs = new()
    {
        ["Parkland"] = new("7120090", "PARKLAND MEDICAL CENTER^300017^CLIA"),
        ["Portsmouth"] = new("7120360", "PORTSMOUTH REGIONAL HOSPITAL^30D1064878^CLIA"),
        ["Frisbie"] = new("7120380", "FRISBIE MEMORIAL HOSPITAL^300014^CLIA"),
        ["SJH"] = new("120300", "ST JOSEPH HOSPITAL^30D0896420^CLIA")
    };

    private record FacilityConfig(string FacilityNum, string CLIA);

    public string ConvertPathologyTextToHl7(string inputPath, string? outputPath, string facilityName, bool previewOnly = false)
    {
        if (!File.Exists(inputPath))
            throw new FileNotFoundException($"Input file not found: {inputPath}");

        if (!FacilityConfigs.TryGetValue(facilityName, out var config))
            throw new ArgumentException($"Unknown facility: {facilityName}");

        var cases = facilityName == "SJH"
            ? GetSJHCases(inputPath)
            : GetStandardCases(inputPath, facilityName);

        if (previewOnly)
            return $"Preview: {cases.Count} cases parsed from {Path.GetFileName(inputPath)}";

        var hl7Lines = new List<string>();

        foreach (var caseData in cases)
        {
            string birthDateHL7;
            string specimenDateHL7;

            if (facilityName == "SJH")
            {
                birthDateHL7 = caseData.BirthDate;
                specimenDateHL7 = caseData.SpecimenDateObj.HasValue
                    ? caseData.SpecimenDateObj.Value.ToString("yyyyMMdd")
                    : UnknownDate;
            }
            else
            {
                birthDateHL7 = ConvertDateToHL7(caseData.BirthDate);
                specimenDateHL7 = ConvertDateToHL7(caseData.SpecimenDate);
            }

            var msh = $"MSH|^~\\&|E-Path Case={caseData.CaseNumber}|{config.CLIA}|E-Path|NHSCR|{UnknownDate}||ORU^R01^ORU_R01||P|2.5.1|||||USA||ENG||VOL_V_40_ORU_R01^NAACCR_CP";
            var pid = $"PID|1||{caseData.MedicalRecordNumber}^^^^MR^~^^^^SS||{caseData.NameLast}^{caseData.NameFirst}^{caseData.NameMiddle}||{birthDateHL7}|{caseData.Sex}|||Unknown^^Unknown^ZZ^99999|||";
            var obr = $"OBR|1||{caseData.PathReportID}||||{specimenDateHL7}||||||||||||||||||F||||||||";

            hl7Lines.Add(msh);
            hl7Lines.Add(pid);
            hl7Lines.Add(obr);

            for (int i = 0; i < caseData.TextLines.Count; i++)
            {
                hl7Lines.Add($"OBX|{i + 1}|TX|||{caseData.TextLines[i]}");
            }
        }

        if (!string.IsNullOrEmpty(outputPath))
        {
            var outputDir = Path.GetDirectoryName(outputPath);
            if (!string.IsNullOrEmpty(outputDir) && !Directory.Exists(outputDir))
                Directory.CreateDirectory(outputDir);

            File.WriteAllLines(outputPath, hl7Lines, Encoding.UTF8);
        }

        return string.Join(Environment.NewLine, hl7Lines);
    }

    public List<Dictionary<string, object>> GetPreviewCases(string inputPath, string facilityName)
    {
        if (!File.Exists(inputPath))
            throw new FileNotFoundException($"Input file not found: {inputPath}");

        var cases = facilityName == "SJH"
            ? GetSJHCases(inputPath)
            : GetStandardCases(inputPath, facilityName);

        return cases.Select(c => new Dictionary<string, object>
        {
            ["CaseNumber"] = c.CaseNumber,
            ["NameLast"] = c.NameLast,
            ["NameFirst"] = c.NameFirst,
            ["PathReportID"] = c.PathReportID,
            ["SpecimenDate"] = c.SpecimenDate,
            ["TextLineCount"] = c.TextLines.Count
        }).ToList();
    }

    #region Date Helpers

    private static string ConvertDateToHL7(string dateString, string format = "MM/dd/yyyy")
    {
        if (string.IsNullOrWhiteSpace(dateString))
            return UnknownDate;

        try
        {
            DateTime date;
            if (Regex.IsMatch(dateString, @"^\d{2}/\d{2}/\d{2}$"))
                date = DateTime.ParseExact(dateString, "MM/dd/yy", CultureInfo.InvariantCulture);
            else
                date = DateTime.ParseExact(dateString, "MM/dd/yyyy", CultureInfo.InvariantCulture);

            return date.ToString("yyyyMMdd");
        }
        catch
        {
            return UnknownDate;
        }
    }

    private static string GetSJHDOB(int? age, DateTime? specimenDate)
    {
        if (age.HasValue && specimenDate.HasValue)
        {
            int dobYear = specimenDate.Value.Year - age.Value;
            if (dobYear >= 1800 && dobYear <= 2200)
                return $"{dobYear:D4}9999";
        }
        return UnknownDate;
    }

    #endregion

    #region Parsing

    private record CaseData
    {
        public int CaseNumber { get; init; }
        public string NameLast { get; set; } = "";
        public string NameFirst { get; set; } = "";
        public string NameMiddle { get; set; } = "";
        public string BirthDate { get; set; } = "";
        public string Sex { get; set; } = "";
        public string MedicalRecordNumber { get; set; } = "";
        public string SpecimenDate { get; set; } = "";
        public string PathReportID { get; set; } = "";
        public List<string> TextLines { get; init; } = new();
        public int? Age { get; set; }
        public DateTime? SpecimenDateObj { get; set; }
    }

    private static (string NameLast, string NameFirst, string NameMiddle, string BirthDate, string Sex, string MedicalRecordNumber) ParsePatientLine(string line)
    {
        string nameLast = "", nameFirst = "", nameMiddle = "", birthDate = "", sex = "", mrn = "";
        var cleanLine = line.Replace(',', ' ');

        var nameMatch = Regex.Match(cleanLine, @"PATIENT:\s*(.+?)\s+ACCT");
        if (nameMatch.Success)
        {
            var parts = nameMatch.Groups[1].Value.Trim().Split(new[] { ' ' }, StringSplitOptions.RemoveEmptyEntries);
            if (parts.Length > 0) nameLast = parts[0];
            if (parts.Length > 1) nameFirst = parts[1];
            if (parts.Length > 2) nameMiddle = parts[2];
        }

        var dobMatch = Regex.Match(cleanLine, @"DOB:\s*(\d{2}/\d{2}/\d{4})");
        if (dobMatch.Success) birthDate = dobMatch.Groups[1].Value;

        var sexMatch = Regex.Match(cleanLine, @"AGE/SEX:\s*\d+/([A-Z])");
        if (sexMatch.Success) sex = sexMatch.Groups[1].Value;

        var mrnMatch = Regex.Match(cleanLine, @"U:\s*([A-Z]\d+)");
        if (mrnMatch.Success) mrn = mrnMatch.Groups[1].Value;

        return (nameLast, nameFirst, nameMiddle, birthDate, sex, mrn);
    }

    private static string GetSpecimenDate(string line)
    {
        var match = Regex.Match(line, @"COLL:\s*(\d{2}/\d{2}/\d{2,4})");
        return match.Success ? match.Groups[1].Value : "";
    }

    private static string GetPathReportID(string line)
    {
        var match = Regex.Match(line, @"SPEC\s*[:#]\s*(?:.*?:)?(\S+)\s+COLL:");
        return match.Success ? match.Groups[1].Value : "";
    }

    private List<CaseData> GetStandardCases(string inputPath, string facilityName)
    {
        var lines = File.ReadAllLines(inputPath, Encoding.UTF8);
        var cases = new List<CaseData>();
        CaseData? currentCase = null;
        int caseNumber = 0;
        int linesSinceCaseSigned = 999;

        foreach (var rawLine in lines)
        {
            var line = rawLine.Trim();
            if (string.IsNullOrWhiteSpace(line) || line == "** CONTINUED ON NEXT PAGE **")
                continue;

            if (line == "Case Signed At")
                linesSinceCaseSigned = 0;
            else
                linesSinceCaseSigned++;

            bool isFacilityLine = line.StartsWith(facilityName);
            if (isFacilityLine && linesSinceCaseSigned <= 4)
                isFacilityLine = false;

            if (isFacilityLine)
            {
                if (currentCase != null)
                    cases.Add(currentCase);

                caseNumber++;
                currentCase = new CaseData { CaseNumber = caseNumber };
                linesSinceCaseSigned = 999;
            }

            if (currentCase == null)
                continue;

            if (line.StartsWith("PATIENT:"))
            {
                var (nl, nf, nm, bd, s, m) = ParsePatientLine(line);
                currentCase.NameLast = nl;
                currentCase.NameFirst = nf;
                currentCase.NameMiddle = nm;
                currentCase.BirthDate = bd;
                currentCase.Sex = s;
                currentCase.MedicalRecordNumber = m;
            }

            var specimenDate = GetSpecimenDate(line);
            if (!string.IsNullOrEmpty(specimenDate))
                currentCase.SpecimenDate = specimenDate;

            var pathReportId = GetPathReportID(line);
            if (!string.IsNullOrEmpty(pathReportId))
                currentCase.PathReportID = pathReportId;

            currentCase.TextLines.Add(line);
        }

        if (currentCase != null)
            cases.Add(currentCase);

        return cases;
    }

    private static readonly Regex SjhCaseStartRegex = new(@"^\s*(?:NH|NS|NC)2[0-9]-\d+", RegexOptions.Compiled);
    private static readonly Regex SjhPathIdRegex = new(@"\b(NH|NS|NC)\d{2}-\d+", RegexOptions.Compiled);
    private static readonly Regex SjhNameRegex = new(
        @"Patient:\s*(?:\d{4,7}\s*)?([A-Za-z]+(?:[ \-][A-Za-z]+)*),\s*([A-Za-z]+)(?:\s+([A-Za-z]+)(?:\.)?)?(?=\s*(?:Age:|\d{4,7}\b|MD:|MRN:|$))",
        RegexOptions.Compiled);
    private static readonly Regex SjhAgeRegex = new(@"Age:\s*(\d{1,3})\b", RegexOptions.Compiled);
    private static readonly Regex SjhSexRegex = new(@"Sex:\s*([MF])\b", RegexOptions.Compiled);
    private static readonly Regex SjhMrnRegex = new(
        @"(?:MRN:\s*Patient:\s*|(?<![-\/]))(\d{4,7})(?=\s*(?:MD:|MRN:|Patient:|Age:|[A-Za-z]|$))",
        RegexOptions.Compiled);
    private static readonly Regex SjhDateRegex = new(@"\b(\d{1,2}\/\d{1,2}\/\d{2,4})\b", RegexOptions.Compiled);

    private static readonly string[] SkipPrefixes = {
        "Tissue Committee Report",
        "Date/Time Printed:",
        "Selection Criteria:",
        "Part Type:"
    };

    private List<CaseData> GetSJHCases(string inputPath)
    {
        var rawText = File.ReadAllText(inputPath, Encoding.Default);
        var lines = rawText.Split(new[] { "\r\n", "\n" }, StringSplitOptions.None);

        var cases = new List<CaseData>();
        CaseData? currentCase = null;
        int caseNumber = 0;

        foreach (var rawLine in lines)
        {
            var line = FormatSJHWhitespace(rawLine);
            if (string.IsNullOrWhiteSpace(line))
                continue;

            if (SkipPrefixes.Any(p => line.StartsWith(p, StringComparison.OrdinalIgnoreCase)))
                continue;

            if (SjhCaseStartRegex.IsMatch(line))
            {
                if (currentCase != null)
                    cases.Add(currentCase);

                caseNumber++;
                var caseInfo = ParseSJHCaseLine(line);
                currentCase = new CaseData
                {
                    CaseNumber = caseNumber,
                    NameLast = caseInfo.NameLast,
                    NameFirst = caseInfo.NameFirst,
                    NameMiddle = caseInfo.NameMiddle,
                    Sex = caseInfo.Sex,
                    MedicalRecordNumber = caseInfo.MRN,
                    PathReportID = caseInfo.PathReportID,
                    Age = caseInfo.Age
                };
            }

            if (currentCase == null)
                continue;

            // Update fields from any line
            var nameMatch = SjhNameRegex.Match(line);
            if (nameMatch.Success)
            {
                if (string.IsNullOrEmpty(currentCase.NameLast)) currentCase.NameLast = nameMatch.Groups[1].Value;
                if (string.IsNullOrEmpty(currentCase.NameFirst)) currentCase.NameFirst = nameMatch.Groups[2].Value;
                if (nameMatch.Groups[3].Success && string.IsNullOrEmpty(currentCase.NameMiddle))
                    currentCase.NameMiddle = nameMatch.Groups[3].Value;
            }

            var ageMatch = SjhAgeRegex.Match(line);
            if (ageMatch.Success && !currentCase.Age.HasValue)
                currentCase.Age = int.Parse(ageMatch.Groups[1].Value);

            var sexMatch = SjhSexRegex.Match(line);
            if (sexMatch.Success && string.IsNullOrEmpty(currentCase.Sex))
                currentCase.Sex = sexMatch.Groups[1].Value;

            var mrnMatch = SjhMrnRegex.Match(line);
            if (mrnMatch.Success && string.IsNullOrEmpty(currentCase.MedicalRecordNumber))
                currentCase.MedicalRecordNumber = mrnMatch.Groups[1].Value;

            var pathIdMatch = SjhPathIdRegex.Match(line);
            if (pathIdMatch.Success && string.IsNullOrEmpty(currentCase.PathReportID))
                currentCase.PathReportID = pathIdMatch.Value;

            // Parse dates
            var dateMatches = SjhDateRegex.Matches(line);
            if (dateMatches.Count > 0)
            {
                DateTime? minDate = null;
                foreach (Match m in dateMatches)
                {
                    if (DateTime.TryParse(m.Groups[1].Value, out var dt))
                    {
                        if (!minDate.HasValue || dt < minDate.Value)
                            minDate = dt;
                    }
                }

                if (minDate.HasValue && (!currentCase.SpecimenDateObj.HasValue || minDate.Value < currentCase.SpecimenDateObj.Value))
                {
                    currentCase.SpecimenDateObj = minDate;
                    currentCase.SpecimenDate = minDate.Value.ToString("MM/dd/yyyy");

                    if (currentCase.Age.HasValue)
                        currentCase.BirthDate = GetSJHDOB(currentCase.Age, currentCase.SpecimenDateObj);
                }
            }

            currentCase.TextLines.Add(line);
        }

        if (currentCase != null)
            cases.Add(currentCase);

        return cases;
    }

    private static (string PathReportID, string NameLast, string NameFirst, string NameMiddle, int? Age, string Sex, string MRN) ParseSJHCaseLine(string line)
    {
        string pathReportId = "", nameLast = "", nameFirst = "", nameMiddle = "", sex = "", mrn = "";
        int? age = null;

        var pathMatch = SjhPathIdRegex.Match(line);
        if (pathMatch.Success) pathReportId = pathMatch.Value;

        var nameMatch = SjhNameRegex.Match(line);
        if (nameMatch.Success)
        {
            nameLast = nameMatch.Groups[1].Value;
            nameFirst = nameMatch.Groups[2].Value;
            if (nameMatch.Groups[3].Success) nameMiddle = nameMatch.Groups[3].Value;
        }

        var ageMatch = SjhAgeRegex.Match(line);
        if (ageMatch.Success) age = int.Parse(ageMatch.Groups[1].Value);

        var sexMatch = SjhSexRegex.Match(line);
        if (sexMatch.Success) sex = sexMatch.Groups[1].Value;

        var mrnMatch = SjhMrnRegex.Match(line);
        if (mrnMatch.Success) mrn = mrnMatch.Groups[1].Value;

        return (pathReportId, nameLast, nameFirst, nameMiddle, age, sex, mrn);
    }

    private static string FormatSJHWhitespace(string? s)
    {
        if (s == null) return "";
        return Regex.Replace(s.Trim(), @"\s+", " ");
    }

    #endregion
}
