using System.Xml;
using Parrat.Core.Models;

namespace Parrat.Core.Helpers;

/// <summary>
/// Rescues field values that were blanket-overwritten in a file — every record
/// given the same reportingFacility, say — by matching each record back to the
/// untouched original file on a key and planning a per-record restore.
///
/// Nothing is ever written to the loaded document: the plan is computed first
/// so every record's fate is reviewable, and applying it builds a repaired
/// copy that the caller saves as a new file.
///
/// Restored values are written at the Tumor level, so restore fields must be
/// tumor-level items (a patient-level write would bleed across every tumor of
/// the patient); the caller enforces that when the field is chosen.
/// </summary>
public static class FieldRestoreHelper
{
    /// <summary>
    /// Plans the restore: for every tumor in the damaged file, finds its match
    /// in the original by <paramref name="keyFieldId"/> and decides per field
    /// whether the original value can and should be brought back. Key values
    /// are trimmed; matching ignores case when <paramref name="caseInsensitiveKeys"/>.
    /// </summary>
    public static FieldRestorePlan BuildPlan(
        XmlNodeList damagedTumors, XmlNamespaceManager damagedNsMgr,
        XmlNodeList originalTumors, XmlNamespaceManager originalNsMgr,
        string keyFieldId, IReadOnlyList<string> restoreFieldIds,
        bool caseInsensitiveKeys = true)
    {
        var comparer = caseInsensitiveKeys ? StringComparer.OrdinalIgnoreCase : StringComparer.Ordinal;
        var index = BuildOriginalIndex(originalTumors, originalNsMgr, keyFieldId, restoreFieldIds, comparer);

        var rows = new List<FieldRestoreRow>();

        for (int i = 0; i < damagedTumors.Count; i++)
        {
            var tumor = damagedTumors[i];
            if (tumor == null) continue;

            var key = TumorFieldReader.ReadValueAnyLevel(tumor, keyFieldId, damagedNsMgr).Trim();

            foreach (var fieldId in restoreFieldIds)
            {
                var current = TumorFieldReader.ReadValueAnyLevel(tumor, fieldId, damagedNsMgr).Trim();

                rows.Add(new FieldRestoreRow
                {
                    TumorIndex = i,
                    KeyValue = key,
                    FieldId = fieldId,
                    CurrentValue = current,
                    OriginalValue = index.TryGetValue(key, out var fields)
                        && fields.TryGetValue(fieldId, out var original) ? original.Value : "",
                    Status = Classify(key, current, index, fieldId)
                });
            }
        }

        return new FieldRestorePlan { Rows = rows };
    }

    /// <summary>
    /// Builds the repaired document: a deep copy of the damaged document with
    /// every <see cref="RestoreStatus.Restore"/> row's value written onto the
    /// copy's tumor. The source document is never touched.
    /// </summary>
    public static XmlDocument BuildRepairedDocument(
        XmlDocument damagedDoc, XmlNamespaceManager nsMgr, FieldRestorePlan plan)
    {
        var repaired = (XmlDocument)damagedDoc.CloneNode(true);
        repaired.XmlResolver = null;

        var nsUri = repaired.DocumentElement?.NamespaceURI ?? "";
        var repairedNsMgr = new XmlNamespaceManager(repaired.NameTable);
        repairedNsMgr.AddNamespace("n", nsUri);

        // The clone preserves node order, so tumor N in the copy is tumor N in
        // the source — the plan's indices carry over directly.
        var tumors = repaired.SelectNodes("//n:Tumor", repairedNsMgr)!;

        foreach (var row in plan.Rows)
        {
            if (row.Status != RestoreStatus.Restore) continue;
            if (row.TumorIndex < 0 || row.TumorIndex >= tumors.Count) continue;

            SetTumorItem(tumors[row.TumorIndex]!, row.FieldId, row.OriginalValue, repaired, nsUri);
        }

        return repaired;
    }

    // ── Private helpers ──────────────────────────────────────────────────

    /// <summary>
    /// One original value per key and field. When several original records
    /// share a key, an empty value never overrides a real one, and two real
    /// values that disagree mark the pairing conflicted.
    /// </summary>
    private static Dictionary<string, Dictionary<string, (string Value, bool Conflict)>> BuildOriginalIndex(
        XmlNodeList originalTumors, XmlNamespaceManager nsMgr,
        string keyFieldId, IReadOnlyList<string> restoreFieldIds, StringComparer comparer)
    {
        var index = new Dictionary<string, Dictionary<string, (string, bool)>>(comparer);

        for (int i = 0; i < originalTumors.Count; i++)
        {
            var tumor = originalTumors[i];
            if (tumor == null) continue;

            var key = TumorFieldReader.ReadValueAnyLevel(tumor, keyFieldId, nsMgr).Trim();
            if (key.Length == 0) continue;

            if (!index.TryGetValue(key, out var fields))
            {
                fields = new Dictionary<string, (string, bool)>(StringComparer.Ordinal);
                index[key] = fields;
            }

            foreach (var fieldId in restoreFieldIds)
            {
                var value = TumorFieldReader.ReadValueAnyLevel(tumor, fieldId, nsMgr).Trim();

                if (!fields.TryGetValue(fieldId, out var existing))
                    fields[fieldId] = (value, false);
                else if (existing.Item1.Length == 0)
                    fields[fieldId] = (value, existing.Item2);
                else if (value.Length > 0 && !string.Equals(existing.Item1, value, StringComparison.Ordinal))
                    fields[fieldId] = (existing.Item1, true);
            }
        }

        return index;
    }

    private static RestoreStatus Classify(
        string key, string current,
        Dictionary<string, Dictionary<string, (string Value, bool Conflict)>> index, string fieldId)
    {
        if (key.Length == 0)
            return RestoreStatus.MissingKey;

        if (!index.TryGetValue(key, out var fields) || !fields.TryGetValue(fieldId, out var original))
            return RestoreStatus.NoMatch;

        if (original.Conflict)
            return RestoreStatus.Ambiguous;

        if (original.Value.Length == 0)
            return RestoreStatus.OriginalEmpty;

        return string.Equals(current, original.Value, StringComparison.Ordinal)
            ? RestoreStatus.AlreadyCorrect
            : RestoreStatus.Restore;
    }

    /// <summary>
    /// Sets a tumor-level Item, creating it when the damaged record lacks one —
    /// the same shape FacilityAssignmentService writes.
    /// </summary>
    private static void SetTumorItem(XmlNode tumor, string fieldId, string value, XmlDocument doc, string nsUri)
    {
        foreach (XmlNode child in tumor.ChildNodes)
        {
            if (child.NodeType == XmlNodeType.Element
                && child.LocalName == "Item"
                && child.Attributes?["naaccrId"]?.Value == fieldId)
            {
                child.InnerText = value;
                return;
            }
        }

        var item = doc.CreateElement("Item", nsUri);
        item.SetAttribute("naaccrId", fieldId);
        item.InnerText = value;
        tumor.AppendChild(item);
    }
}
