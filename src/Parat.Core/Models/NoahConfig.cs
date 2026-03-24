namespace Parat.Core.Models;

public class NoahConfig
{
    public string ExePath { get; set; } = string.Empty;
    public string ModelId { get; set; } = string.Empty;
    public string Output { get; set; } = "hl7";
    public bool SeparateImpossiblesAndMets { get; set; }
    public string WorkingRoot { get; set; } = Path.GetTempPath();
    public string ApiServerUrl { get; set; } = "http://localhost:4000";
}

public class NoahModel
{
    public string Id { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
}

public class CachedNoahModels
{
    public string? LastUpdated { get; set; }
    public List<NoahModel> Models { get; set; } = new();
}

public class NoahWorkingFolders
{
    public string Base { get; set; } = string.Empty;
    public string Source { get; set; } = string.Empty;
    public string Reportable { get; set; } = string.Empty;
    public string NonReportable { get; set; } = string.Empty;
    public string Reports { get; set; } = string.Empty;
    public string OutputFormat { get; set; } = string.Empty;
}

public class NoahResult
{
    public bool Success { get; set; }
    public string Classification { get; set; } = string.Empty;
    public bool Reportable { get; set; }
    public bool ImpossibleCombination { get; set; }
    public bool MetastaticReport { get; set; }
    public string MessageId { get; set; } = string.Empty;
    public object? ApiResponse { get; set; }
    public int ExitCode { get; set; }
    public string WorkingFolder { get; set; } = string.Empty;
    public int ReportableCount { get; set; }
    public int NonReportableCount { get; set; }
}
