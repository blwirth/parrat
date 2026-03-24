using Parat.Core.Models;

namespace Parat.Core.Interfaces;

public interface IConfigService
{
    // Export configs
    string GetExportConfigPath();
    List<ExportField> GetDefaultFieldList();
    ExportConfig NewExportConfig(string? name = null, List<ExportField>? fields = null, int version = 25);
    (bool Success, string Path, string Message) SaveExportConfig(ExportConfig config, string? fileName = null, string? path = null);
    ExportConfig GetExportConfig(string filePath);
    List<(string Name, string Path)> GetAvailableExportConfigs();
    List<string> ConvertFieldListToXmlIds(List<ExportField> fields);
    Dictionary<string, string> GetCustomFieldsFromConfig(List<ExportField> fields);
    void InitializeDefaultExportConfig();

    // OBX skip config
    ObxSkipConfig GetObxSkipConfig();
    void SaveObxSkipConfig(ObxSkipConfig config);
}
