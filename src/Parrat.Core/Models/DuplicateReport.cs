namespace Parrat.Core.Models;

public class DuplicateReport
{
    public string PatientKey { get; set; } = string.Empty;
    public string AllIndices { get; set; } = string.Empty;
    public int KeptIndex { get; set; }
    public string RemovedIndices { get; set; } = string.Empty;
    public string Reason { get; set; } = string.Empty;
    public string DateReceived { get; set; } = string.Empty;
    public string Physician3 { get; set; } = string.Empty;
}

public class DeduplicationResult
{
    public HashSet<int> IndicesToKeep { get; set; } = new();
    public List<DuplicateReport> Report { get; set; } = new();
}
