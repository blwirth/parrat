namespace Parat.Core.Models;

public class SiteLateralityResult
{
    public int TumorIndex { get; set; }
    public string PatientName { get; set; } = string.Empty;
    public string CurrentSite { get; set; } = string.Empty;
    public string ProposedSite { get; set; } = string.Empty;
    public string CurrentLaterality { get; set; } = string.Empty;
    public string ProposedLaterality { get; set; } = string.Empty;
    public string SourceText { get; set; } = string.Empty;
    public string Category { get; set; } = string.Empty; // HasSite_NoUpdate, NoSite_NoText, NoSite_NoMatch, WillUpdate
}

public class SiteAssignment
{
    public string? PrimarySite { get; set; }
    public string? Laterality { get; set; }
}

public class SiteCodingTestResult
{
    public bool Matched { get; set; }
    public string? MatchedTerm { get; set; }
    public string? TopoCode { get; set; }
}
