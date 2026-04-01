namespace Parrat.Core.Interfaces;

public interface IConvertTxtService
{
    string ConvertPathologyTextToHl7(string inputPath, string? outputPath, string facilityName, bool previewOnly = false);
    List<Dictionary<string, object>> GetPreviewCases(string inputPath, string facilityName);
}
