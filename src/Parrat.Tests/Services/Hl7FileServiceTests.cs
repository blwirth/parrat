using System.Text;
using Parrat.Core.Models;
using Parrat.Core.Services;
using Xunit;

namespace Parrat.Tests.Services;

public class Hl7FileServiceTests : IDisposable
{
    private readonly string _tempDir;

    public Hl7FileServiceTests()
    {
        _tempDir = Path.Combine(Path.GetTempPath(), $"parrat_hl7file_test_{Guid.NewGuid():N}");
        Directory.CreateDirectory(_tempDir);
    }

    public void Dispose()
    {
        try { Directory.Delete(_tempDir, true); } catch { }
    }

    [Fact]
    public void LoadHl7File_ParsesMessagesFromFile()
    {
        var content = "MSH|^~\\&|App|Fac|||20240101||ORU^R01|M1|P|2.5\rPID|1||123||Smith^John||19800101|M\rOBR|1|ORD1||PROC1\rOBX|1|TX|CODE^Desc||Some text\r\rMSH|^~\\&|App|Fac|||20240102||ORU^R01|M2|P|2.5\rPID|1||456||Jones^Jane||19900215|F\rOBR|1|ORD2||PROC2\r";
        var filePath = Path.Combine(_tempDir, "test.hl7");
        File.WriteAllText(filePath, content, Encoding.ASCII);

        var parser = new Hl7Parser();
        var service = new Hl7FileService(parser);
        var messages = service.LoadHl7File(filePath);

        Assert.Equal(2, messages.Count);
        Assert.Equal("Smith", messages[0].PatientLastName);
        Assert.Equal("Jones", messages[1].PatientLastName);
    }

    [Fact]
    public void LoadHl7File_ReturnsEmptyForEmptyFile()
    {
        var filePath = Path.Combine(_tempDir, "empty.hl7");
        File.WriteAllText(filePath, "", Encoding.ASCII);

        var parser = new Hl7Parser();
        var service = new Hl7FileService(parser);
        var messages = service.LoadHl7File(filePath);

        Assert.Empty(messages);
    }

    [Fact]
    public void SaveHl7File_WritesMessagesToFile()
    {
        var messages = new List<Hl7Message>
        {
            new() { RawContent = "MSH|^~\\&|A\rPID|1||001" },
            new() { RawContent = "MSH|^~\\&|B\rPID|1||002" },
        };

        var filePath = Path.Combine(_tempDir, "output.hl7");
        var parser = new Hl7Parser();
        var service = new Hl7FileService(parser);
        service.SaveHl7File(filePath, messages);

        var content = File.ReadAllText(filePath, Encoding.ASCII);
        Assert.Contains("MSH|^~\\&|A", content);
        Assert.Contains("MSH|^~\\&|B", content);
    }

    [Fact]
    public void LoadAndSave_Roundtrip_PreservesContent()
    {
        var original = "MSH|^~\\&|App|Fac|||20240101||ORU^R01|M1|P|2.5\rPID|1||123||Smith^John||19800101|M\rOBR|1|ORD1||PROC1\r";
        var filePath = Path.Combine(_tempDir, "roundtrip.hl7");
        File.WriteAllText(filePath, original, Encoding.ASCII);

        var parser = new Hl7Parser();
        var service = new Hl7FileService(parser);

        var messages = service.LoadHl7File(filePath);
        var savePath = Path.Combine(_tempDir, "roundtrip_out.hl7");
        service.SaveHl7File(savePath, messages);

        var reloaded = service.LoadHl7File(savePath);
        Assert.Single(reloaded);
        Assert.Equal("Smith", reloaded[0].PatientLastName);
    }
}
