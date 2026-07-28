using Parrat.Core.Helpers;
using Parrat.Core.Interfaces;
using Parrat.Core.Models;

namespace Parrat.Core.Services;

/// <summary>
/// Parses HL7 messages, segments, fields, and components.
/// Ported from lib/hl7-helpers.ps1.
/// </summary>
public class Hl7Parser : IHl7Parser
{
    private readonly IParratLogger _logger;

    public Hl7Parser() : this(NullParratLogger.Instance) { }

    public Hl7Parser(IParratLogger logger)
    {
        _logger = logger;
    }

    public string GetField(string segment, int fieldIndex)
    {
        if (string.IsNullOrWhiteSpace(segment))
            return "";

        var fields = segment.Split('|');
        return fieldIndex < fields.Length ? fields[fieldIndex] : "";
    }

    public string GetComponent(string field, int componentIndex)
    {
        if (string.IsNullOrWhiteSpace(field))
            return "";

        var components = field.Split('^');
        return componentIndex < components.Length ? components[componentIndex] : "";
    }

    public List<Hl7Message> Parse(string content)
    {
        var messages = new List<Hl7Message>();

        if (string.IsNullOrEmpty(content))
            return messages;

        // Normalize line endings to \n
        content = content.Replace("\r\n", "\n").Replace("\r", "\n");

        // Split content into individual messages by MSH segments
        var messageTexts = new List<string>();
        var currentMessageLines = new List<string>();

        var allLines = content.Split('\n');

        foreach (var line in allLines)
        {
            var trimmedLine = line.Trim();
            if (string.IsNullOrEmpty(trimmedLine))
                continue;

            // Batch envelope segments (FHS/BHS/BTS/FTS) are not message content.
            // Trailers in particular would otherwise be absorbed by the message
            // that precedes them.
            if (Hl7BatchHelper.IsEnvelopeSegment(trimmedLine))
                continue;

            if (trimmedLine.StartsWith("MSH|"))
            {
                if (currentMessageLines.Count > 0)
                {
                    messageTexts.Add(string.Join("\n", currentMessageLines));
                    currentMessageLines.Clear();
                }
                currentMessageLines.Add(trimmedLine);
            }
            else
            {
                if (currentMessageLines.Count > 0)
                    currentMessageLines.Add(trimmedLine);
            }
        }

        if (currentMessageLines.Count > 0)
            messageTexts.Add(string.Join("\n", currentMessageLines));

        for (int i = 0; i < messageTexts.Count; i++)
        {
            var msg = messageTexts[i];

            var segments = new Dictionary<string, List<string>>();
            var allSegments = new List<string>();
            var lines = msg.Split('\n');

            foreach (var line in lines)
            {
                var trimmedLine = line.Trim();
                if (string.IsNullOrEmpty(trimmedLine) || trimmedLine.Length < 3)
                    continue;

                var segmentType = trimmedLine[..3];
                if (!segments.ContainsKey(segmentType))
                    segments[segmentType] = new List<string>();
                segments[segmentType].Add(trimmedLine);
                allSegments.Add(trimmedLine);
            }

            var mshLine = segments.TryGetValue("MSH", out var mshList) ? mshList[0] : "";
            var pidLine = segments.TryGetValue("PID", out var pidList) ? pidList[0] : "";
            var obrLine = segments.TryGetValue("OBR", out var obrList) ? obrList[0] : "";

            var parsedMsh = ParseMsh(mshLine);
            var parsedPid = ParsePid(pidLine);
            var parsedObr = ParseObr(obrLine);

            messages.Add(new Hl7Message
            {
                Index = i,
                RawContent = msg,
                Segments = segments,
                AllSegments = allSegments,
                PatientId = parsedPid.PatientId,
                PatientName = parsedPid.PatientName,
                PatientLastName = parsedPid.LastName,
                PatientFirstName = parsedPid.FirstName,
                DateOfBirth = parsedPid.DateOfBirth,
                Sex = parsedPid.Sex,
                MessageType = parsedMsh.MessageType,
                MessageDateTime = parsedMsh.MessageDateTime,
                SendingApplication = parsedMsh.SendingApplication,
                SendingFacility = parsedMsh.SendingFacility,
                AccessionNumber = parsedObr.AccessionNumber,
                OrderDateTime = parsedObr.OrderDateTime,
                OrderingProvider = parsedObr.OrderingProvider
            });
        }

        return messages;
    }

    public MshSegment ParseMsh(string mshSegment)
    {
        var fields = (mshSegment ?? "").Split('|');

        return new MshSegment
        {
            SendingApplication = fields.Length > 2 ? fields[2] : "",
            SendingFacility = fields.Length > 3 ? fields[3] : "",
            MessageDateTime = fields.Length > 6 ? fields[6] : "",
            MessageType = fields.Length > 8 ? fields[8] : "",
            MessageControlId = fields.Length > 9 ? fields[9] : ""
        };
    }

    public PidSegment ParsePid(string pidSegment)
    {
        var fields = (pidSegment ?? "").Split('|');

        var patientId = fields.Length > 3 ? fields[3] : "";
        var patientNameField = fields.Length > 5 ? fields[5] : "";
        var dateOfBirth = fields.Length > 7 ? fields[7] : "";
        var sex = fields.Length > 8 ? fields[8] : "";

        var nameComponents = patientNameField.Split('^');
        var lastName = nameComponents.Length > 0 ? nameComponents[0] : "";
        var firstName = nameComponents.Length > 1 ? nameComponents[1] : "";
        var middleName = nameComponents.Length > 2 ? nameComponents[2] : "";

        var patientName = $"{lastName}, {firstName}";
        if (!string.IsNullOrWhiteSpace(middleName))
            patientName = $"{lastName}, {firstName} {middleName}";

        // Trim leading/trailing ", " like PS Trim(", ")
        patientName = patientName.Trim(',', ' ');

        return new PidSegment
        {
            PatientId = patientId,
            PatientName = patientName,
            LastName = lastName,
            FirstName = firstName,
            MiddleName = middleName,
            DateOfBirth = dateOfBirth,
            Sex = sex
        };
    }

    public ObrSegment ParseObr(string obrSegment)
    {
        var fields = (obrSegment ?? "").Split('|');

        // OBR-3: Filler Order Number — this is the lab's path report number.
        // IMPORTANT for future HL7→NAACCR XML mapping:
        //   HL7 AccessionNumber (OBR-3) = NAACCR pathReportNumber1 (item 7090)
        //   HL7 AccessionNumber (OBR-3) ≠ NAACCR accessionNumberHosp (item 380)
        //   accessionNumberHosp is a registry-assigned patient ID (YYYY + 5-digit seq),
        //   NOT the lab's specimen/report number.
        var accessionNumber = fields.Length > 3 ? fields[3] : "";

        var orderDateTime = fields.Length > 7 ? fields[7] : "";
        var orderingProviderField = fields.Length > 16 ? fields[16] : "";

        var providerComponents = orderingProviderField.Split('^');
        var providerId = providerComponents.Length > 0 ? providerComponents[0] : "";
        var providerLast = providerComponents.Length > 1 ? providerComponents[1] : "";
        var providerFirst = providerComponents.Length > 2 ? providerComponents[2] : "";

        var orderingProvider = $"{providerLast}, {providerFirst}";
        if (!string.IsNullOrWhiteSpace(providerId))
            orderingProvider = $"{orderingProvider} ({providerId})";

        orderingProvider = orderingProvider.Trim(',', ' ');

        return new ObrSegment
        {
            AccessionNumber = accessionNumber,
            OrderDateTime = orderDateTime,
            OrderingProvider = orderingProvider
        };
    }

    public List<ObxSegment> ParseObx(List<string> obxSegments)
    {
        var observations = new List<ObxSegment>();

        foreach (var obx in obxSegments)
        {
            var fields = obx.Split('|');

            observations.Add(new ObxSegment
            {
                SetId = fields.Length > 1 ? fields[1] : "",
                ValueType = fields.Length > 2 ? fields[2] : "",
                ObservationId = fields.Length > 3 ? fields[3] : "",
                ObservationValue = fields.Length > 5 ? fields[5] : "",
                Units = fields.Length > 6 ? fields[6] : "",
                ReferenceRange = fields.Length > 7 ? fields[7] : "",
                AbnormalFlag = fields.Length > 8 ? fields[8] : ""
            });
        }

        return observations;
    }

    public string FormatDateTime(string hl7DateTime)
    {
        if (string.IsNullOrWhiteSpace(hl7DateTime))
            return "";

        try
        {
            if (hl7DateTime.Length >= 8)
            {
                var year = hl7DateTime[..4];
                var month = hl7DateTime.Substring(4, 2);
                var day = hl7DateTime.Substring(6, 2);

                if (hl7DateTime.Length >= 14)
                {
                    var hour = hl7DateTime.Substring(8, 2);
                    var minute = hl7DateTime.Substring(10, 2);
                    var second = hl7DateTime.Substring(12, 2);
                    return $"{year}-{month}-{day} {hour}:{minute}:{second}";
                }
                return $"{year}-{month}-{day}";
            }
        }
        catch (Exception ex)
        {
            _logger.Log("WARN", $"Failed to parse HL7 datetime value: {hl7DateTime}", "HL7_PARSE_DATETIME", ex.Message);
        }

        return hl7DateTime;
    }

    public string GetObxTextContent(List<string> obxSegments)
    {
        if (obxSegments == null || obxSegments.Count == 0)
            return "";

        var textLines = new List<string>();

        foreach (var obx in obxSegments)
        {
            var fields = obx.Split('|');
            var observationValue = fields.Length > 5 ? fields[5] : "";

            if (string.IsNullOrWhiteSpace(observationValue))
                continue;

            // Replace HL7 escape sequences
            observationValue = Hl7EscapeHelper.Unescape(observationValue);

            textLines.Add(observationValue);
        }

        return string.Join("\r\n", textLines);
    }

    public string GetObx3Component1(string obxSegment)
    {
        if (string.IsNullOrWhiteSpace(obxSegment))
            return "";

        var fields = obxSegment.Split('|');
        if (fields.Length < 4)
            return "";

        var obx3 = fields[3];
        if (string.IsNullOrWhiteSpace(obx3))
            return "";

        var components = obx3.Split('^');
        return components[0].Trim();
    }

    public List<string> SelectObxSegments(List<string> obxSegments, List<string> skipCodes)
    {
        if (obxSegments == null || obxSegments.Count == 0)
            return new List<string>();

        if (skipCodes == null || skipCodes.Count == 0)
            return new List<string>(obxSegments);

        var skipCodesUpper = new HashSet<string>(
            skipCodes.Select(c => c.ToUpperInvariant()),
            StringComparer.OrdinalIgnoreCase);

        var filtered = new List<string>();
        foreach (var obx in obxSegments)
        {
            var obx3Code = GetObx3Component1(obx).ToUpperInvariant();
            if (!skipCodesUpper.Contains(obx3Code))
                filtered.Add(obx);
        }

        return filtered;
    }

    public string GetFilteredObxTextContent(List<string> obxSegments, List<string> skipCodes)
    {
        var filtered = SelectObxSegments(obxSegments, skipCodes);
        return GetObxTextContent(filtered);
    }
}
