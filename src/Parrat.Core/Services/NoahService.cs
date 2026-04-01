using System.Diagnostics;
using System.Net.Http;
using System.Text;
using System.Text.Json;
using Parrat.Core.Helpers;
using Parrat.Core.Interfaces;
using Parrat.Core.Models;

namespace Parrat.Core.Services;

public class NoahService : INoahService
{
    private static readonly HttpClient HttpClient = new() { Timeout = TimeSpan.FromSeconds(30) };

    public string GetNoahConfigPath()
    {
        return PathHelper.GetConfigPath("noah-config.json");
    }

    public string GetNoahModelsPath()
    {
        return PathHelper.GetConfigPath("models.json");
    }

    public CachedNoahModels GetCachedModels()
    {
        string modelsPath = GetNoahModelsPath();

        if (!File.Exists(modelsPath))
            return new CachedNoahModels();

        try
        {
            string raw = File.ReadAllText(modelsPath);
            if (string.IsNullOrWhiteSpace(raw))
                return new CachedNoahModels();

            var cache = JsonSerializer.Deserialize<CachedNoahModels>(raw, new JsonSerializerOptions
            {
                PropertyNameCaseInsensitive = true
            });

            return cache ?? new CachedNoahModels();
        }
        catch
        {
            return new CachedNoahModels();
        }
    }

    public void SaveCachedModels(List<NoahModel> models)
    {
        string modelsPath = GetNoahModelsPath();
        var cache = new CachedNoahModels
        {
            LastUpdated = DateTime.Now.ToString("o"),
            Models = models
        };

        string json = JsonSerializer.Serialize(cache, new JsonSerializerOptions
        {
            WriteIndented = true,
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase
        });

        PathHelper.EnsureDirectoryExists(Path.GetDirectoryName(modelsPath)!);
        File.WriteAllText(modelsPath, json, Encoding.UTF8);
    }

    public NoahConfig GetConfig()
    {
        string configPath = GetNoahConfigPath();
        if (File.Exists(configPath))
        {
            try
            {
                string raw = File.ReadAllText(configPath);
                if (!string.IsNullOrWhiteSpace(raw))
                {
                    var config = JsonSerializer.Deserialize<NoahConfig>(raw, new JsonSerializerOptions
                    {
                        PropertyNameCaseInsensitive = true
                    });
                    if (config != null) return config;
                }
            }
            catch
            {
                // Fall back to defaults
            }
        }

        return new NoahConfig();
    }

    public void SaveConfig(NoahConfig config)
    {
        string configPath = GetNoahConfigPath();
        string json = JsonSerializer.Serialize(config, new JsonSerializerOptions
        {
            WriteIndented = true,
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase
        });

        PathHelper.EnsureDirectoryExists(Path.GetDirectoryName(configPath)!);
        File.WriteAllText(configPath, json, Encoding.UTF8);
    }

    public Process StartServer(NoahConfig config)
    {
        string exePath = config.ExePath;
        if (string.IsNullOrWhiteSpace(exePath) || !File.Exists(exePath))
            throw new InvalidOperationException("NOAH exe path not configured or not found.");

        string exeDir = Path.GetDirectoryName(exePath) ?? ".";

        var proc = new Process
        {
            StartInfo = new ProcessStartInfo
            {
                FileName = exePath,
                WorkingDirectory = exeDir,
                WindowStyle = ProcessWindowStyle.Minimized,
                UseShellExecute = true
            }
        };

        proc.Start();
        return proc;
    }

    public void StopServer(Process? process)
    {
        if (process == null) return;

        try
        {
            if (!process.HasExited)
            {
                process.Kill();
                process.WaitForExit(5000);
            }
        }
        catch
        {
            // Ignore errors when stopping
        }
    }

    public List<NoahModel> GetModels(NoahConfig config, ref Process? serverProcess)
    {
        string apiServerUrl = config.ApiServerUrl?.TrimEnd('/') ?? "http://localhost:4000";

        // Try to get models from API
        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Get, $"{apiServerUrl}/Models");
            request.Headers.Add("accept", "*/*");
            request.Headers.Add("api-version", "2");

            var response = HttpClient.Send(request);
            response.EnsureSuccessStatusCode();

            using var stream = response.Content.ReadAsStream();
            var models = JsonSerializer.Deserialize<List<NoahModel>>(stream, new JsonSerializerOptions
            {
                PropertyNameCaseInsensitive = true
            });

            return models ?? new List<NoahModel>();
        }
        catch
        {
            // Server not running, try to start it
            try
            {
                serverProcess = StartServer(config);

                // Wait for server to be ready (polling with timeout)
                for (int attempt = 0; attempt < 60; attempt++)
                {
                    Thread.Sleep(500);
                    try
                    {
                        using var request = new HttpRequestMessage(HttpMethod.Get, $"{apiServerUrl}/Models");
                        request.Headers.Add("accept", "*/*");
                        request.Headers.Add("api-version", "2");

                        var response = HttpClient.Send(request);
                        response.EnsureSuccessStatusCode();

                        using var stream = response.Content.ReadAsStream();
                        var models = JsonSerializer.Deserialize<List<NoahModel>>(stream, new JsonSerializerOptions
                        {
                            PropertyNameCaseInsensitive = true
                        });

                        return models ?? new List<NoahModel>();
                    }
                    catch
                    {
                        // Server not ready yet
                    }
                }
            }
            catch
            {
                // Failed to start server
            }
        }

        return new List<NoahModel>();
    }

    public NoahWorkingFolders CreateWorkingFolders(string outputFormat, string workingRoot)
    {
        string stamp = DateTime.Now.ToString("yyyyMMdd_HHmmss");
        string runId = Guid.NewGuid().ToString();
        string basePath = Path.Combine(workingRoot, $"noah_reportability_{stamp}_{runId}");

        var folders = new NoahWorkingFolders
        {
            Base = basePath,
            Source = Path.Combine(basePath, "source"),
            Reportable = Path.Combine(basePath, "reportable"),
            NonReportable = Path.Combine(basePath, "nonreportable"),
            Reports = Path.Combine(basePath, "reports"),
            OutputFormat = outputFormat
        };

        Directory.CreateDirectory(folders.Base);
        Directory.CreateDirectory(folders.Source);
        Directory.CreateDirectory(folders.Reportable);
        Directory.CreateDirectory(folders.NonReportable);
        Directory.CreateDirectory(folders.Reports);

        return folders;
    }

    public NoahResult InvokeReportabilityApi(string hl7Message, NoahConfig config, string modelId,
        string? messageId = null, Process? serverProcess = null)
    {
        string apiServerUrl = (config.ApiServerUrl ?? "http://localhost:4000").TrimEnd('/');
        messageId ??= Guid.NewGuid().ToString();

        if (!Guid.TryParse(modelId, out var guid))
        {
            return new NoahResult
            {
                Success = false,
                Classification = $"Invalid ModelId format: {modelId} (must be a GUID)"
            };
        }

        modelId = guid.ToString();

        // Encode HL7 message as Base64
        byte[] bytes = Encoding.UTF8.GetBytes(hl7Message);
        string hl7MessageEncoded = Convert.ToBase64String(bytes);

        var requestObj = new
        {
            value = new[]
            {
                new
                {
                    messageId,
                    hl7Message = hl7MessageEncoded,
                    messageEncodingFormat = "Base64",
                    modelId
                }
            }
        };

        string requestBody = JsonSerializer.Serialize(requestObj);
        string endpoint = $"{apiServerUrl}/api/NER";

        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Post, endpoint);
            request.Content = new StringContent(requestBody, Encoding.UTF8, "application/json");
            request.Headers.Add("Accept", "application/json");
            request.Headers.Add("api-version", "2");

            var response = HttpClient.Send(request);
            response.EnsureSuccessStatusCode();

            using var stream = response.Content.ReadAsStream();
            using var doc = JsonDocument.Parse(stream);

            var root = doc.RootElement;

            if (root.ValueKind == JsonValueKind.Array && root.GetArrayLength() > 0)
            {
                var result = root[0];

                string reportableStr = result.TryGetProperty("reportable", out var rp) ? rp.GetString() ?? "" : "";
                bool isReportable = reportableStr == "true";

                string classification = isReportable ? "reportable"
                    : reportableStr == "false" ? "nonreportable"
                    : "unknown";

                return new NoahResult
                {
                    Success = true,
                    Classification = classification,
                    Reportable = isReportable,
                    ImpossibleCombination = result.TryGetProperty("impossibleCombination", out var ic) && ic.GetString() == "true",
                    MetastaticReport = result.TryGetProperty("metastaticReport", out var mr) && mr.GetBoolean(),
                    MessageId = result.TryGetProperty("messageId", out var mi) ? mi.GetString() ?? "" : ""
                };
            }

            return new NoahResult { Success = false, Classification = "NOAH API returned empty response" };
        }
        catch (Exception ex)
        {
            return new NoahResult { Success = false, Classification = $"Failed to POST to NOAH API: {ex.Message}" };
        }
        finally
        {
            if (serverProcess != null)
                StopServer(serverProcess);
        }
    }

    public string CreateMinimalHl7Message(string customText, string? patientId = null, string? accessionNumber = null)
    {
        patientId ??= "TEST000001";
        accessionNumber ??= "TEST-ACC-001";

        string timestamp = DateTime.Now.ToString("yyyyMMddHHmmss");
        string msgId = Guid.NewGuid().ToString()[..8];

        string segmentSeparrator = "\r";

        var segments = new List<string>
        {
            $"MSH|^~\\&|ePATH|TEST_FACILITY|NOAH|NOAH_FACILITY|{timestamp}||ORU^R01|{msgId}|P|2.5.1",
            $"PID|1||{patientId}^^^TEST_FACILITY^MR||TEST^PATIENT||19700101|U",
            $"OBR|1||{accessionNumber}||88305^Surgical Pathology|||{timestamp}",
            $"OBX|1|FT|88305&ICD10&2.16.840.1.113883.6.90^Final Diagnosis^L|2|{customText}||||||F"
        };

        return string.Join(segmentSeparrator, segments);
    }
}
