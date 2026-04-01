using System.Xml;
using Parrat.Core.Interfaces;
using Parrat.Core.Models;

namespace Parrat.Core.Services;

public class DeduplicationService : IDeduplicationService
{
    private static readonly HashSet<string> IgnoredFields = new(StringComparer.Ordinal)
    {
        "dateCaseReportReceived",
        "dateCaseReportLoaded",
        "dateCaseReportExported",
        "pathDateSpecCollect1",
        "pathDateSpecCollect2",
        "pathDateSpecCollect3",
        "pathDateSpecCollect4",
        "pathDateSpecCollect5",
        "physician3",
        "physicianManaging",
        "physicianFollowUp"
    };

    public Dictionary<string, List<(int Index, XmlNode Tumor, XmlNode Patient)>> GetPatientTumorGroups(
        XmlNodeList tumors, XmlNamespaceManager nsMgr)
    {
        var groups = new Dictionary<string, List<(int Index, XmlNode Tumor, XmlNode Patient)>>();

        for (int i = 0; i < tumors.Count; i++)
        {
            var tumor = tumors[i]!;
            var patient = tumor.SelectSingleNode("ancestor::n:Patient[1]", nsMgr);

            string nameLast = "";
            string nameFirst = "";
            string dateOfBirth = "";
            string dateOfDiagnosis = "";
            string pathReportNumber1 = "";

            if (patient != null)
            {
                nameLast = GetNodeText(patient, "./n:Item[@naaccrId='nameLast']", nsMgr);
                nameFirst = GetNodeText(patient, "./n:Item[@naaccrId='nameFirst']", nsMgr);
                dateOfBirth = GetNodeText(patient, "./n:Item[@naaccrId='dateOfBirth']", nsMgr);
            }

            dateOfDiagnosis = GetNodeText(tumor, "./n:Item[@naaccrId='dateOfDiagnosis']", nsMgr);
            pathReportNumber1 = GetNodeText(tumor, "./n:Item[@naaccrId='pathReportNumber1']", nsMgr);

            string key = $"{nameLast}|{nameFirst}|{dateOfBirth}|{dateOfDiagnosis}|{pathReportNumber1}";

            if (!groups.ContainsKey(key))
                groups[key] = new List<(int, XmlNode, XmlNode)>();

            groups[key].Add((i, tumor, patient!));
        }

        return groups;
    }

    public string GetTumorFingerprint(XmlNode tumor, XmlNode patient, XmlNamespaceManager nsMgr)
    {
        var items = new List<string>();

        // Patient items
        if (patient != null)
        {
            var pItems = patient.SelectNodes("./n:Item", nsMgr);
            if (pItems != null)
            {
                foreach (XmlNode item in pItems)
                {
                    string id = item.Attributes?["naaccrId"]?.Value ?? "";
                    string val = item.InnerText;

                    if (!IgnoredFields.Contains(id))
                        items.Add($"P|{id}|{val}");
                }
            }
        }

        // Tumor items
        var tItems = tumor.SelectNodes("./n:Item", nsMgr);
        if (tItems != null)
        {
            foreach (XmlNode item in tItems)
            {
                string id = item.Attributes?["naaccrId"]?.Value ?? "";
                string val = item.InnerText;

                if (!IgnoredFields.Contains(id))
                    items.Add($"T|{id}|{val}");
            }
        }

        items.Sort(StringComparer.Ordinal);
        return string.Join("||", items);
    }

    public DeduplicationResult GetDuplicates(XmlNodeList tumors, XmlNamespaceManager nsMgr)
    {
        var patientGroups = GetPatientTumorGroups(tumors, nsMgr);
        var report = new List<DuplicateReport>();
        var indicesToKeep = new HashSet<int>();

        foreach (var kvp in patientGroups)
        {
            var group = kvp.Value;
            if (group == null || group.Count == 0)
                continue;

            if (group.Count == 1)
            {
                indicesToKeep.Add(group[0].Index);
                continue;
            }

            // Build fingerprint groups for this patient group
            var fingerprintGroups = new Dictionary<string, List<(int Index, XmlNode Tumor, XmlNode Patient)>>();

            foreach (var item in group)
            {
                string fingerprint = GetTumorFingerprint(item.Tumor, item.Patient, nsMgr);

                if (!fingerprintGroups.ContainsKey(fingerprint))
                    fingerprintGroups[fingerprint] = new List<(int, XmlNode, XmlNode)>();

                fingerprintGroups[fingerprint].Add(item);
            }

            foreach (var fpKvp in fingerprintGroups)
            {
                var dupGroup = fpKvp.Value;

                if (dupGroup.Count == 1)
                {
                    indicesToKeep.Add(dupGroup[0].Index);
                }
                else
                {
                    var winner = ApplyTiebreakerRules(dupGroup, nsMgr);
                    indicesToKeep.Add(winner.Index);

                    string allIndices = string.Join(",", dupGroup.Select(d => d.Index + 1));
                    string removedIndices = string.Join(",", dupGroup.Where(d => d.Index != winner.Index).Select(d => d.Index + 1));

                    string dateLoaded = GetTiebreakerValue(winner.Tumor, nsMgr, "dateCaseReportLoaded");
                    string dateReceived = GetTiebreakerValue(winner.Tumor, nsMgr, "dateCaseReportReceived");
                    string physician3 = GetTiebreakerValue(winner.Tumor, nsMgr, "physician3");

                    string reason = !string.IsNullOrWhiteSpace(dateLoaded) ? "Earliest dateCaseReportLoaded"
                        : !string.IsNullOrWhiteSpace(dateReceived) ? "Earliest dateCaseReportReceived"
                        : !string.IsNullOrWhiteSpace(physician3) ? "Non-empty physician3"
                        : "First occurrence";

                    report.Add(new DuplicateReport
                    {
                        PatientKey = kvp.Key,
                        AllIndices = allIndices,
                        KeptIndex = winner.Index + 1,
                        RemovedIndices = removedIndices,
                        Reason = reason,
                        DateReceived = dateReceived,
                        Physician3 = physician3
                    });
                }
            }
        }

        return new DeduplicationResult { IndicesToKeep = indicesToKeep, Report = report };
    }

    public DeduplicationResult GetDuplicatesByPrimaryKey(XmlNodeList tumors, XmlNamespaceManager nsMgr)
    {
        var primaryKeyGroups = new Dictionary<string, List<(int Index, XmlNode Tumor, XmlNode Patient)>>();
        var report = new List<DuplicateReport>();
        var indicesToKeep = new HashSet<int>();

        for (int i = 0; i < tumors.Count; i++)
        {
            var tumor = tumors[i]!;
            var patient = tumor.SelectSingleNode("ancestor::n:Patient[1]", nsMgr);

            string nameLast = "";
            string nameFirst = "";
            string dateOfBirth = "";
            string primarySite = "";
            string laterality = "";

            if (patient != null)
            {
                nameLast = GetNodeText(patient, "./n:Item[@naaccrId='nameLast']", nsMgr);
                nameFirst = GetNodeText(patient, "./n:Item[@naaccrId='nameFirst']", nsMgr);
                dateOfBirth = GetNodeText(patient, "./n:Item[@naaccrId='dateOfBirth']", nsMgr);
            }

            primarySite = GetNodeText(tumor, "./n:Item[@naaccrId='primarySite']", nsMgr);
            laterality = GetNodeText(tumor, "./n:Item[@naaccrId='laterality']", nsMgr);

            string key = $"{nameLast}|{nameFirst}|{dateOfBirth}|{primarySite}|{laterality}";

            if (string.IsNullOrWhiteSpace(key))
            {
                indicesToKeep.Add(i);
                continue;
            }

            if (!primaryKeyGroups.ContainsKey(key))
                primaryKeyGroups[key] = new List<(int, XmlNode, XmlNode)>();

            primaryKeyGroups[key].Add((i, tumor, patient!));
        }

        foreach (var kvp in primaryKeyGroups)
        {
            var group = kvp.Value;

            if (group.Count == 1)
            {
                indicesToKeep.Add(group[0].Index);
                continue;
            }

            var winner = ApplyTiebreakerRules(group, nsMgr);
            indicesToKeep.Add(winner.Index);

            string allIndices = string.Join(",", group.Select(d => d.Index + 1));
            string removedIndices = string.Join(",", group.Where(d => d.Index != winner.Index).Select(d => d.Index + 1));

            string dateLoaded = GetTiebreakerValue(winner.Tumor, nsMgr, "dateCaseReportLoaded");
            string dateReceived = GetTiebreakerValue(winner.Tumor, nsMgr, "dateCaseReportReceived");
            string physician3 = GetTiebreakerValue(winner.Tumor, nsMgr, "physician3");

            string reason = !string.IsNullOrWhiteSpace(dateLoaded) ? "Earliest dateCaseReportLoaded"
                : !string.IsNullOrWhiteSpace(dateReceived) ? "Earliest dateCaseReportReceived"
                : !string.IsNullOrWhiteSpace(physician3) ? "Non-empty physician3"
                : "First occurrence";

            report.Add(new DuplicateReport
            {
                PatientKey = $"PrimaryKey: {kvp.Key}",
                AllIndices = allIndices,
                KeptIndex = winner.Index + 1,
                RemovedIndices = removedIndices,
                Reason = reason,
                DateReceived = dateReceived,
                Physician3 = physician3
            });
        }

        return new DeduplicationResult { IndicesToKeep = indicesToKeep, Report = report };
    }

    public DeduplicationResult GetDuplicatesByPathReport(XmlNodeList tumors, XmlNamespaceManager nsMgr)
    {
        var pathReportGroups = new Dictionary<string, List<(int Index, XmlNode Tumor, XmlNode Patient)>>();
        var report = new List<DuplicateReport>();
        var indicesToKeep = new HashSet<int>();

        for (int i = 0; i < tumors.Count; i++)
        {
            var tumor = tumors[i]!;
            string pathReportNumber1 = GetNodeText(tumor, "./n:Item[@naaccrId='pathReportNumber1']", nsMgr);

            if (string.IsNullOrWhiteSpace(pathReportNumber1))
            {
                indicesToKeep.Add(i);
                continue;
            }

            if (!pathReportGroups.ContainsKey(pathReportNumber1))
                pathReportGroups[pathReportNumber1] = new List<(int, XmlNode, XmlNode)>();

            var patient = tumor.SelectSingleNode("ancestor::n:Patient[1]", nsMgr);
            pathReportGroups[pathReportNumber1].Add((i, tumor, patient!));
        }

        foreach (var kvp in pathReportGroups)
        {
            var group = kvp.Value;

            if (group.Count == 1)
            {
                indicesToKeep.Add(group[0].Index);
                continue;
            }

            var winner = ApplyTiebreakerRules(group, nsMgr);
            indicesToKeep.Add(winner.Index);

            string allIndices = string.Join(",", group.Select(d => d.Index + 1));
            string removedIndices = string.Join(",", group.Where(d => d.Index != winner.Index).Select(d => d.Index + 1));

            string dateLoaded = GetTiebreakerValue(winner.Tumor, nsMgr, "dateCaseReportLoaded");
            string dateReceived = GetTiebreakerValue(winner.Tumor, nsMgr, "dateCaseReportReceived");
            string physician3 = GetTiebreakerValue(winner.Tumor, nsMgr, "physician3");

            string reason = !string.IsNullOrWhiteSpace(dateLoaded) ? "Earliest dateCaseReportLoaded"
                : !string.IsNullOrWhiteSpace(dateReceived) ? "Earliest dateCaseReportReceived"
                : !string.IsNullOrWhiteSpace(physician3) ? "Non-empty physician3"
                : "First occurrence";

            report.Add(new DuplicateReport
            {
                PatientKey = $"pathReportNumber1: {kvp.Key}",
                AllIndices = allIndices,
                KeptIndex = winner.Index + 1,
                RemovedIndices = removedIndices,
                Reason = reason,
                DateReceived = dateReceived,
                Physician3 = physician3
            });
        }

        return new DeduplicationResult { IndicesToKeep = indicesToKeep, Report = report };
    }

    public void WriteDedupedXml(XmlDocument xmlDoc, XmlNodeList tumors, HashSet<int> indicesToKeep, string outputPath)
    {
        var newDoc = new XmlDocument();
        newDoc.XmlResolver = null;

        // Copy XML declaration
        foreach (XmlNode child in xmlDoc.ChildNodes)
        {
            if (child is XmlDeclaration decl)
            {
                var newDecl = newDoc.CreateXmlDeclaration(decl.Version, decl.Encoding, decl.Standalone);
                newDoc.AppendChild(newDecl);
                break;
            }
        }

        var root = xmlDoc.DocumentElement!;
        var newRoot = newDoc.CreateElement(root.Prefix, root.LocalName, root.NamespaceURI);
        CopyAttributes(root, newRoot, newDoc);
        newDoc.AppendChild(newRoot);

        // Copy non-Patient children
        foreach (XmlNode child in root.ChildNodes)
        {
            if (child.LocalName != "Patient")
            {
                var imported = newDoc.ImportNode(child, true);
                newRoot.AppendChild(imported);
            }
        }

        // Build set of kept tumor nodes
        var keptTumorNodes = new HashSet<XmlNode>();
        for (int i = 0; i < tumors.Count; i++)
        {
            if (indicesToKeep.Contains(i))
                keptTumorNodes.Add(tumors[i]!);
        }

        var nsMgr2 = new XmlNamespaceManager(xmlDoc.NameTable);
        nsMgr2.AddNamespace("n", root.NamespaceURI);

        foreach (XmlNode patientNode in root.SelectNodes("./n:Patient", nsMgr2)!)
        {
            var tumorsInPatient = patientNode.SelectNodes("./n:Tumor", nsMgr2)!;

            bool hasKeptTumor = false;
            foreach (XmlNode tumor in tumorsInPatient)
            {
                if (keptTumorNodes.Contains(tumor))
                {
                    hasKeptTumor = true;
                    break;
                }
            }

            if (hasKeptTumor)
            {
                var newPatient = newDoc.CreateElement(patientNode.Prefix, patientNode.LocalName, patientNode.NamespaceURI);
                CopyAttributes(patientNode, newPatient, newDoc);

                foreach (XmlNode child in patientNode.ChildNodes)
                {
                    if (child.LocalName == "Item")
                    {
                        var imported = newDoc.ImportNode(child, true);
                        newPatient.AppendChild(imported);
                    }
                }

                foreach (XmlNode tumor in tumorsInPatient)
                {
                    if (keptTumorNodes.Contains(tumor))
                    {
                        var imported = newDoc.ImportNode(tumor, true);
                        newPatient.AppendChild(imported);
                    }
                }

                newRoot.AppendChild(newPatient);
            }
        }

        WriteXmlDocument(newDoc, outputPath);
    }

    // --- Private helpers ---

    private static string GetNodeText(XmlNode context, string xpath, XmlNamespaceManager nsMgr)
    {
        var node = context.SelectSingleNode(xpath, nsMgr);
        return node?.InnerText ?? "";
    }

    private static string GetTiebreakerValue(XmlNode tumor, XmlNamespaceManager nsMgr, string fieldId)
    {
        var node = tumor.SelectSingleNode($"./n:Item[@naaccrId='{fieldId}']", nsMgr);
        return node?.InnerText ?? "";
    }

    private static (int Index, XmlNode Tumor, XmlNode Patient) ApplyTiebreakerRules(
        List<(int Index, XmlNode Tumor, XmlNode Patient)> group, XmlNamespaceManager nsMgr)
    {
        if (group.Count == 1)
            return group[0];

        // Rule 1: earliest dateCaseReportLoaded
        var withLoaded = group
            .Where(g => !string.IsNullOrWhiteSpace(GetTiebreakerValue(g.Tumor, nsMgr, "dateCaseReportLoaded")))
            .OrderBy(g => GetTiebreakerValue(g.Tumor, nsMgr, "dateCaseReportLoaded"))
            .ToList();

        if (withLoaded.Count > 0)
            return withLoaded[0];

        // Rule 2: earliest dateCaseReportReceived
        var withDates = group
            .Where(g => !string.IsNullOrWhiteSpace(GetTiebreakerValue(g.Tumor, nsMgr, "dateCaseReportReceived")))
            .OrderBy(g => GetTiebreakerValue(g.Tumor, nsMgr, "dateCaseReportReceived"))
            .ToList();

        if (withDates.Count > 0)
        {
            string earliestDate = GetTiebreakerValue(withDates[0].Tumor, nsMgr, "dateCaseReportReceived");
            var candidates = withDates.TakeWhile(g =>
                GetTiebreakerValue(g.Tumor, nsMgr, "dateCaseReportReceived") == earliestDate).ToList();

            if (candidates.Count > 1)
            {
                // Rule 3: prefer non-empty physician3
                var withPhysician = candidates
                    .Where(g => !string.IsNullOrWhiteSpace(GetTiebreakerValue(g.Tumor, nsMgr, "physician3")))
                    .ToList();

                if (withPhysician.Count > 0)
                    return withPhysician[0];
            }

            return candidates[0];
        }

        // No dates found, try Rule 3 directly
        var withPhys = group
            .Where(g => !string.IsNullOrWhiteSpace(GetTiebreakerValue(g.Tumor, nsMgr, "physician3")))
            .ToList();

        if (withPhys.Count > 0)
            return withPhys[0];

        // Rule 4: first occurrence
        return group[0];
    }

    private static void CopyAttributes(XmlNode source, XmlElement target, XmlDocument newDoc)
    {
        if (source.Attributes == null) return;
        foreach (XmlAttribute attr in source.Attributes)
        {
            var newAttr = newDoc.CreateAttribute(attr.Prefix, attr.LocalName, attr.NamespaceURI);
            newAttr.Value = attr.Value;
            target.Attributes.Append(newAttr);
        }
    }

    private static void WriteXmlDocument(XmlDocument doc, string outputPath)
    {
        var settings = new XmlWriterSettings
        {
            Indent = true,
            NewLineChars = "\r\n",
            NewLineHandling = NewLineHandling.Replace
        };

        using var writer = XmlWriter.Create(outputPath, settings);
        doc.Save(writer);
    }
}
