using Parrat.Core.Models;

namespace Parrat.Core.Interfaces;

public interface IFilterService
{
    /// <summary>
    /// The 0-based indices of the records matching <paramref name="filter"/>, in
    /// load order. An empty filter matches every record.
    /// </summary>
    int[] GetMatchingIndices(FilterDefinition? filter, IFilterFieldSource source);

    /// <summary>
    /// The distinct field ids a filter refers to — what a field source needs to
    /// be built for.
    /// </summary>
    IReadOnlyList<string> GetReferencedFields(FilterDefinition? filter);
}
