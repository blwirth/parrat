using System.Xml;

namespace Parrat.Core.Helpers;

/// <summary>
/// Reads a fixed set of NAACCR Item values from Patient/Tumor elements in a
/// single pass over each element's children.
///
/// The obvious approach — one <c>SelectSingleNode("./n:Item[@naaccrId='x']")</c>
/// per value — compiles and evaluates an XPath expression for every cell, which
/// dominates load time once a file holds thousands of tumors. Reading every
/// wanted item from one element in one pass is an order of magnitude faster and
/// produces identical values.
///
/// Construct once with the item ids you need, then reuse across all records.
/// </summary>
public sealed class NaaccrItemReader
{
    private readonly HashSet<string> _wanted;

    public NaaccrItemReader(IEnumerable<string> naaccrIds)
    {
        _wanted = new HashSet<string>(naaccrIds, StringComparer.Ordinal);
    }

    /// <summary>The item ids this reader collects.</summary>
    public IReadOnlyCollection<string> WantedIds => _wanted;

    /// <summary>
    /// Adds this element's wanted items to <paramref name="into"/>. Values
    /// already present are left alone, so calling for the tumor and then its
    /// patient yields the tumor's value where both carry the item — matching
    /// how the grid and search index resolve a field.
    ///
    /// Empty values are not recorded, so an item present but blank on the tumor
    /// still falls through to the patient. Where an element carries the same
    /// naaccrId more than once — which NAACCR XML does not permit — the first
    /// non-empty occurrence wins.
    /// </summary>
    public void ReadInto(XmlNode? node, IDictionary<string, string> into)
    {
        // No short-circuit on into.Count: the dictionary may be shared with
        // other readers covering different item ids, so a full dictionary does
        // not mean this reader's ids are all resolved.
        if (node == null)
            return;

        for (var child = node.FirstChild; child != null; child = child.NextSibling)
        {
            if (child.NodeType != XmlNodeType.Element) continue;
            if (!string.Equals(child.LocalName, "Item", StringComparison.Ordinal)) continue;

            var id = ((XmlElement)child).GetAttribute("naaccrId");
            if (id.Length == 0 || !_wanted.Contains(id) || into.ContainsKey(id)) continue;

            var text = child.InnerText;
            if (text.Length > 0)
                into[id] = text;
        }
    }

    /// <summary>
    /// Reads the wanted items from the given elements, earlier elements taking
    /// precedence. Missing items are absent from the result rather than empty.
    /// </summary>
    public Dictionary<string, string> Read(params XmlNode?[] nodesInPriorityOrder)
    {
        var values = new Dictionary<string, string>(_wanted.Count, StringComparer.Ordinal);

        foreach (var node in nodesInPriorityOrder)
            ReadInto(node, values);

        return values;
    }

    /// <summary>
    /// Appends the text of every Item directly under <paramref name="node"/> to
    /// <paramref name="into"/>, regardless of id. Used to build the search
    /// index, which indexes all values rather than a chosen set.
    /// </summary>
    public static void CollectAllItemText(XmlNode? node, List<string> into)
    {
        if (node == null) return;

        for (var child = node.FirstChild; child != null; child = child.NextSibling)
        {
            if (child.NodeType != XmlNodeType.Element) continue;
            if (!string.Equals(child.LocalName, "Item", StringComparison.Ordinal)) continue;

            var text = child.InnerText;
            if (text.Length > 0)
                into.Add(text);
        }
    }
}
