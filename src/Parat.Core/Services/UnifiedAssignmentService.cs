using System.Text.RegularExpressions;
using System.Xml;
using Parat.Core.Interfaces;

namespace Parat.Core.Services;

public class UnifiedAssignmentService : IUnifiedAssignmentService
{
    private readonly ISiteLateralityService? _siteLateralityService;

    public UnifiedAssignmentService()
    {
    }

    public UnifiedAssignmentService(ISiteLateralityService? siteLateralityService)
    {
        _siteLateralityService = siteLateralityService;
    }

    public (Dictionary<int, Dictionary<string, string>> TumorAssignments,
        Dictionary<int, Dictionary<string, string>> PatientAssignments,
        List<Dictionary<string, object>> Report) GetUnifiedAssignments(
        XmlNodeList tumors, XmlNamespaceManager nsMgr, Dictionary<string, object> options)
    {
        var report = new List<Dictionary<string, object>>();
        var tumorAssignments = new Dictionary<int, Dictionary<string, string>>();
        var patientAssignments = new Dictionary<int, Dictionary<string, string>>();
        var processedPatients = new HashSet<XmlNode>(ReferenceEqualityComparer.Instance);
        // We also need a map from patient node -> its first tumor index for the patient assignments
        var patientToFirstTumor = new Dictionary<XmlNode, int>(ReferenceEqualityComparer.Instance);
        int pidCounter = 0;

        bool assignSite = GetBool(options, "AssignSite");
        bool assignLaterality = GetBool(options, "AssignLaterality");
        bool assignFacility = GetBool(options, "AssignFacility");
        bool assignPid = GetBool(options, "AssignPid");
        bool siteOverride = GetBool(options, "SiteOverride");
        bool lateralityOverride = GetBool(options, "LateralityOverride");
        bool facilityOverride = GetBool(options, "FacilityOverride");
        string facilityNumber = GetString(options, "FacilityNumber");
        string pidMode = GetString(options, "PidMode", "Default");
        int pidStartingNumber = GetInt(options, "PidStartingNumber", 1);

        if (pidMode == "ReplaceZeros")
            pidStartingNumber = 90000001;

        for (int i = 0; i < tumors.Count; i++)
        {
            var tumor = tumors[i]!;
            var patient = tumor.SelectSingleNode("ancestor::n:Patient[1]", nsMgr);

            string nameLast = patient?.SelectSingleNode("./n:Item[@naaccrId='nameLast']", nsMgr)?.InnerText ?? "";
            string nameFirst = patient?.SelectSingleNode("./n:Item[@naaccrId='nameFirst']", nsMgr)?.InnerText ?? "";
            string patientName = $"{nameLast}, {nameFirst}".Trim(',', ' ');

            string currentSite = (tumor.SelectSingleNode("./n:Item[@naaccrId='primarySite']", nsMgr)?.InnerText ?? "").Trim();
            string currentLat = (tumor.SelectSingleNode("./n:Item[@naaccrId='laterality']", nsMgr)?.InnerText ?? "").Trim();
            string currentFacility = (tumor.SelectSingleNode("./n:Item[@naaccrId='reportingFacility']", nsMgr)?.InnerText ?? "").Trim();

            var entry = new Dictionary<string, object>
            {
                ["TumorIndex"] = i + 1,
                ["PatientName"] = patientName,
                ["CurrentSite"] = currentSite,
                ["ProposedSite"] = "",
                ["CurrentLaterality"] = currentLat,
                ["ProposedLaterality"] = "",
                ["CurrentFacility"] = currentFacility,
                ["ProposedFacility"] = "",
                ["CurrentPid"] = "",
                ["ProposedPid"] = "",
                ["SourceText"] = "",
                ["HasChanges"] = false
            };

            var tumorAssignment = new Dictionary<string, string>();

            // --- Site/Laterality Assignment ---
            if (assignSite || assignLaterality)
            {
                bool hasSite = !string.IsNullOrWhiteSpace(currentSite);
                bool hasLat = !string.IsNullOrWhiteSpace(currentLat);

                string textPath = tumor.SelectSingleNode("./n:Item[@naaccrId='textDxProcPath']", nsMgr)?.InnerText ?? "";
                string textPe = tumor.SelectSingleNode("./n:Item[@naaccrId='textDxProcPe']", nsMgr)?.InnerText ?? "";
                string textLab = tumor.SelectSingleNode("./n:Item[@naaccrId='textDxProcLabTests']", nsMgr)?.InnerText ?? "";

                string textCombined = (textPath + " " + textPe).Trim();
                if (string.IsNullOrEmpty(textCombined))
                    textCombined = textLab.Trim();

                string proposedSite = "";
                string proposedLat = "";

                if (!string.IsNullOrEmpty(textCombined))
                {
                    string low = textCombined.ToLower();

                    bool needsSite = assignSite && (!hasSite || siteOverride);
                    if (needsSite && _siteLateralityService != null)
                    {
                        var bestCode = _siteLateralityService.GetBestCode(new List<Models.TopographyEntry>(), low);
                        proposedSite = bestCode.PrimarySite ?? "";
                    }

                    string siteToCheck = !string.IsNullOrEmpty(proposedSite) ? proposedSite
                        : hasSite ? currentSite : "";

                    bool needsLat = assignLaterality && (!hasLat || lateralityOverride);
                    if (needsLat && !string.IsNullOrEmpty(siteToCheck) && _siteLateralityService != null)
                    {
                        string? detectedLat = _siteLateralityService.GetLaterality(low);
                        proposedLat = detectedLat ?? "9";
                    }

                    if (!string.IsNullOrEmpty(proposedSite) || !string.IsNullOrEmpty(proposedLat))
                    {
                        entry["SourceText"] = textCombined.Length > 200 ? textCombined[..200] + "..." : textCombined;
                    }
                }

                if (!string.IsNullOrEmpty(proposedSite))
                {
                    entry["ProposedSite"] = proposedSite;
                    tumorAssignment["PrimarySite"] = proposedSite;
                    entry["HasChanges"] = true;
                }

                if (!string.IsNullOrEmpty(proposedLat))
                {
                    entry["ProposedLaterality"] = proposedLat;
                    tumorAssignment["Laterality"] = proposedLat;
                    entry["HasChanges"] = true;
                }
            }

            // --- Facility Assignment ---
            if (assignFacility)
            {
                bool needsFacility = facilityOverride ||
                                     string.IsNullOrWhiteSpace(currentFacility) ||
                                     Regex.IsMatch(currentFacility, @"^0+$");

                if (needsFacility)
                {
                    entry["ProposedFacility"] = facilityNumber;
                    tumorAssignment["ReportingFacility"] = facilityNumber;
                    entry["HasChanges"] = true;
                }
            }

            // --- Patient ID Assignment ---
            if (assignPid && patient != null)
            {
                if (!patientToFirstTumor.ContainsKey(patient))
                    patientToFirstTumor[patient] = i;

                if (!processedPatients.Contains(patient))
                {
                    processedPatients.Add(patient);

                    string currentPid = patient.SelectSingleNode("./n:Item[@naaccrId='patientIdNumber']", nsMgr)?.InnerText ?? "";
                    entry["CurrentPid"] = string.IsNullOrWhiteSpace(currentPid) ? "(none)" : currentPid;

                    bool hasPid = !string.IsNullOrWhiteSpace(currentPid);
                    bool shouldAssignPid = false;
                    string pidValue = "";

                    if (pidMode == "OverwriteAll")
                    {
                        shouldAssignPid = true;
                        pidCounter++;
                        pidValue = (pidStartingNumber + pidCounter - 1).ToString("D8");
                    }
                    else if (pidMode == "ReplaceZeros")
                    {
                        if (!hasPid || Regex.IsMatch(currentPid, @"^0+$"))
                        {
                            shouldAssignPid = true;
                            pidCounter++;
                            pidValue = (pidStartingNumber + pidCounter - 1).ToString("D8");
                        }
                    }
                    else
                    {
                        if (!hasPid)
                        {
                            shouldAssignPid = true;
                            pidCounter++;
                            pidValue = (pidStartingNumber + pidCounter - 1).ToString("D8");
                        }
                    }

                    if (shouldAssignPid)
                    {
                        entry["ProposedPid"] = pidValue;
                        int patientKey = patientToFirstTumor[patient];
                        patientAssignments[patientKey] = new Dictionary<string, string>
                        {
                            ["patientIdNumber"] = pidValue
                        };
                        entry["HasChanges"] = true;
                    }
                }
                else
                {
                    string currentPid = patient.SelectSingleNode("./n:Item[@naaccrId='patientIdNumber']", nsMgr)?.InnerText ?? "";
                    entry["CurrentPid"] = string.IsNullOrWhiteSpace(currentPid) ? "(none)" : currentPid;

                    int patientKey = patientToFirstTumor[patient];
                    if (patientAssignments.TryGetValue(patientKey, out var existingAssignment))
                        entry["ProposedPid"] = existingAssignment["patientIdNumber"];
                }
            }

            if (tumorAssignment.Count > 0)
                tumorAssignments[i] = tumorAssignment;

            report.Add(entry);
        }

        return (tumorAssignments, patientAssignments, report);
    }

    public void WriteUnifiedAssignedXml(XmlDocument xmlDoc, XmlNodeList tumors,
        Dictionary<int, Dictionary<string, string>> tumorAssignments,
        Dictionary<int, Dictionary<string, string>> patientAssignments,
        XmlNamespaceManager nsMgr, string outputPath)
    {
        // Build patient node -> id value map from patientAssignments
        // patientAssignments keys are tumor indices (first tumor of each patient)
        var patientIdMap = new Dictionary<XmlNode, string>(ReferenceEqualityComparer.Instance);
        foreach (var kvp in patientAssignments)
        {
            if (kvp.Key < tumors.Count && kvp.Value.TryGetValue("patientIdNumber", out var pidValue))
            {
                var tumor = tumors[kvp.Key]!;
                var patient = tumor.SelectSingleNode("ancestor::n:Patient[1]", nsMgr);
                if (patient != null)
                    patientIdMap[patient] = pidValue;
            }
        }

        var newDoc = new XmlDocument();
        newDoc.XmlResolver = null;

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

        foreach (XmlNode child in root.ChildNodes)
        {
            if (child.LocalName != "Patient")
            {
                var imported = newDoc.ImportNode(child, true);
                newRoot.AppendChild(imported);
            }
        }

        foreach (XmlNode patientNode in root.SelectNodes("./n:Patient", nsMgr)!)
        {
            var newPatient = newDoc.CreateElement(patientNode.Prefix, patientNode.LocalName, patientNode.NamespaceURI);
            CopyAttributes(patientNode, newPatient, newDoc);

            bool needsPid = patientIdMap.TryGetValue(patientNode, out var patientIdValue);
            var tumorsInPatient = patientNode.SelectNodes("./n:Tumor", nsMgr)!;
            XmlNode? firstTumor = tumorsInPatient.Count > 0 ? tumorsInPatient[0] : null;
            bool patientIdAdded = false;

            foreach (XmlNode childNode in patientNode.ChildNodes)
            {
                if (childNode.LocalName == "Item")
                {
                    string idAttr = childNode.Attributes?["naaccrId"]?.Value ?? "";

                    if (idAttr == "patientIdNumber")
                    {
                        var imported = newDoc.ImportNode(childNode, true);
                        if (needsPid)
                            imported.InnerText = patientIdValue!;
                        newPatient.AppendChild(imported);
                        patientIdAdded = true;
                    }
                    else
                    {
                        var imported = newDoc.ImportNode(childNode, true);
                        newPatient.AppendChild(imported);
                    }
                }
                else if (childNode.LocalName == "Tumor")
                {
                    if (childNode == firstTumor && needsPid && !patientIdAdded)
                    {
                        var item = newDoc.CreateElement("Item", root.NamespaceURI);
                        item.SetAttribute("naaccrId", "patientIdNumber");
                        item.SetAttribute("naaccrNum", "20");
                        item.InnerText = patientIdValue!;
                        newPatient.AppendChild(item);
                        patientIdAdded = true;
                    }

                    int tumorIndex = FindTumorIndex(tumors, childNode);
                    var newTumor = newDoc.ImportNode(childNode, true);

                    if (tumorIndex >= 0 && tumorAssignments.TryGetValue(tumorIndex, out var assignment))
                    {
                        if (assignment.TryGetValue("PrimarySite", out var site))
                            SetOrCreateItem(newTumor, "primarySite", site, root.NamespaceURI, nsMgr, newDoc);

                        if (assignment.TryGetValue("Laterality", out var lat))
                            SetOrCreateItem(newTumor, "laterality", lat, root.NamespaceURI, nsMgr, newDoc);

                        if (assignment.TryGetValue("ReportingFacility", out var fac))
                            SetOrCreateItem(newTumor, "reportingFacility", fac, root.NamespaceURI, nsMgr, newDoc);
                    }

                    newPatient.AppendChild(newTumor);
                }
            }

            if (needsPid && !patientIdAdded)
            {
                var item = newDoc.CreateElement("Item", root.NamespaceURI);
                item.SetAttribute("naaccrId", "patientIdNumber");
                item.SetAttribute("naaccrNum", "20");
                item.InnerText = patientIdValue!;
                newPatient.AppendChild(item);
            }

            newRoot.AppendChild(newPatient);
        }

        var settings = new XmlWriterSettings
        {
            Indent = true,
            IndentChars = "  ",
            NewLineChars = "\r\n",
            NewLineHandling = NewLineHandling.Replace
        };

        using var writer = XmlWriter.Create(outputPath, settings);
        newDoc.Save(writer);
    }

    public string GetFileSuffix(Dictionary<string, object> options, List<Dictionary<string, object>> report)
    {
        var suffixParts = new List<string>();

        bool hasSiteChanges = report.Any(r => r.TryGetValue("ProposedSite", out var v) && v is string s && !string.IsNullOrEmpty(s));
        bool hasLatChanges = report.Any(r => r.TryGetValue("ProposedLaterality", out var v) && v is string s && !string.IsNullOrEmpty(s));
        bool hasFacChanges = report.Any(r => r.TryGetValue("ProposedFacility", out var v) && v is string s && !string.IsNullOrEmpty(s));
        bool hasPidChanges = report.Any(r => r.TryGetValue("ProposedPid", out var v) && v is string s && !string.IsNullOrEmpty(s));

        if (GetBool(options, "AssignSite") && hasSiteChanges) suffixParts.Add("psite");
        if (GetBool(options, "AssignLaterality") && hasLatChanges) suffixParts.Add("lat");
        if (GetBool(options, "AssignFacility") && hasFacChanges) suffixParts.Add("fac");
        if (GetBool(options, "AssignPid") && hasPidChanges) suffixParts.Add("pid");

        return suffixParts.Count == 0 ? "assigned" : string.Join("-", suffixParts);
    }

    // --- Helpers ---

    private static bool GetBool(Dictionary<string, object> dict, string key)
    {
        if (dict.TryGetValue(key, out var val))
        {
            if (val is bool b) return b;
            if (val is string s) return bool.TryParse(s, out var r) && r;
        }
        return false;
    }

    private static string GetString(Dictionary<string, object> dict, string key, string defaultValue = "")
    {
        if (dict.TryGetValue(key, out var val) && val is string s)
            return s;
        return defaultValue;
    }

    private static int GetInt(Dictionary<string, object> dict, string key, int defaultValue = 0)
    {
        if (dict.TryGetValue(key, out var val))
        {
            if (val is int i) return i;
            if (val is long l) return (int)l;
            if (val is string s && int.TryParse(s, out var r)) return r;
        }
        return defaultValue;
    }

    private static int FindTumorIndex(XmlNodeList tumors, XmlNode tumor)
    {
        for (int i = 0; i < tumors.Count; i++)
        {
            if (tumors[i] == tumor)
                return i;
        }
        return -1;
    }

    private static void SetOrCreateItem(XmlNode tumorNode, string naaccrId, string value,
        string namespaceUri, XmlNamespaceManager nsMgr, XmlDocument newDoc)
    {
        var node = tumorNode.SelectSingleNode($"./n:Item[@naaccrId='{naaccrId}']", nsMgr);
        if (node != null)
        {
            node.InnerText = value;
        }
        else
        {
            var itemNode = newDoc.CreateElement("Item", namespaceUri);
            var attr = newDoc.CreateAttribute("naaccrId");
            attr.Value = naaccrId;
            itemNode.Attributes!.Append(attr);
            itemNode.InnerText = value;
            tumorNode.AppendChild(itemNode);
        }
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
}
