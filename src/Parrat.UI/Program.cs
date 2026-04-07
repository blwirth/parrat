using Microsoft.Extensions.DependencyInjection;
using Parrat.Core.Interfaces;
using Parrat.Core.Services;
using Parrat.UI.Services;

namespace Parrat.UI;

internal static class Program
{
    [STAThread]
    static void Main()
    {
        ApplicationConfiguration.Initialize();

        try
        {
            var services = new ServiceCollection();
            ConfigureServices(services);
            var provider = services.BuildServiceProvider();

            var logger = provider.GetRequiredService<IParratLogger>();
            logger.Initialize();

            try
            {
                var mainForm = provider.GetRequiredService<Forms.MainForm>();

                // Read version from VERSION file (written by CI release)
                var versionPath = Path.Combine(Parrat.Core.Helpers.PathHelper.RepoRoot, "VERSION");
                if (File.Exists(versionPath))
                {
                    var version = File.ReadAllText(versionPath).Trim();
                    if (!string.IsNullOrEmpty(version))
                        mainForm.UpdateTitle(version);
                }

                Application.Run(mainForm);
            }
            finally
            {
                logger.Close();
                if (provider is IDisposable disposable)
                    disposable.Dispose();
            }
        }
        catch (Exception ex)
        {
            MessageBox.Show($"PARRAT failed to start:\n\n{ex.Message}\n\n{ex.StackTrace}",
                "Startup Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    private static void ConfigureServices(IServiceCollection services)
    {
        // Singleton state
        services.AddSingleton<AppState>();

        // Core services
        services.AddSingleton<IParratLogger, ParratLogger>();
        services.AddSingleton<INaaccrDictionary, NaaccrDictionary>();
        services.AddSingleton<IRecentFilesService, RecentFilesService>();
        services.AddSingleton<IConfigService, ConfigService>();
        services.AddSingleton<IHl7Parser, Hl7Parser>();
        services.AddSingleton<IXmlFileService, XmlFileService>();
        services.AddSingleton<IHl7FileService, Hl7FileService>();
        services.AddSingleton<IObxService, ObxService>();
        services.AddSingleton<IConcatenateService, ConcatenateService>();
        services.AddSingleton<IConvertTxtService, ConvertTxtService>();
        services.AddSingleton<ISearchService, SearchService>();
        services.AddSingleton<IDiffService, DiffService>();
        services.AddSingleton<IDeduplicationService, DeduplicationService>();
        services.AddSingleton<ISplitFileService, SplitFileService>();
        services.AddSingleton<ISiteLateralityService, SiteLateralityService>();
        services.AddSingleton<IFacilityAssignmentService, FacilityAssignmentService>();
        services.AddSingleton<IPidAssignmentService, PidAssignmentService>();
        services.AddSingleton<IExportService, ExportService>();
        services.AddSingleton<ICsvParserService, CsvParserService>();
        services.AddSingleton<ICsvImportService, CsvImportService>();
        services.AddSingleton<IXlsxParserService, XlsxParserService>();
        services.AddSingleton<IGridSettingsService, GridSettingsService>();
        services.AddSingleton<INoahService, NoahService>();
        services.AddSingleton<IRemoveVariableService, RemoveVariableService>();
        services.AddSingleton<IUnifiedAssignmentService, UnifiedAssignmentService>();

        // UI services
        services.AddSingleton<MenuBuilder>();
        services.AddSingleton<NavigationService>();
        services.AddSingleton<FileHandlers>();

        // Forms
        services.AddTransient<Forms.MainForm>();
    }
}
