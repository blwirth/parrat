using System.Diagnostics;
using Parrat.Core.Models;

namespace Parrat.Core.Interfaces;

public interface INoahService
{
    string GetNoahConfigPath();
    string GetNoahModelsPath();
    CachedNoahModels GetCachedModels();
    void SaveCachedModels(List<NoahModel> models);
    NoahConfig GetConfig();
    void SaveConfig(NoahConfig config);
    Process StartServer(NoahConfig config);
    void StopServer(Process? process);
    List<NoahModel> GetModels(NoahConfig config, ref Process? serverProcess);
    NoahWorkingFolders CreateWorkingFolders(string outputFormat, string workingRoot);
    NoahResult InvokeReportabilityApi(string hl7Message, NoahConfig config, string modelId,
        string? messageId = null, Process? serverProcess = null);
    string CreateMinimalHl7Message(string customText, string? patientId = null, string? accessionNumber = null);
}
