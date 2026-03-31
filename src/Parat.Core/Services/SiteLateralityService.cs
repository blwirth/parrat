using System.Text.Json;
using System.Text.RegularExpressions;
using System.Xml;
using Parat.Core.Interfaces;
using Parat.Core.Models;

namespace Parat.Core.Services;

public class SiteLateralityService : ISiteLateralityService
{
    // Cache for loaded data
    private List<TopographyEntry>? _topoMapCache;
    private List<TopographyEntry>? _melTopoMapCache;
    private Dictionary<string, bool>? _lateralityCodesCache;
    private List<SiteCodingRule>? _siteCodingRulesCache;

    public List<TopographyEntry> ReadTopographyJson(string path)
    {
        if (!File.Exists(path))
            throw new FileNotFoundException($"JSON file not found: {path}");

        var items = new List<TopographyEntry>();
        var lines = File.ReadAllLines(path);

        foreach (var line in lines)
        {
            if (string.IsNullOrWhiteSpace(line)) continue;

            try
            {
                var item = JsonSerializer.Deserialize<TopographyEntry>(line, new JsonSerializerOptions
                {
                    PropertyNameCaseInsensitive = true
                });
                if (item != null && !string.IsNullOrEmpty(item.Code) && !string.IsNullOrEmpty(item.SearchPhrase))
                    items.Add(item);
            }
            catch
            {
                // Skip malformed lines
            }
        }

        return items;
    }

    public Dictionary<string, bool> ReadLateralityJson(string path)
    {
        if (!File.Exists(path))
            throw new FileNotFoundException($"JSON file not found: {path}");

        string json = File.ReadAllText(path);
        var codes = new Dictionary<string, bool>();
        var array = JsonSerializer.Deserialize<string[]>(json);

        if (array != null)
        {
            foreach (var code in array)
                codes[code] = true;
        }

        return codes;
    }

    public List<SiteCodingRule> ReadSiteCodingRules(string path)
    {
        if (!File.Exists(path))
            return new List<SiteCodingRule>();

        var patterns = new List<SiteCodingRule>();
        var lines = File.ReadAllLines(path);

        foreach (var line in lines)
        {
            if (string.IsNullOrWhiteSpace(line)) continue;

            try
            {
                var pattern = JsonSerializer.Deserialize<SiteCodingRule>(line, new JsonSerializerOptions
                {
                    PropertyNameCaseInsensitive = true
                });
                if (pattern != null && !string.IsNullOrEmpty(pattern.Code) && pattern.Enabled)
                    patterns.Add(pattern);
            }
            catch
            {
                // Skip malformed lines
            }
        }

        // Sort by Priority ascending
        patterns.Sort((a, b) => a.Priority.CompareTo(b.Priority));
        return patterns;
    }

    public SiteCodingTestResult TestSiteCodingRule(SiteCodingRule rule, string textLow, List<TopographyEntry>? topoMap = null)
    {
        var expressionResults = new List<(bool Matched, string Term, string? TopoCode)>();

        foreach (var item in rule.Expression)
        {
            bool itemMatched = false;
            string itemMatchedTerm = "";
            string? itemTopoCode = null;

            if (item.Type == "term" && item.Value != null)
            {
                string escaped = Regex.Escape(item.Value);
                string regexPattern = $"(?<![a-zA-Z]){escaped}(?![a-zA-Z])";
                var match = Regex.Match(textLow, regexPattern);
                if (match.Success)
                {
                    itemMatched = true;
                    itemMatchedTerm = item.Value;
                }
            }
            else if (item.Type == "group" && item.Terms != null)
            {
                var groupResults = new List<bool>();
                var groupMatchedTerms = new List<string>();

                foreach (var term in item.Terms)
                {
                    string escaped = Regex.Escape(term);
                    string regexPattern = $"(?<![a-zA-Z]){escaped}(?![a-zA-Z])";
                    var match = Regex.Match(textLow, regexPattern);
                    groupResults.Add(match.Success);
                    if (match.Success)
                        groupMatchedTerms.Add(term);
                }

                if (item.Logic == "AND")
                    itemMatched = groupResults.Count > 0 && groupResults.All(r => r);
                else
                    itemMatched = groupResults.Any(r => r);

                if (itemMatched)
                    itemMatchedTerm = "(" + string.Join($" {item.Logic ?? "OR"} ", groupMatchedTerms) + ")";
            }
            else if (item.Type == "topo-template" && topoMap != null && item.Template != null)
            {
                foreach (var topoEntry in topoMap)
                {
                    string testPhrase = item.Template.Replace("{topo}", topoEntry.SearchPhrase);
                    string escaped = Regex.Escape(testPhrase);
                    string regexPattern = $"(?<![a-zA-Z]){escaped}(?![a-zA-Z])";
                    var match = Regex.Match(textLow, regexPattern);
                    if (match.Success)
                    {
                        itemMatched = true;
                        itemMatchedTerm = testPhrase;
                        itemTopoCode = topoEntry.Code;
                        break;
                    }
                }
            }

            expressionResults.Add((itemMatched, itemMatchedTerm, itemTopoCode));
        }

        // Apply top-level Logic
        bool overallMatched = false;
        string matchedTerm = "";
        string? topoCode = null;

        if (rule.Logic == "AND")
        {
            overallMatched = expressionResults.Count > 0 && expressionResults.All(r => r.Matched);
        }
        else
        {
            // OR logic (default)
            var firstMatch = expressionResults.FirstOrDefault(r => r.Matched);
            if (firstMatch.Matched)
            {
                overallMatched = true;
                matchedTerm = firstMatch.Term;
                topoCode = firstMatch.TopoCode;
            }
        }

        if (overallMatched && string.IsNullOrEmpty(matchedTerm))
        {
            matchedTerm = string.Join(", ", expressionResults.Where(r => r.Matched).Select(r => r.Term));
        }

        // Pick up topoCode from any matched expression if not yet set
        if (overallMatched && topoCode == null)
        {
            topoCode = expressionResults.FirstOrDefault(r => r.Matched && r.TopoCode != null).TopoCode;
        }

        return new SiteCodingTestResult
        {
            Matched = overallMatched,
            MatchedTerm = matchedTerm,
            TopoCode = topoCode
        };
    }

    public SiteAssignment GetBestCode(List<TopographyEntry> map, string textLow)
    {
        string bestCode = "";
        int bestPos = 0;

        foreach (var row in map)
        {
            string escaped = Regex.Escape(row.SearchPhrase);
            string pattern = $"(?<![a-zA-Z]){escaped}(?![a-zA-Z])";
            var match = Regex.Match(textLow, pattern);
            if (match.Success)
            {
                int p = match.Index + 1;
                if (bestPos == 0 || p < bestPos)
                {
                    bestPos = p;
                    bestCode = row.Code;
                }
            }
        }

        return new SiteAssignment { PrimarySite = string.IsNullOrEmpty(bestCode) ? null : bestCode };
    }

    public string? GetLaterality(string textLow)
    {
        bool hasLeft = Regex.IsMatch(textLow, @"\bleft\b", RegexOptions.IgnoreCase);
        bool hasRight = Regex.IsMatch(textLow, @"\bright\b", RegexOptions.IgnoreCase);

        if (!hasLeft && !hasRight) return null;
        if (hasLeft && hasRight) return "9";
        if (hasLeft) return "2";
        return "1";
    }

    public List<SiteLateralityResult> GetMissingFields(XmlNodeList tumors, XmlNamespaceManager nsMgr)
    {
        // Load cached maps
        EnsureMapsLoaded();

        var report = new List<SiteLateralityResult>();

        for (int i = 0; i < tumors.Count; i++)
        {
            var tumor = tumors[i]!;
            var patient = tumor.SelectSingleNode("ancestor::n:Patient[1]", nsMgr);

            string nameLast = patient?.SelectSingleNode("./n:Item[@naaccrId='nameLast']", nsMgr)?.InnerText ?? "";
            string nameFirst = patient?.SelectSingleNode("./n:Item[@naaccrId='nameFirst']", nsMgr)?.InnerText ?? "";
            string patientName = $"{nameLast}, {nameFirst}".Trim(',', ' ');

            string currentSite = (tumor.SelectSingleNode("./n:Item[@naaccrId='primarySite']", nsMgr)?.InnerText ?? "").Trim();
            string currentLat = (tumor.SelectSingleNode("./n:Item[@naaccrId='laterality']", nsMgr)?.InnerText ?? "").Trim();

            bool hasSite = !string.IsNullOrWhiteSpace(currentSite);
            bool hasLat = !string.IsNullOrWhiteSpace(currentLat);

            if (hasSite && hasLat)
            {
                report.Add(new SiteLateralityResult
                {
                    TumorIndex = i + 1,
                    PatientName = patientName,
                    CurrentSite = currentSite,
                    ProposedSite = "",
                    CurrentLaterality = currentLat,
                    ProposedLaterality = "",
                    SourceText = "",
                    Category = "HasSite_NoUpdate"
                });
                continue;
            }

            string textPath = tumor.SelectSingleNode("./n:Item[@naaccrId='textDxProcPath']", nsMgr)?.InnerText ?? "";
            string textPe = tumor.SelectSingleNode("./n:Item[@naaccrId='textDxProcPe']", nsMgr)?.InnerText ?? "";
            string textLab = tumor.SelectSingleNode("./n:Item[@naaccrId='textDxProcLabTests']", nsMgr)?.InnerText ?? "";

            string textCombined = (textPath + " " + textPe).Trim();
            if (string.IsNullOrEmpty(textCombined))
                textCombined = textLab.Trim();

            if (string.IsNullOrEmpty(textCombined))
            {
                if (!hasSite)
                {
                    report.Add(new SiteLateralityResult
                    {
                        TumorIndex = i + 1,
                        PatientName = patientName,
                        CurrentSite = currentSite,
                        ProposedSite = "",
                        CurrentLaterality = currentLat,
                        ProposedLaterality = "",
                        SourceText = "(no text available)",
                        Category = "NoSite_NoText"
                    });
                }
                continue;
            }

            string low = textCombined.ToLower();
            string proposedSite = "";
            string proposedLat = "";
            SiteCodingRule? matchedPattern = null;

            if (!hasSite && _siteCodingRulesCache != null)
            {
                bool patternMatched = false;
                foreach (var pattern in _siteCodingRulesCache)
                {
                    var testResult = TestSiteCodingRule(pattern, low, _topoMapCache);
                    if (testResult.Matched)
                    {
                        if (testResult.TopoCode != null)
                            proposedSite = testResult.TopoCode;
                        else if (pattern.Code != "{topo}")
                            proposedSite = pattern.Code;
                        else
                            continue;

                        patternMatched = true;
                        matchedPattern = pattern;
                        break;
                    }
                }

                if (!patternMatched && _melTopoMapCache != null && _topoMapCache != null)
                {
                    bool hasMel = low.Contains("melanoma");
                    if (hasMel)
                    {
                        var bestCode = GetBestCode(_melTopoMapCache, low);
                        proposedSite = bestCode.PrimarySite ?? "C449";
                    }
                    else
                    {
                        var bestCode = GetBestCode(_topoMapCache, low);
                        proposedSite = bestCode.PrimarySite ?? "";
                    }
                }
            }

            // Determine site for laterality check
            string siteToCheck = !string.IsNullOrEmpty(proposedSite) ? proposedSite : currentSite;

            if (!hasLat && !string.IsNullOrEmpty(siteToCheck) && _lateralityCodesCache != null)
            {
                if (matchedPattern?.ForceLaterality != null)
                {
                    proposedLat = matchedPattern.ForceLaterality;
                }
                else if (_lateralityCodesCache.ContainsKey(siteToCheck))
                {
                    string? detectedLat = GetLaterality(low);
                    proposedLat = detectedLat ?? "9";
                }
                else
                {
                    proposedLat = "0";
                }
            }

            string sourceText = "";
            if (!string.IsNullOrEmpty(proposedSite) || !string.IsNullOrEmpty(proposedLat))
            {
                sourceText = textCombined.Length > 200 ? textCombined[..200] + "..." : textCombined;
            }

            string category;
            if (!string.IsNullOrEmpty(proposedSite) || !string.IsNullOrEmpty(proposedLat))
                category = "WillUpdate";
            else if (hasSite)
                category = "HasSite_NoUpdate";
            else
                category = "NoSite_NoMatch";

            string displaySourceText = sourceText;
            if (string.IsNullOrEmpty(displaySourceText) && !string.IsNullOrEmpty(textCombined))
            {
                int maxLen = Math.Min(200, textCombined.Length);
                displaySourceText = textCombined[..maxLen];
                if (textCombined.Length > 200)
                    displaySourceText += "...";
            }

            report.Add(new SiteLateralityResult
            {
                TumorIndex = i + 1,
                PatientName = patientName,
                CurrentSite = currentSite,
                ProposedSite = proposedSite,
                CurrentLaterality = currentLat,
                ProposedLaterality = proposedLat,
                SourceText = displaySourceText ?? "",
                Category = category
            });
        }

        return report;
    }

    public void WriteAssignedXml(XmlDocument xmlDoc, XmlNodeList tumors, Dictionary<int, SiteAssignment> assignments,
        XmlNamespaceManager nsMgr, string outputPath)
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

            foreach (XmlNode child in patientNode.ChildNodes)
            {
                if (child.LocalName == "Item")
                {
                    var imported = newDoc.ImportNode(child, true);
                    newPatient.AppendChild(imported);
                }
            }

            var tumorsInPatient = patientNode.SelectNodes("./n:Tumor", nsMgr)!;
            foreach (XmlNode tumor in tumorsInPatient)
            {
                int tumorIndex = FindTumorIndex(tumors, tumor);
                var newTumor = newDoc.ImportNode(tumor, true);

                if (tumorIndex >= 0 && assignments.TryGetValue(tumorIndex, out var assignment))
                {
                    if (assignment.PrimarySite != null)
                        SetOrCreateItem(newTumor, "primarySite", assignment.PrimarySite, root.NamespaceURI, nsMgr, newDoc);

                    if (assignment.Laterality != null)
                        SetOrCreateItem(newTumor, "laterality", assignment.Laterality, root.NamespaceURI, nsMgr, newDoc);
                }

                newPatient.AppendChild(newTumor);
            }

            newRoot.AppendChild(newPatient);
        }

        WriteXmlDocument(newDoc, outputPath);
    }

    // --- Private helpers ---

    private void EnsureMapsLoaded()
    {
        // Maps are loaded on demand via the public Read* methods and cached here.
        // In production use, the caller loads them and passes data in.
        // This is a placeholder for the caching pattern.
    }

    /// <summary>
    /// Load all maps from the dictionaries directory. Call this before GetMissingFields if maps are not loaded.
    /// </summary>
    public void LoadMaps(string dictionaryDir)
    {
        string topoPath = Path.Combine(dictionaryDir, "Topography.jsonl");
        string melTopoPath = Path.Combine(dictionaryDir, "TopographyMelanoma.jsonl");
        string latPath = Path.Combine(dictionaryDir, "Laterality.json");
        string rulesPath = Path.Combine(dictionaryDir, "SiteCodingRules.jsonl");

        if (File.Exists(topoPath))
            _topoMapCache = ReadTopographyJson(topoPath)
                .Where(t => !string.IsNullOrEmpty(t.Code) && !string.IsNullOrEmpty(t.SearchPhrase) && !t.Code.StartsWith("C77"))
                .ToList();

        if (File.Exists(melTopoPath))
            _melTopoMapCache = ReadTopographyJson(melTopoPath);

        if (File.Exists(latPath))
            _lateralityCodesCache = ReadLateralityJson(latPath);

        if (File.Exists(rulesPath))
            _siteCodingRulesCache = ReadSiteCodingRules(rulesPath);
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
