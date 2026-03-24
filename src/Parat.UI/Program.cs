using Microsoft.Extensions.DependencyInjection;
using Parat.Core.Interfaces;
using Parat.UI.Services;

namespace Parat.UI;

internal static class Program
{
    [STAThread]
    static void Main()
    {
        ApplicationConfiguration.Initialize();

        var services = new ServiceCollection();
        ConfigureServices(services);
        var provider = services.BuildServiceProvider();

        // TODO: Uncomment when services are registered in Phase 1
        // var logger = provider.GetRequiredService<IParatLogger>();
        // logger.Initialize();
        //
        // try
        // {
        //     var mainForm = provider.GetRequiredService<Forms.MainForm>();
        //     Application.Run(mainForm);
        // }
        // finally
        // {
        //     logger.Close();
        //     if (provider is IDisposable disposable)
        //         disposable.Dispose();
        // }
    }

    private static void ConfigureServices(IServiceCollection services)
    {
        // Singleton state
        services.AddSingleton<AppState>();

        // Core services — implementations will be registered in Phase 1
        // services.AddSingleton<IParatLogger, ParatLogger>();
        // services.AddSingleton<INaaccrDictionary, NaaccrDictionary>();
        // services.AddSingleton<IRecentFilesService, RecentFilesService>();
        // services.AddSingleton<IConfigService, ConfigService>();
        // services.AddSingleton<IHl7Parser, Hl7Parser>();
        // services.AddSingleton<IXmlFileService, XmlFileService>();
        // services.AddSingleton<IHl7FileService, Hl7FileService>();
        // services.AddSingleton<IObxService, ObxService>();
        // services.AddSingleton<IConcatenateService, ConcatenateService>();
        // services.AddSingleton<IConvertTxtService, ConvertTxtService>();
        // services.AddSingleton<ISearchService, SearchService>();
        // services.AddSingleton<IDiffService, DiffService>();
        // services.AddSingleton<IDeduplicationService, DeduplicationService>();
        // services.AddSingleton<ISplitFileService, SplitFileService>();
        // services.AddSingleton<ISiteLateralityService, SiteLateralityService>();
        // services.AddSingleton<IFacilityAssignmentService, FacilityAssignmentService>();
        // services.AddSingleton<IPidAssignmentService, PidAssignmentService>();
        // services.AddSingleton<IExportService, ExportService>();
        // services.AddSingleton<INoahService, NoahService>();
        // services.AddSingleton<IRemoveVariableService, RemoveVariableService>();
        // services.AddSingleton<IUnifiedAssignmentService, UnifiedAssignmentService>();

        // UI services
        // services.AddSingleton<MenuBuilder>();
        // services.AddSingleton<NavigationService>();

        // Forms
        // services.AddTransient<Forms.MainForm>();
    }
}
