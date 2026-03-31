using System.Data;
using System.Windows.Forms;
using System.Xml;
using Parat.Core.Interfaces;
using Parat.Core.Models;
using Parat.Core.Services;

namespace Parat.UI.Services;

/// <summary>
/// Loads a file into a FileContext and configures a reference grid.
/// The DataTable has NO "Selected" column -- structural export isolation.
/// Does not touch AppState, MenuBuilder, RecentFilesService, or any
/// export/edit service.
/// </summary>
public class ReferenceFileLoader
{
    private readonly IXmlFileService _xmlFileService;
    private readonly IHl7FileService _hl7FileService;
    private readonly IGridSettingsService _gridSettingsService;
    private readonly IParatLogger _logger;

    public ReferenceFileLoader(
        IXmlFileService xmlFileService,
        IHl7FileService hl7FileService,
        IGridSettingsService gridSettingsService,
        IParatLogger logger)
    {
        _xmlFileService = xmlFileService;
        _hl7FileService = hl7FileService;
        _gridSettingsService = gridSettingsService;
        _logger = logger;
    }

    /// <summary>
    /// Loads the given file into the FileContext and binds it to the grid.
    /// Returns true on success.
    /// </summary>
    public bool LoadFile(string filePath, FileContext ctx, DataGridView grid)
    {
        var extension = Path.GetExtension(filePath).ToLowerInvariant();

        if (extension == ".hl7")
            return LoadHl7(filePath, ctx, grid);
        else
            return LoadXml(filePath, ctx, grid);
    }

    private bool LoadXml(string filePath, FileContext ctx, DataGridView grid)
    {
        try
        {
            ctx.Reset();

            var (doc, tumors, nsMgr) = _xmlFileService.LoadNaaccrXml(filePath);

            ctx.XmlDoc = doc;
            ctx.Tumors = tumors;
            ctx.NsMgr = nsMgr;
            ctx.CurrentFilePath = filePath;
            ctx.FileType = "xml";
            ctx.CurrentIndex = -1;

            if (tumors.Count == 0)
            {
                MessageBox.Show("No <Tumor> elements found in this file.", "No Tumors");
                return false;
            }

            var gridSettings = _gridSettingsService.Load();
            var xmlCols = gridSettings.Xml.Columns;

            // Build DataTable WITHOUT "Selected" column
            var table = new DataTable();
            table.Columns.Add("Index", typeof(int));
            foreach (var col in xmlCols)
                table.Columns.Add(col.Id, typeof(string));

            table.BeginLoadData();
            for (int i = 0; i < tumors.Count; i++)
            {
                var tumor = tumors[i]!;
                var patient = _xmlFileService.GetPatientForTumor(tumor);

                var row = table.NewRow();
                row["Index"] = i + 1;
                foreach (var col in xmlCols)
                {
                    var val = _xmlFileService.GetItemValue(tumor, col.Id, nsMgr);
                    if (string.IsNullOrEmpty(val) && patient != null)
                        val = _xmlFileService.GetItemValue(patient, col.Id, nsMgr);
                    row[col.Id] = val;
                }

                table.Rows.Add(row);
            }
            table.EndLoadData();

            ctx.NavTable = table;

            ctx.IsLoadingData = true;
            grid.DataSource = null;
            grid.Columns.Clear();
            grid.DataSource = table;

            FileHandlers.ConfigureGridColumns(grid, xmlCols);

            ctx.IsLoadingData = false;

            // Build search index
            var searchService = new SearchService(tumors, nsMgr);
            ctx.SearchIndex = searchService.BuildSearchIndex("xml");

            _logger.Log("INFO", $"Reference loaded: {Path.GetFileName(filePath)} ({tumors.Count} tumors)", "REF_OPEN");
            return true;
        }
        catch (Exception ex)
        {
            _logger.LogError("Failed to load reference XML file", "REF_OPEN", ex);
            MessageBox.Show($"Error loading reference XML: {ex.Message}", "Error");
            return false;
        }
    }

    private bool LoadHl7(string filePath, FileContext ctx, DataGridView grid)
    {
        try
        {
            ctx.Reset();

            var messages = _hl7FileService.LoadHl7File(filePath);

            if (messages.Count == 0)
            {
                MessageBox.Show("No HL7 messages found in this file.", "No Messages");
                return false;
            }

            ctx.Hl7Messages = messages;
            ctx.CurrentFilePath = filePath;
            ctx.FileType = "hl7";
            ctx.CurrentIndex = -1;

            var gridSettings = _gridSettingsService.Load();

            // Build DataTable WITHOUT "Selected" column
            var table = new DataTable();
            table.Columns.Add("Index", typeof(int));
            table.Columns.Add("nameLast", typeof(string));
            table.Columns.Add("nameFirst", typeof(string));
            table.Columns.Add("dateOfBirth", typeof(string));
            table.Columns.Add("accessionNumber", typeof(string));
            table.Columns.Add("patientId", typeof(string));
            table.Columns.Add("messageType", typeof(string));
            table.Columns.Add("orderDateTime", typeof(string));

            table.BeginLoadData();
            foreach (var msg in messages)
            {
                var row = table.NewRow();
                row["Index"] = msg.Index + 1;
                row["nameLast"] = msg.PatientLastName;
                row["nameFirst"] = msg.PatientFirstName;
                row["dateOfBirth"] = msg.DateOfBirth;
                row["accessionNumber"] = msg.AccessionNumber;
                row["patientId"] = msg.PatientId;
                row["messageType"] = msg.MessageType;
                row["orderDateTime"] = msg.OrderDateTime;

                table.Rows.Add(row);
            }
            table.EndLoadData();

            ctx.NavTable = table;

            ctx.IsLoadingData = true;
            grid.DataSource = null;
            grid.Columns.Clear();
            grid.DataSource = table;

            FileHandlers.ConfigureGridColumns(grid, gridSettings.Hl7.Columns);

            ctx.IsLoadingData = false;

            // Build search index
            var searchService = new SearchService(null, null, messages);
            ctx.SearchIndex = searchService.BuildSearchIndex("hl7");

            _logger.Log("INFO", $"Reference loaded: {Path.GetFileName(filePath)} ({messages.Count} messages)", "REF_OPEN");
            return true;
        }
        catch (Exception ex)
        {
            _logger.LogError("Failed to load reference HL7 file", "REF_OPEN", ex);
            MessageBox.Show($"Error loading reference HL7: {ex.Message}", "Error");
            return false;
        }
    }
}
