using System.Data;
using System.Diagnostics;
using System.Text.RegularExpressions;
using System.Xml;
using Parrat.Core.Helpers;
using Parrat.Core.Interfaces;
using Parrat.Core.Models;

namespace Parrat.UI.Forms;

/// <summary>
/// Partial class containing all action handlers for MainForm menu items.
/// Phase 3 Agent 2: View, Edit, Export, Tools, Settings, and Help handlers.
/// </summary>
public partial class MainForm
{
    // ── DI-resolved services (set via constructor) ──
    private IDiffService _diffService = null!;
    private IXmlFileService _xmlFileService = null!;
    private IHl7FileService _hl7FileService = null!;
    private IDeduplicationService _deduplicationService = null!;
    private IUnifiedAssignmentService _unifiedAssignmentService = null!;
    private ISiteLateralityService _siteLateralityService = null!;
    private IFacilityAssignmentService _facilityAssignmentService = null!;
    private IObxService _obxService = null!;
    private IPidAssignmentService _pidAssignmentService = null!;
    private IRemoveVariableService _removeVariableService = null!;
    private IConvertTxtService _convertTxtService = null!;
    private IExportService _exportService = null!;
    private INoahService _noahService = null!;
    private ISplitFileService _splitFileService = null!;
    private IConcatenateService _concatenateService = null!;
    private IConfigService _configService = null!;
    private INaaccrDictionary _naaccrDictionary = null!;
    private ICsvParserService _csvParserService = null!;
    private ICsvImportService _csvImportService = null!;
    private IXlsxParserService _xlsxParserService = null!;
    private IEpathParserService _epathParserService = null!;

    /// <summary>
    /// Wires all menu item Click handlers to the appropriate handler methods.
    /// </summary>
    private void WireMenuHandlers()
    {
        var mb = _menuBuilder;

        // ── View ──────────────────────────────────────────────────────────
        mb.MnuRawRecord.Click += (s, e) => OnShowRawRecord();
        mb.MnuDiffRecords.Click += (s, e) => OnDiffRecords();

        // ── File (items owned by Agent 2) ─────────────────────────────────
        mb.MnuDiffFiles.Click += (s, e) => OnDiffFiles();
        mb.MenuItemConcatenateXml.Click += (s, e) => OnConcatenateXml();
        mb.MenuItemConcatenateHl7.Click += (s, e) => OnConcatenateHl7();
        mb.MenuItemConcatenateTxt.Click += (s, e) => OnConcatenateTxt();
        mb.MnuSplit.Click += (s, e) => OnSplitFile();
        mb.MnuConvertTxt.Click += (s, e) => OnConvertTxt();
        mb.MnuImportCsv.Click += (s, e) => OnImportCsv();
        mb.MnuConvertDatToHl7.Click += (s, e) => OnConvertDatToHl7();

        // ── Edit ──────────────────────────────────────────────────────────
        mb.MnuAssign.Click += (s, e) => OnAssignUnified();
        mb.MenuItemFixObx31.Click += (s, e) => OnFixObx();
        mb.MenuItemRemoveEmptyObx5.Click += (s, e) => OnRemoveEmptyObx5();
        mb.MenuItemRemoveVariable.Click += (s, e) => OnRemoveVariable();
        mb.MenuItemTrueMatches.Click += (s, e) => OnDedupTrueMatches();
        mb.MenuItemPrimaryKey.Click += (s, e) => OnDedupPrimaryKey();
        mb.MenuItemPathReport.Click += (s, e) => OnDedupPathReport();

        // ── Export ─────────────────────────────────────────────────────────
        mb.MnuExport.DropDownOpening += OnExportDropDownOpening;
        mb.MnuExportSelectedXml.Click += (s, e) => OnExportSelectedXml();
        mb.MnuExportSelectedHl7.Click += (s, e) => OnExportSelectedHl7();
        mb.MnuExportAllCsv.Click += (s, e) =>
        {
            if (_state.FileType == "hl7") OnExportAllHl7Csv();
            else OnExportAllCsv();
        };
        mb.MnuExportSelectedCsv.Click += (s, e) =>
        {
            if (_state.FileType == "hl7") OnExportSelectedHl7Csv();
            else OnExportSelectedCsv();
        };

        // ── Tools ─────────────────────────────────────────────────────────
        mb.MnuTestSiteLatCurrent.Click += (s, e) => OnTestSiteLatCurrent();
        mb.MnuTestSiteLatCustom.Click += (s, e) => OnTestSiteLatCustom();
        mb.MnuFilterCurrentHl7.Click += (s, e) => OnNoahReportability();
        mb.MnuFilterCustomPayload.Click += (s, e) => OnNoahCustomPayload();

        // ── Settings ──────────────────────────────────────────────────────
        mb.MnuManageCodingTables.DropDownOpening += OnManageTablesDropDownOpening;
        mb.MnuNoahConfig.Click += (s, e) => OnNoahConfig();
        mb.MnuObxSkipCodes.Click += (s, e) => OnObxSkipCodes();
        mb.MnuGridColumns.Click += (s, e) => OnGridColumns();

        // ── Help ──────────────────────────────────────────────────────────
        mb.MnuUserManual.Click += (s, e) => OnUserManual();
        mb.MnuOpenLogs.Click += (s, e) => OnOpenLogsFolder();
    }

    // =====================================================================
    //  VIEW HANDLERS
    // =====================================================================

    /// <summary>Show Raw Record — opens RawRecordForm for the selected record.</summary>
    private void OnShowRawRecord()
    {
        try
        {
            var fileType = _state.FileType;
            int recordCount = _state.RecordCount;

            if (recordCount == 0)
            {
                var typeLabel = fileType == "hl7" ? "messages" : "tumors";
                MessageBox.Show($"No {typeLabel} loaded.", "Show Raw",
                    MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }

            if (_gridNav.SelectedRows.Count == 0)
            {
                MessageBox.Show("Please select a row in the grid first.", "Show Raw",
                    MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }

            var val = _gridNav.SelectedRows[0].Cells["Index"].Value;
            if (val == null)
            {
                MessageBox.Show("Unable to determine index for selected row.", "Show Raw",
                    MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            int idx = Convert.ToInt32(val) - 1;

            if (fileType == "hl7")
            {
                if (idx < 0 || idx >= _state.Hl7Messages.Count) return;
                var message = _state.Hl7Messages[idx];
                var rawContent = string.Join("\r\n",
                    message.Segments.SelectMany(kvp => kvp.Value));
                var label = $"Message {idx + 1} of {_state.Hl7Messages.Count}";
                using var form = RawRecordForm.CreateHl7Viewer(rawContent, label);
                form.ShowDialog(this);
            }
            else
            {
                if (_state.Tumors == null || _state.XmlDoc == null || _state.NsMgr == null) return;
                if (idx < 0 || idx >= _state.Tumors.Count) return;
                var tumor = _state.Tumors[idx]!;
                var label = $"Tumor {idx + 1} of {_state.Tumors.Count}";
                using var form = RawRecordForm.CreateXmlViewer(_state.XmlDoc, tumor, _state.NsMgr, label);
                form.ShowDialog(this);
            }
        }
        catch (Exception ex)
        {
            _logger.LogError("Show raw failed", "SHOW_RAW", ex);
            MessageBox.Show($"Error showing raw data: {ex.Message}", "Error",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    /// <summary>Diff Records — opens DiffViewerForm for two selected records.</summary>
    private void OnDiffRecords()
    {
        try
        {
            var fileType = _state.FileType;
            int recordCount = _state.RecordCount;

            if (recordCount == 0)
            {
                var typeLabel = fileType == "hl7" ? "messages" : "tumors";
                MessageBox.Show($"No {typeLabel} loaded.", "Diff",
                    MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }

            if (_gridNav.SelectedRows.Count != 2)
            {
                MessageBox.Show("Please select exactly two rows in the grid to compare.", "Diff",
                    MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }

            var indexVals = new List<int>();
            foreach (DataGridViewRow r in _gridNav.SelectedRows)
            {
                var val = r.Cells["Index"].Value;
                if (val != null) indexVals.Add(Convert.ToInt32(val));
            }

            if (indexVals.Count != 2)
            {
                MessageBox.Show("Unable to determine both indices for comparison.", "Diff",
                    MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            int idxA = indexVals[0] - 1;
            int idxB = indexVals[1] - 1;

            if (idxA < 0 || idxA >= recordCount || idxB < 0 || idxB >= recordCount)
            {
                MessageBox.Show("Selected indices are out of range.", "Diff",
                    MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            string[] linesA, linesB;
            string labelA, labelB;

            if (fileType == "hl7")
            {
                linesA = _diffService.GetHl7MessageLines(idxA);
                linesB = _diffService.GetHl7MessageLines(idxB);
                labelA = _diffService.GetHl7MessageLabel(idxA);
                labelB = _diffService.GetHl7MessageLabel(idxB);
            }
            else
            {
                linesA = _diffService.GetFormattedTumorXml(idxA);
                linesB = _diffService.GetFormattedTumorXml(idxB);
                labelA = _diffService.GetTumorLabel(idxA);
                labelB = _diffService.GetTumorLabel(idxB);
            }

            var diffLines = _diffService.GetDiffLines(linesA, linesB);
            using var form = new DiffViewerForm(diffLines, labelA, labelB, "Diff");
            form.ShowDialog(this);
        }
        catch (Exception ex)
        {
            _logger.LogError("Diff failed", "DIFF", ex);
            MessageBox.Show($"Error during diff: {ex.Message}", "Error",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    /// <summary>Diff Files — opens DiffFilesForm to compare two files.</summary>
    private void OnDiffFiles()
    {
        try
        {
            using var form = new DiffFilesForm(_diffService, _xmlFileService, _hl7FileService);
            if (form.ShowDialog(this) == DialogResult.OK)
            {
                // Comparison was performed inside the DiffFilesForm
            }
        }
        catch (Exception ex)
        {
            _logger.LogError("File diff failed", "DIFF_FILES", ex);
            MessageBox.Show($"Error during file diff: {ex.Message}", "Error",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    // =====================================================================
    //  EDIT HANDLERS
    // =====================================================================

    /// <summary>Dedup true matches.</summary>
    private void OnDedupTrueMatches() => RunDedup("TrueMatches");

    /// <summary>Dedup by primary key.</summary>
    private void OnDedupPrimaryKey() => RunDedup("PrimaryKey");

    /// <summary>Dedup by pathReportNumber1.</summary>
    private void OnDedupPathReport() => RunDedup("PathReport");

    /// <summary>Common deduplication handler for all three modes.</summary>
    private void RunDedup(string dedupType)
    {
        if (_state.Tumors == null || _state.Tumors.Count == 0)
        {
            MessageBox.Show("No XML file loaded.", "Deduplicate",
                MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }

        if (string.IsNullOrEmpty(_state.CurrentFilePath))
        {
            MessageBox.Show("No file path available.", "Deduplicate",
                MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }

        try
        {
            SetStatusText($"Analyzing duplicates ({dedupType})...");
            Refresh();

            _logger.Log("INFO", $"Starting deduplication ({dedupType}) for {_state.Tumors.Count} tumors", "DEDUPLICATE");

            DeduplicationResult result = dedupType switch
            {
                "TrueMatches" => _deduplicationService.GetDuplicates(_state.Tumors, _state.NsMgr!),
                "PrimaryKey" => _deduplicationService.GetDuplicatesByPrimaryKey(_state.Tumors, _state.NsMgr!),
                "PathReport" => _deduplicationService.GetDuplicatesByPathReport(_state.Tumors, _state.NsMgr!),
                _ => throw new ArgumentException($"Unknown dedup type: {dedupType}")
            };

            _logger.Log("INFO", $"Deduplication analysis complete: {result.Report.Count} duplicates found", "DEDUPLICATE");
            SetStatusText($"Loaded: {Path.GetFileName(_state.CurrentFilePath)} (Tumors: {_state.Tumors.Count})");

            // Show preview
            using var previewForm = new DeduplicationPreviewForm(result, _state.Tumors.Count, dedupType);
            if (previewForm.ShowDialog(this) != DialogResult.OK)
                return;

            var fileSuffix = previewForm.GetFileSuffix();

            // Show report with save options
            using var reportForm = new DeduplicationReportForm(
                _deduplicationService,
                result.Report,
                result.IndicesToKeep,
                _state.Tumors.Count,
                _state.CurrentFilePath,
                _state.XmlDoc!,
                _state.Tumors,
                fileSuffix,
                _logger);
            reportForm.ShowDialog(this);
        }
        catch (Exception ex)
        {
            _logger.LogError($"Deduplication ({dedupType}) failed", "DEDUPLICATE", ex);
            MessageBox.Show($"Error during deduplication: {ex.Message}", "Error",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
            SetStatusText("Error during deduplication");
        }
    }

    /// <summary>Assign Unified — opens AssignUnifiedForm then preview.</summary>
    private void OnAssignUnified()
    {
        if (_state.Tumors == null || _state.Tumors.Count == 0)
        {
            MessageBox.Show("No XML file loaded.", "Unified Assignment",
                MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }

        if (string.IsNullOrEmpty(_state.CurrentFilePath))
        {
            MessageBox.Show("No file path available.", "Unified Assignment",
                MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }

        try
        {
            // Count unique patients
            int patientCount = 0;
            var processedPatients = new HashSet<XmlNode>();
            foreach (XmlNode tumor in _state.Tumors)
            {
                var patient = tumor.SelectSingleNode("ancestor::n:Patient[1]", _state.NsMgr!);
                if (patient != null && processedPatients.Add(patient))
                    patientCount++;
            }

            // Show options dialog
            using var optionsForm = new AssignUnifiedForm(
                _unifiedAssignmentService,
                _siteLateralityService,
                _facilityAssignmentService,
                _state.CurrentFilePath,
                _state.Tumors.Count,
                patientCount,
                _state.Tumors,
                _state.NsMgr!);

            if (optionsForm.ShowDialog(this) != DialogResult.OK || optionsForm.ResultOptions == null)
                return;

            var options = optionsForm.ResultOptions;

            // Check at least one option selected
            bool anySel = (options.TryGetValue("AssignSite", out var asBool) && asBool is true)
                       || (options.TryGetValue("AssignLaterality", out var alBool) && alBool is true)
                       || (options.TryGetValue("AssignFacility", out var afBool) && afBool is true)
                       || (options.TryGetValue("AssignPid", out var apBool) && apBool is true);

            if (!anySel)
            {
                MessageBox.Show("Please select at least one assignment option.",
                    "Unified Assignment", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            SetStatusText("Analyzing records for unified assignment...");
            Refresh();

            _logger.Log("INFO", $"Starting unified assignment analysis for {_state.Tumors.Count} tumors", "ASSIGN");

            var sw = Stopwatch.StartNew();
            var result = _unifiedAssignmentService.GetUnifiedAssignments(_state.Tumors, _state.NsMgr!, options);
            sw.Stop();

            SetStatusText($"Loaded: {Path.GetFileName(_state.CurrentFilePath)} (Tumors: {_state.Tumors.Count}) | Analysis: {sw.Elapsed.TotalSeconds:F2}s");

            int changesFound = result.Report.Count(r => r.TryGetValue("HasChanges", out var hc) && hc is true);

            if (changesFound == 0)
            {
                _logger.Log("INFO", "Unified assignment complete: no changes needed", "ASSIGN");
                MessageBox.Show("No records need updating based on the selected options.",
                    "Unified Assignment", MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }

            _logger.Log("INFO", $"Unified assignment analysis complete: {changesFound} records with changes", "ASSIGN");

            // Show preview
            using var previewForm = new AssignUnifiedPreviewForm(
                _unifiedAssignmentService,
                result.Report,
                options,
                _state.Tumors,
                _state.XmlDoc!,
                _state.NsMgr!);

            if (previewForm.ShowDialog(this) != DialogResult.OK)
                return;

            if (previewForm.SaveXmlClicked)
            {
                var suffix = _unifiedAssignmentService.GetFileSuffix(options, result.Report);
                var originalFileName = Path.GetFileNameWithoutExtension(_state.CurrentFilePath);
                var extension = Path.GetExtension(_state.CurrentFilePath);
                var directory = Path.GetDirectoryName(_state.CurrentFilePath) ?? ".";
                var outputPath = Path.Combine(directory, $"{originalFileName}{suffix}{extension}");

                _unifiedAssignmentService.WriteUnifiedAssignedXml(
                    _state.XmlDoc!, _state.Tumors,
                    result.TumorAssignments, result.PatientAssignments,
                    _state.NsMgr!, outputPath);

                _logger.Log("INFO", $"Unified assignment saved to {Path.GetFileName(outputPath)}", "ASSIGN");

                var dlgResult = MessageBox.Show(
                    $"Assignment saved to:\n{outputPath}\n\nOpen containing folder?",
                    "Unified Assignment Complete",
                    MessageBoxButtons.YesNo, MessageBoxIcon.Information);

                if (dlgResult == DialogResult.Yes)
                    OpenFolderAndSelect(outputPath);
            }
        }
        catch (Exception ex)
        {
            _logger.LogError("Unified assignment failed", "ASSIGN", ex);
            MessageBox.Show($"Error during unified assignment: {ex.Message}", "Error",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
            SetStatusText("Error during unified assignment");
        }
    }

    /// <summary>Fix OBX 3.1 — repairs truncated OBX segments in HL7 files.</summary>
    private void OnFixObx()
    {
        if (_state.Hl7Messages.Count == 0)
        {
            MessageBox.Show("No HL7 file loaded.", "Fix OBX3.1",
                MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }

        if (string.IsNullOrEmpty(_state.CurrentFilePath))
        {
            MessageBox.Show("No file path available.", "Fix OBX3.1",
                MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }

        try
        {
            SetStatusText("Fixing OBX segments...");
            Refresh();

            _logger.Log("INFO", $"Starting Fix OBX 3.1 for {_state.Hl7Messages.Count} messages", "MODIFY_HL7");

            var rawContent = File.ReadAllText(_state.CurrentFilePath);
            var result = _obxService.RepairObxInRawContent(rawContent);

            if (result.RepairedCount == 0)
            {
                _logger.Log("INFO", "Fix OBX 3.1: no truncated segments found", "MODIFY_HL7");
                MessageBox.Show("No truncated OBX segments found.",
                    "Fix OBX3.1", MessageBoxButtons.OK, MessageBoxIcon.Information);
                SetStatusText($"Loaded: {Path.GetFileName(_state.CurrentFilePath)} (Messages: {_state.Hl7Messages.Count})");
                return;
            }

            var originalFileName = Path.GetFileNameWithoutExtension(_state.CurrentFilePath);
            var extension = Path.GetExtension(_state.CurrentFilePath);
            var directory = Path.GetDirectoryName(_state.CurrentFilePath) ?? ".";
            var outputPath = Path.Combine(directory, $"{originalFileName}-obx{extension}");

            File.WriteAllText(outputPath, result.Content, System.Text.Encoding.ASCII);

            _logger.Log("INFO", $"Fix OBX 3.1: fixed {result.RepairedCount} segments, saved to {Path.GetFileName(outputPath)}", "MODIFY_HL7");
            SetStatusText($"Loaded: {Path.GetFileName(_state.CurrentFilePath)} (Messages: {_state.Hl7Messages.Count})");

            var dlgResult = MessageBox.Show(
                $"Fixed {result.RepairedCount} OBX segments.\n\nSaved to:\n{outputPath}\n\nOpen containing folder?",
                "Fix OBX3.1 Complete", MessageBoxButtons.YesNo, MessageBoxIcon.Information);

            if (dlgResult == DialogResult.Yes)
                OpenFolderAndSelect(outputPath);
        }
        catch (Exception ex)
        {
            _logger.LogError("Fix OBX 3.1 failed", "MODIFY_HL7", ex);
            MessageBox.Show($"Error fixing OBX segments: {ex.Message}", "Error",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
            SetStatusText("Error fixing OBX segments");
        }
    }

    /// <summary>Remove Empty OBX-5 — removes OBX segments with empty OBX-5 values.</summary>
    private void OnRemoveEmptyObx5()
    {
        if (_state.Hl7Messages.Count == 0)
        {
            MessageBox.Show("No HL7 file loaded.", "Remove Empty OBX5",
                MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }

        if (string.IsNullOrEmpty(_state.CurrentFilePath))
        {
            MessageBox.Show("No file path available.", "Remove Empty OBX5",
                MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }

        try
        {
            SetStatusText("Removing empty OBX5 segments...");
            Refresh();

            _logger.Log("INFO", $"Starting Remove Empty OBX5 for {_state.Hl7Messages.Count} messages", "MODIFY_HL7");

            var rawContent = File.ReadAllText(_state.CurrentFilePath);
            var result = _obxService.RemoveEmptyObx5FromRawContent(rawContent);

            if (result.RemovedCount == 0)
            {
                _logger.Log("INFO", "Remove Empty OBX5: no empty segments found", "MODIFY_HL7");
                MessageBox.Show("No empty OBX5 segments found.",
                    "Remove Empty OBX5", MessageBoxButtons.OK, MessageBoxIcon.Information);
                SetStatusText($"Loaded: {Path.GetFileName(_state.CurrentFilePath)} (Messages: {_state.Hl7Messages.Count})");
                return;
            }

            var originalFileName = Path.GetFileNameWithoutExtension(_state.CurrentFilePath);
            var extension = Path.GetExtension(_state.CurrentFilePath);
            var directory = Path.GetDirectoryName(_state.CurrentFilePath) ?? ".";
            var outputPath = Path.Combine(directory, $"{originalFileName}-no-empty-obx5{extension}");

            File.WriteAllText(outputPath, result.Content, System.Text.Encoding.ASCII);

            _logger.Log("INFO", $"Remove Empty OBX5: removed {result.RemovedCount} segments, saved to {Path.GetFileName(outputPath)}", "MODIFY_HL7");
            SetStatusText($"Loaded: {Path.GetFileName(_state.CurrentFilePath)} (Messages: {_state.Hl7Messages.Count})");

            var dlgResult = MessageBox.Show(
                $"Removed {result.RemovedCount} OBX segments with empty OBX5 values.\n\nSaved to:\n{outputPath}\n\nOpen containing folder?",
                "Remove Empty OBX5 Complete", MessageBoxButtons.YesNo, MessageBoxIcon.Information);

            if (dlgResult == DialogResult.Yes)
                OpenFolderAndSelect(outputPath);
        }
        catch (Exception ex)
        {
            _logger.LogError("Remove Empty OBX5 failed", "MODIFY_HL7", ex);
            MessageBox.Show($"Error removing empty OBX5 segments: {ex.Message}", "Error",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
            SetStatusText("Error removing empty OBX5 segments");
        }
    }

    /// <summary>Remove Variable — prompts for NAACCR fields and removes them from XML.</summary>
    private void OnRemoveVariable()
    {
        if (_state.XmlDoc == null)
        {
            MessageBox.Show("No XML file loaded.", "Remove Variable",
                MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }

        if (_state.Tumors == null || _state.Tumors.Count == 0)
        {
            MessageBox.Show("No records found in the loaded file.", "Remove Variable",
                MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }

        if (string.IsNullOrEmpty(_state.CurrentFilePath))
        {
            MessageBox.Show("No file path available.", "Remove Variable",
                MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }

        try
        {
            SetStatusText("Scanning variables...");
            Refresh();

            var variables = _removeVariableService.GetUniqueNaaccrIds(_state.XmlDoc, _state.NsMgr!);

            if (variables.Count == 0)
            {
                MessageBox.Show("No variables found in the loaded file.", "Remove Variable",
                    MessageBoxButtons.OK, MessageBoxIcon.Information);
                SetStatusText($"Loaded: {Path.GetFileName(_state.CurrentFilePath)} (Tumors: {_state.Tumors.Count})");
                return;
            }

            SetStatusText($"Loaded: {Path.GetFileName(_state.CurrentFilePath)} (Tumors: {_state.Tumors.Count})");

            // Show variable selection using a simple CheckedListBox dialog
            var selectedIds = ShowVariableSelectionDialog(variables);

            if (selectedIds == null || selectedIds.Length == 0)
                return;

            var varWord = selectedIds.Length == 1 ? "variable" : "variables";
            var confirmResult = MessageBox.Show(
                $"Remove all occurrences of {selectedIds.Length} {varWord}?\n\nA new file will be created. The original file will not be modified.",
                "Confirm Remove Variable",
                MessageBoxButtons.YesNo, MessageBoxIcon.Question);

            if (confirmResult != DialogResult.Yes)
                return;

            SetStatusText($"Removing {selectedIds.Length} {varWord}...");
            Refresh();

            var originalFileName = Path.GetFileNameWithoutExtension(_state.CurrentFilePath);
            var extension = Path.GetExtension(_state.CurrentFilePath);
            var directory = Path.GetDirectoryName(_state.CurrentFilePath) ?? ".";
            var suffix = $"{selectedIds.Length}v";
            var outputPath = Path.Combine(directory, $"{originalFileName}-rm{suffix}{extension}");

            _logger.Log("INFO", $"Removing {selectedIds.Length} {varWord} ({string.Join(", ", selectedIds)}) from {Path.GetFileName(_state.CurrentFilePath)}", "MODIFY_XML");

            _removeVariableService.RemoveXmlVariable(_state.XmlDoc, selectedIds, outputPath);

            _logger.Log("INFO", $"Remove Variable: saved to {Path.GetFileName(outputPath)}", "MODIFY_XML");
            SetStatusText($"Loaded: {Path.GetFileName(_state.CurrentFilePath)} (Tumors: {_state.Tumors.Count})");

            var dlgResult = MessageBox.Show(
                $"Removed {selectedIds.Length} {varWord}.\n\nSaved to:\n{outputPath}\n\nOpen containing folder?",
                "Remove Variable Complete", MessageBoxButtons.YesNo, MessageBoxIcon.Information);

            if (dlgResult == DialogResult.Yes)
                OpenFolderAndSelect(outputPath);
        }
        catch (Exception ex)
        {
            _logger.LogError("Remove Variable failed", "MODIFY_XML", ex);
            MessageBox.Show($"Error removing variable: {ex.Message}", "Remove Variable Error",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
            SetStatusText("Error removing variable");
        }
    }

    /// <summary>Convert TXT — opens converter form for pathology text to HL7.</summary>
    private void OnConvertTxt()
    {
        try
        {
            // The ConvertTxt form is a self-contained form; the PS version builds
            // the entire UI inline. We open a simple file dialog approach here.
            using var ofd = new OpenFileDialog
            {
                Filter = "Text files (*.txt)|*.txt|All files (*.*)|*.*",
                Title = "Select Input Pathology Text File"
            };

            if (ofd.ShowDialog(this) != DialogResult.OK) return;

            var inputPath = ofd.FileName;

            // Ask for facility
            using var facilityForm = new Form
            {
                Text = "Select Facility",
                Width = 300,
                Height = 150,
                StartPosition = FormStartPosition.CenterParent,
                FormBorderStyle = FormBorderStyle.FixedDialog,
                MaximizeBox = false,
                MinimizeBox = false
            };

            var cmbFacility = new ComboBox
            {
                Location = new System.Drawing.Point(10, 30),
                Width = 260,
                DropDownStyle = ComboBoxStyle.DropDownList
            };
            cmbFacility.Items.AddRange(new object[] { "Parkland", "Portsmouth", "Frisbie", "SJH" });
            cmbFacility.SelectedIndex = 0;

            facilityForm.Controls.Add(new Label { Text = "Facility:", Location = new System.Drawing.Point(10, 10), AutoSize = true });
            facilityForm.Controls.Add(cmbFacility);

            var btnConvertOk = new Button { Text = "Convert", Location = new System.Drawing.Point(100, 70), DialogResult = DialogResult.OK };
            var btnConvertCancel = new Button { Text = "Cancel", Location = new System.Drawing.Point(190, 70), DialogResult = DialogResult.Cancel };
            facilityForm.Controls.AddRange(new Control[] { btnConvertOk, btnConvertCancel });
            facilityForm.AcceptButton = btnConvertOk;
            facilityForm.CancelButton = btnConvertCancel;

            if (facilityForm.ShowDialog(this) != DialogResult.OK) return;

            var facilityName = cmbFacility.SelectedItem?.ToString() ?? "Parkland";

            using var sfd = new SaveFileDialog
            {
                Filter = "HL7 files (*.hl7)|*.hl7|All files (*.*)|*.*",
                Title = "Save HL7 Output File",
                FileName = Path.GetFileNameWithoutExtension(inputPath) + ".hl7"
            };

            if (sfd.ShowDialog(this) != DialogResult.OK) return;

            SetStatusText("Converting...");
            Refresh();

            var result = _convertTxtService.ConvertPathologyTextToHl7(inputPath, sfd.FileName, facilityName);

            SetStatusText("Conversion complete");
            MessageBox.Show($"Conversion complete.\n\nOutput file: {sfd.FileName}",
                "Conversion Complete", MessageBoxButtons.OK, MessageBoxIcon.Information);
        }
        catch (Exception ex)
        {
            _logger.LogError("Text converter failed", "CONVERT", ex);
            MessageBox.Show($"Error during conversion: {ex.Message}", "Error",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    /// <summary>Import CSV — parse CSV, map columns to NAACCR fields, generate XML.</summary>
    private void OnImportCsv()
    {
        try
        {
            using var ofd = new OpenFileDialog
            {
                Filter = "Spreadsheet Files (*.csv;*.xlsx)|*.csv;*.xlsx|CSV Files (*.csv)|*.csv|Excel Files (*.xlsx)|*.xlsx|All files (*.*)|*.*",
                Title = "Select CSV or Excel File to Import"
            };

            if (ofd.ShowDialog(this) != DialogResult.OK) return;

            SetStatusText("Parsing file...");
            Refresh();

            var extension = Path.GetExtension(ofd.FileName).ToLowerInvariant();
            var csvData = extension == ".xlsx"
                ? _xlsxParserService.Parse(ofd.FileName)
                : _csvParserService.Parse(ofd.FileName);

            if (csvData.ColumnCount == 0)
            {
                MessageBox.Show("The CSV file has no columns.", "Convert CSV",
                    MessageBoxButtons.OK, MessageBoxIcon.Warning);
                SetStatusText("Ready");
                return;
            }

            if (csvData.RowCount == 0)
            {
                MessageBox.Show("The CSV file has headers but no data rows.", "Convert CSV",
                    MessageBoxButtons.OK, MessageBoxIcon.Warning);
                SetStatusText("Ready");
                return;
            }

            // Auto-match columns
            var mappings = _csvImportService.AutoMatch(csvData.Headers);

            // Show mapping form
            using var importForm = new CsvImportForm(_naaccrDictionary, _csvImportService, csvData, mappings);
            if (importForm.ShowDialog(this) != DialogResult.OK) return;

            var finalMappings = importForm.ResultMappings;
            var recordType = importForm.RecordType;
            var naaccrVersion = importForm.NaaccrVersion;

            // Check that at least one column is mapped
            if (finalMappings.All(m => m.IsSkipped))
            {
                MessageBox.Show("No columns are mapped. Import cancelled.", "Convert CSV",
                    MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            SetStatusText("Generating NAACCR XML...");
            Refresh();

            var xmlDoc = _csvImportService.GenerateNaaccrXml(csvData, finalMappings, naaccrVersion, recordType);

            // Save
            using var sfd = new SaveFileDialog
            {
                Filter = "NAACCR XML (*.xml)|*.xml|All files (*.*)|*.*",
                Title = "Save Generated NAACCR XML",
                FileName = Path.GetFileNameWithoutExtension(ofd.FileName) + "_naaccr.xml",
                InitialDirectory = Path.GetDirectoryName(ofd.FileName) ?? ""
            };

            if (sfd.ShowDialog(this) != DialogResult.OK) return;

            // Format and save
            var formattedXml = Parrat.Core.Helpers.XmlFormattingHelper.FormatXml(xmlDoc.OuterXml);
            File.WriteAllText(sfd.FileName, formattedXml, System.Text.Encoding.UTF8);

            _logger.Log("INFO", $"CSV imported: {csvData.RowCount} rows → {sfd.FileName}", "IMPORT");

            var openResult = MessageBox.Show(
                $"NAACCR XML saved to:\n{sfd.FileName}\n\nOpen in PARRAT?",
                "Import Complete",
                MessageBoxButtons.YesNo,
                MessageBoxIcon.Information);

            if (openResult == DialogResult.Yes)
            {
                _fileHandlers.OpenFile(sfd.FileName, this);
            }

            SetStatusText("Ready");
        }
        catch (Exception ex)
        {
            _logger.LogError("CSV import failed", "IMPORT", ex);
            MessageBox.Show($"Error converting CSV: {ex.Message}", "Convert Error",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
            SetStatusText("Error converting CSV");
        }
    }

    /// <summary>Convert ePath .dat data to HL7 file on disk. Prompts for a file if none loaded.</summary>
    private void OnConvertDatToHl7()
    {
        try
        {
            List<EpathRecord> records;
            string? inputPath;

            if (_state.FileType == "epath" && _state.EpathRecords.Count > 0)
            {
                // Use already-loaded records
                records = _state.EpathRecords;
                inputPath = _state.CurrentFilePath;
            }
            else
            {
                // Prompt for a .dat file (same UX as Convert .txt)
                using var ofd = new OpenFileDialog
                {
                    Filter = "ePath Flat Files (*.dat)|*.dat|All files (*.*)|*.*",
                    Title = "Select ePath .dat File"
                };

                if (ofd.ShowDialog(this) != DialogResult.OK) return;

                inputPath = ofd.FileName;
                SetStatusText("Parsing .dat file...");
                Refresh();

                records = _epathParserService.ParseDatFile(inputPath);
                if (records.Count == 0)
                {
                    MessageBox.Show("No ePath records found in this file.", "Convert .dat to .hl7",
                        MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    SetStatusText("Ready");
                    return;
                }
            }

            // Show preview dialog
            SetStatusText("Ready");
            using var preview = new EpathPreviewForm(records, _epathParserService);
            if (preview.ShowDialog(this) != DialogResult.OK) return;

            var defaultName = Path.GetFileNameWithoutExtension(inputPath ?? "epath") + ".hl7";

            using var sfd = new SaveFileDialog
            {
                Filter = "HL7 Files (*.hl7)|*.hl7|All files (*.*)|*.*",
                Title = "Convert .dat to .hl7",
                FileName = defaultName,
                InitialDirectory = Path.GetDirectoryName(inputPath) ?? ""
            };

            if (sfd.ShowDialog(this) != DialogResult.OK) return;

            SetStatusText("Converting to HL7...");
            Refresh();

            var hl7Messages = _epathParserService.ConvertToHl7(records);
            _hl7FileService.SaveHl7File(sfd.FileName, hl7Messages);

            var version = records[0].FormatVersion == "NOAH v2" ? "2.5.1" : "2.3.1";
            _logger.Log("INFO", $"Converted {hl7Messages.Count} ePath records to HL7 v{version}: {sfd.FileName}", "EPATH_CONVERT");

            var openResult = MessageBox.Show(
                $"HL7 v{version} file saved to:\n{sfd.FileName}\n\n{hl7Messages.Count} messages written.\n\nOpen in PARRAT?",
                "Conversion Complete",
                MessageBoxButtons.YesNo,
                MessageBoxIcon.Information);

            if (openResult == DialogResult.Yes)
            {
                _fileHandlers.OpenFile(sfd.FileName, this);
            }

            SetStatusText("Ready");
        }
        catch (Exception ex)
        {
            _logger.LogError("ePath to HL7 conversion failed", "EPATH_CONVERT", ex);
            MessageBox.Show($"Error converting .dat to .hl7: {ex.Message}", "Conversion Error",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
            SetStatusText("Error converting .dat to .hl7");
        }
    }

    // =====================================================================
    //  EXPORT HANDLERS
    // =====================================================================

    /// <summary>Toggles export menu item enabled states based on current file type.</summary>
    private void OnExportDropDownOpening(object? sender, EventArgs e)
    {
        var fileType = _state.FileType;
        bool isXml = fileType == "xml";
        bool isHl7 = fileType == "hl7";

        var mb = _menuBuilder;
        mb.MnuExportSelectedXml.Enabled = isXml;
        mb.MnuExportSelectedHl7.Enabled = isHl7;
        mb.MnuExportAllCsv.Enabled = isXml || isHl7;
        mb.MnuExportSelectedCsv.Enabled = isXml || isHl7;
    }

    private int[] GetCheckedIndices()
    {
        _gridNav.EndEdit();
        var checkedIndices = new List<int>();
        foreach (DataGridViewRow row in _gridNav.Rows)
        {
            var cell = row.Cells["Selected"];
            if (cell.EditedFormattedValue is true)
            {
                var indexVal = row.Cells["Index"].Value;
                if (indexVal != null && indexVal != DBNull.Value)
                    checkedIndices.Add(Convert.ToInt32(indexVal) - 1);
            }
        }
        return checkedIndices.ToArray();
    }

    private void OnExportSelectedXml()
    {
        if (_state.Tumors == null || _state.Tumors.Count == 0 || _state.XmlDoc == null || _state.NsMgr == null)
        {
            MessageBox.Show("No XML file loaded.", "Export Selected", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }

        var indices = GetCheckedIndices();
        if (indices.Length == 0)
        {
            MessageBox.Show("Please select at least one tumor to export by checking the boxes in the first column.",
                "No Tumors Selected", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }

        try
        {
            using var sfd = new SaveFileDialog
            {
                Filter = "NAACCR XML (*.xml)|*.xml|All files (*.*)|*.*",
                Title = "Save Exported XML File"
            };
            if (!string.IsNullOrEmpty(_state.CurrentFilePath))
            {
                sfd.FileName = Path.GetFileNameWithoutExtension(_state.CurrentFilePath) + "_exported.xml";
                sfd.InitialDirectory = Path.GetDirectoryName(_state.CurrentFilePath) ?? "";
            }

            if (sfd.ShowDialog(this) != DialogResult.OK) return;

            SetStatusText($"Exporting {indices.Length} tumor(s)...");
            Refresh();

            _exportService.ExportSelectedXml(indices, _state.XmlDoc, _state.NsMgr, sfd.FileName);

            _logger.Log("INFO", $"Exported {indices.Length} tumor(s) to {Path.GetFileName(sfd.FileName)}", "EXPORT");
            SetStatusText($"Loaded: {Path.GetFileName(_state.CurrentFilePath)} (Tumors: {_state.Tumors.Count})");

            var dlgResult = MessageBox.Show(
                $"Successfully exported {indices.Length} tumor(s) to:\n{sfd.FileName}\n\nOpen containing folder?",
                "Export Complete", MessageBoxButtons.YesNo, MessageBoxIcon.Information);
            if (dlgResult == DialogResult.Yes)
                OpenFolderAndSelect(sfd.FileName);
        }
        catch (Exception ex)
        {
            _logger.LogError("XML export failed", "EXPORT", ex);
            MessageBox.Show($"Error during export: {ex.Message}", "Export Error",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    private void OnExportSelectedHl7()
    {
        if (_state.Hl7Messages.Count == 0)
        {
            MessageBox.Show("No HL7 file loaded.", "Export Selected", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }

        var indices = GetCheckedIndices();
        if (indices.Length == 0)
        {
            MessageBox.Show("Please select at least one message to export by checking the boxes in the first column.",
                "No Messages Selected", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }

        try
        {
            using var sfd = new SaveFileDialog
            {
                Filter = "HL7 Files (*.hl7)|*.hl7|All files (*.*)|*.*",
                Title = "Save Exported HL7 File"
            };
            if (!string.IsNullOrEmpty(_state.CurrentFilePath))
            {
                sfd.FileName = Path.GetFileNameWithoutExtension(_state.CurrentFilePath) + "_exported.hl7";
                sfd.InitialDirectory = Path.GetDirectoryName(_state.CurrentFilePath) ?? "";
            }

            if (sfd.ShowDialog(this) != DialogResult.OK) return;

            SetStatusText($"Exporting {indices.Length} message(s)...");
            Refresh();

            _exportService.ExportSelectedHl7(indices, _state.Hl7Messages, sfd.FileName);

            _logger.Log("INFO", $"Exported {indices.Length} message(s) to {Path.GetFileName(sfd.FileName)}", "EXPORT");
            SetStatusText($"Loaded: {Path.GetFileName(_state.CurrentFilePath)} (Messages: {_state.Hl7Messages.Count})");

            var dlgResult = MessageBox.Show(
                $"Successfully exported {indices.Length} message(s) to:\n{sfd.FileName}\n\nOpen containing folder?",
                "Export Complete", MessageBoxButtons.YesNo, MessageBoxIcon.Information);
            if (dlgResult == DialogResult.Yes)
                OpenFolderAndSelect(sfd.FileName);
        }
        catch (Exception ex)
        {
            _logger.LogError("HL7 export failed", "EXPORT", ex);
            MessageBox.Show($"Error during export: {ex.Message}", "Export Error",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    private void OnExportSelectedCsv()
    {
        if (_state.Tumors == null || _state.XmlDoc == null || _state.NsMgr == null)
        {
            MessageBox.Show("No XML file loaded.", "Export Selected", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }

        var indices = GetCheckedIndices();
        if (indices.Length == 0)
        {
            MessageBox.Show("Please select at least one tumor to export.", "No Tumors Selected",
                MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }

        RunCsvExport(indices, "selected");
    }

    private void OnExportAllCsv()
    {
        if (_state.Tumors == null || _state.XmlDoc == null || _state.NsMgr == null)
        {
            MessageBox.Show("No XML file loaded.", "Export All", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }

        var indices = Enumerable.Range(0, _state.Tumors.Count).ToArray();
        RunCsvExport(indices, "all");
    }

    private void RunCsvExport(int[] indices, string mode)
    {
        try
        {
            var defaultFields = _configService.GetDefaultFieldList();

            using var previewForm = new ExportPreviewForm(
                _naaccrDictionary,
                _configService,
                indices,
                _state.XmlDoc!,
                _state.NsMgr!,
                _state.Tumors,
                _configService.ConvertFieldListToXmlIds(defaultFields),
                $"Export {(mode == "all" ? "All" : "Selected")} as CSV - Configure Fields & Preview",
                _logger);

            if (previewForm.ShowDialog(this) != DialogResult.OK)
                return;

            var fieldIds = previewForm.SelectedFieldIds;
            var customFields = previewForm.CustomFields;

            if (fieldIds.Count == 0)
            {
                MessageBox.Show("No fields selected for export.", "Export Cancelled",
                    MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            // Convert to ExportField list
            var exportFields = fieldIds.Select(id => new ExportField
            {
                XmlId = id,
                IsCustom = customFields.ContainsKey(id),
                ParentElement = _naaccrDictionary.GetParentElement(id, customFields)
            }).ToList();

            using var sfd = new SaveFileDialog
            {
                Filter = "CSV Files (*.csv)|*.csv|All files (*.*)|*.*",
                Title = "Save Exported CSV File"
            };
            if (!string.IsNullOrEmpty(_state.CurrentFilePath))
            {
                var suffix = mode == "all" ? "_all_exported" : "_exported";
                sfd.FileName = Path.GetFileNameWithoutExtension(_state.CurrentFilePath) + suffix + ".csv";
                sfd.InitialDirectory = Path.GetDirectoryName(_state.CurrentFilePath) ?? "";
            }

            if (sfd.ShowDialog(this) != DialogResult.OK) return;

            SetStatusText($"Exporting {indices.Length} tumor(s) to CSV...");
            Refresh();

            if (mode == "all")
                _exportService.ExportAllCsv(_state.XmlDoc!, _state.NsMgr!, sfd.FileName, exportFields, customFields);
            else
                _exportService.ExportSelectedCsv(indices, _state.XmlDoc!, _state.NsMgr!, sfd.FileName, exportFields, customFields);

            _logger.Log("INFO", $"Exported {indices.Length} tumor(s) to CSV: {Path.GetFileName(sfd.FileName)}", "EXPORT");
            SetStatusText($"Loaded: {Path.GetFileName(_state.CurrentFilePath)} (Tumors: {_state.Tumors!.Count})");

            var dlgResult = MessageBox.Show(
                $"Successfully exported {indices.Length} tumor(s) to:\n{sfd.FileName}\n\nOpen containing folder?",
                "Export Complete", MessageBoxButtons.YesNo, MessageBoxIcon.Information);
            if (dlgResult == DialogResult.Yes)
                OpenFolderAndSelect(sfd.FileName);
        }
        catch (Exception ex)
        {
            _logger.LogError("CSV export failed", "EXPORT", ex);
            MessageBox.Show($"Error during export: {ex.Message}", "Export Error",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    private void OnExportAllXml()
    {
        if (_state.XmlDoc == null || string.IsNullOrEmpty(_state.CurrentFilePath))
        {
            MessageBox.Show("No XML file loaded.", "Export All", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }

        try
        {
            using var sfd = new SaveFileDialog
            {
                Filter = "NAACCR XML (*.xml)|*.xml|All files (*.*)|*.*",
                Title = "Save Full XML Document",
                FileName = Path.GetFileNameWithoutExtension(_state.CurrentFilePath) + "_copy.xml",
                InitialDirectory = Path.GetDirectoryName(_state.CurrentFilePath) ?? ""
            };

            if (sfd.ShowDialog(this) != DialogResult.OK) return;

            _state.XmlDoc.Save(sfd.FileName);

            _logger.Log("INFO", $"Exported full XML to {Path.GetFileName(sfd.FileName)}", "EXPORT");
            MessageBox.Show($"Full XML saved to:\n{sfd.FileName}",
                "Export Complete", MessageBoxButtons.OK, MessageBoxIcon.Information);
        }
        catch (Exception ex)
        {
            _logger.LogError("Export All XML failed", "EXPORT", ex);
            MessageBox.Show($"Error during export: {ex.Message}", "Export Error",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    private void OnExportAllHl7()
    {
        if (_state.Hl7Messages.Count == 0 || string.IsNullOrEmpty(_state.CurrentFilePath))
        {
            MessageBox.Show("No HL7 file loaded.", "Export All", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }

        try
        {
            using var sfd = new SaveFileDialog
            {
                Filter = "HL7 Files (*.hl7)|*.hl7|All files (*.*)|*.*",
                Title = "Save Full HL7 File",
                FileName = Path.GetFileNameWithoutExtension(_state.CurrentFilePath) + "_copy.hl7",
                InitialDirectory = Path.GetDirectoryName(_state.CurrentFilePath) ?? ""
            };

            if (sfd.ShowDialog(this) != DialogResult.OK) return;

            _hl7FileService.SaveHl7File(sfd.FileName, _state.Hl7Messages);

            _logger.Log("INFO", $"Exported full HL7 to {Path.GetFileName(sfd.FileName)}", "EXPORT");
            MessageBox.Show($"Full HL7 saved to:\n{sfd.FileName}",
                "Export Complete", MessageBoxButtons.OK, MessageBoxIcon.Information);
        }
        catch (Exception ex)
        {
            _logger.LogError("Export All HL7 failed", "EXPORT", ex);
            MessageBox.Show($"Error during export: {ex.Message}", "Export Error",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    private void OnExportSelectedHl7Csv()
    {
        if (_state.Hl7Messages.Count == 0)
        {
            MessageBox.Show("No HL7 file loaded.", "Export Selected", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }

        var indices = GetCheckedIndices();
        if (indices.Length == 0)
        {
            MessageBox.Show("Please select at least one message to export.", "No Messages Selected",
                MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }

        RunHl7CsvExport(indices, "selected");
    }

    private void OnExportAllHl7Csv()
    {
        if (_state.Hl7Messages.Count == 0)
        {
            MessageBox.Show("No HL7 file loaded.", "Export All", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }

        RunHl7CsvExport(null, "all");
    }

    private void RunHl7CsvExport(int[]? indices, string mode)
    {
        try
        {
            using var sfd = new SaveFileDialog
            {
                Filter = "CSV Files (*.csv)|*.csv|All files (*.*)|*.*",
                Title = "Save Exported CSV File"
            };
            if (!string.IsNullOrEmpty(_state.CurrentFilePath))
            {
                var suffix = mode == "all" ? "_all_exported" : "_exported";
                sfd.FileName = Path.GetFileNameWithoutExtension(_state.CurrentFilePath) + suffix + ".csv";
                sfd.InitialDirectory = Path.GetDirectoryName(_state.CurrentFilePath) ?? "";
            }

            if (sfd.ShowDialog(this) != DialogResult.OK) return;

            var count = indices?.Length ?? _state.Hl7Messages.Count;
            SetStatusText($"Exporting {count} message(s) to CSV...");
            Refresh();

            if (mode == "all")
                _exportService.ExportAllHl7Csv(_state.Hl7Messages, sfd.FileName);
            else
                _exportService.ExportSelectedHl7Csv(indices!, _state.Hl7Messages, sfd.FileName);

            _logger.Log("INFO", $"Exported {count} message(s) to CSV: {Path.GetFileName(sfd.FileName)}", "EXPORT");
            SetStatusText($"Loaded: {Path.GetFileName(_state.CurrentFilePath)} (Messages: {_state.Hl7Messages.Count})");

            var dlgResult = MessageBox.Show(
                $"Successfully exported {count} message(s) to:\n{sfd.FileName}\n\nOpen containing folder?",
                "Export Complete", MessageBoxButtons.YesNo, MessageBoxIcon.Information);
            if (dlgResult == DialogResult.Yes)
                OpenFolderAndSelect(sfd.FileName);
        }
        catch (Exception ex)
        {
            _logger.LogError("HL7 CSV export failed", "EXPORT", ex);
            MessageBox.Show($"Error during export: {ex.Message}", "Export Error",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    // =====================================================================
    //  TOOLS HANDLERS
    // =====================================================================

    /// <summary>NOAH Reportability — runs NOAH filter on current record.</summary>
    private void OnNoahReportability()
    {
        try
        {
            var config = _noahService.GetConfig();

            // Show model selection dialog
            using var modelForm = new NoahReportabilityForm(_noahService, config, NoahReportabilityForm.DialogMode.ModelSelection, _logger);
            if (modelForm.ShowDialog(this) != DialogResult.OK || modelForm.SelectedModel == null)
                return;

            var fileType = _state.FileType;
            int idx = _state.CurrentIndex;

            if (fileType == "hl7")
            {
                if (_state.Hl7Messages.Count == 0 || idx < 0 || idx >= _state.Hl7Messages.Count)
                {
                    MessageBox.Show("Select a message first.", "NOAH Reportability",
                        MessageBoxButtons.OK, MessageBoxIcon.Information);
                    return;
                }
            }
            else
            {
                if (_state.Tumors == null || _state.Tumors.Count == 0 || idx < 0 || idx >= _state.Tumors.Count)
                {
                    MessageBox.Show("Select a record first.", "NOAH Reportability",
                        MessageBoxButtons.OK, MessageBoxIcon.Information);
                    return;
                }
            }

            SetStatusText("NOAH reportability: running...");
            Refresh();

            // The actual NOAH API call would happen here through _noahService
            // For now, show info message
            MessageBox.Show("NOAH reportability filtering would execute here using the selected model.",
                "NOAH Reportability", MessageBoxButtons.OK, MessageBoxIcon.Information);
            SetStatusText($"Loaded: {Path.GetFileName(_state.CurrentFilePath)}");
        }
        catch (Exception ex)
        {
            _logger.LogError("NOAH reportability failed", "NOAH_API", ex);
            MessageBox.Show($"Error: {ex.Message}", "NOAH Reportability - Error",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
            SetStatusText("NOAH reportability: error");
        }
    }

    /// <summary>NOAH Custom Payload — tests custom text against NOAH.</summary>
    private void OnNoahCustomPayload()
    {
        try
        {
            var config = _noahService.GetConfig();
            using var payloadForm = new NoahReportabilityForm(_noahService, config, NoahReportabilityForm.DialogMode.CustomPayload, _logger);
            if (payloadForm.ShowDialog(this) != DialogResult.OK || string.IsNullOrEmpty(payloadForm.CustomPayloadText))
                return;

            // Show model selection
            using var modelForm = new NoahReportabilityForm(_noahService, config, NoahReportabilityForm.DialogMode.ModelSelection, _logger);
            if (modelForm.ShowDialog(this) != DialogResult.OK || modelForm.SelectedModel == null)
                return;

            SetStatusText("NOAH reportability: running custom payload...");
            Refresh();

            var minimalHl7 = _noahService.CreateMinimalHl7Message(payloadForm.CustomPayloadText);
            var result = _noahService.InvokeReportabilityApi(minimalHl7, config, modelForm.SelectedModel.Id);

            if (result.Success)
            {
                SetStatusText($"NOAH reportability: {result.Classification}");

                var reportsFolder = Path.Combine(result.WorkingFolder, "reports");
                var resultFiles = Directory.Exists(reportsFolder)
                    ? Directory.GetFiles(reportsFolder, "*.json")
                    : Array.Empty<string>();

                if (resultFiles.Length > 0)
                {
                    using var resultsForm = new NoahResultsForm(
                        resultFiles[0], result.WorkingFolder, "Custom", 0, 1, _logger);
                    resultsForm.ShowDialog(this);
                }
                else
                {
                    MessageBox.Show($"Result: {result.Classification.ToUpperInvariant()}",
                        "NOAH Reportability", MessageBoxButtons.OK, MessageBoxIcon.Information);
                }
            }
            else
            {
                MessageBox.Show($"NOAH filter error.\n\nWorking folder:\n{result.WorkingFolder}",
                    "NOAH Reportability - Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
                SetStatusText("NOAH reportability: error");
            }
        }
        catch (Exception ex)
        {
            _logger.LogError("NOAH custom payload failed", "NOAH_API", ex);
            MessageBox.Show($"Error: {ex.Message}", "NOAH Reportability - Error",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    /// <summary>Test Site/Laterality on current record.</summary>
    private void OnTestSiteLatCurrent()
    {
        try
        {
            var fileType = _state.FileType;
            if (fileType != "xml" && fileType != "hl7")
            {
                MessageBox.Show("No file loaded. This feature works with NAACCR XML or HL7 files.",
                    "Test Site/Laterality", MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }

            int idx = _state.CurrentIndex;
            if (idx < 0 || idx >= _state.RecordCount)
            {
                MessageBox.Show("Select a record first.", "Test Site/Laterality",
                    MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }

            SetStatusText("Testing site/laterality on current record...");
            Refresh();

            SiteLateralityTestResult result;
            string? sourceText = null;
            string[]? obxSegments = null;
            string[]? skipCodes = null;

            if (fileType == "xml")
            {
                var tumor = _state.Tumors![idx]!;
                var nsMgr = _state.NsMgr!;

                var patient = tumor.SelectSingleNode("ancestor::n:Patient[1]", nsMgr);
                string nameLast = patient?.SelectSingleNode("./n:Item[@naaccrId='nameLast']", nsMgr)?.InnerText ?? "";
                string nameFirst = patient?.SelectSingleNode("./n:Item[@naaccrId='nameFirst']", nsMgr)?.InnerText ?? "";
                string sourceInfo = $"Tumor {idx + 1}";
                string patientLabel = $"{nameLast}, {nameFirst}".Trim(',', ' ');
                if (!string.IsNullOrWhiteSpace(patientLabel))
                    sourceInfo += $" — {patientLabel}";

                string textPath = tumor.SelectSingleNode("./n:Item[@naaccrId='textDxProcPath']", nsMgr)?.InnerText ?? "";
                string textPe = tumor.SelectSingleNode("./n:Item[@naaccrId='textDxProcPe']", nsMgr)?.InnerText ?? "";
                string textLab = tumor.SelectSingleNode("./n:Item[@naaccrId='textDxProcLabTests']", nsMgr)?.InnerText ?? "";

                string textCombined = (textPath + " " + textPe).Trim();
                if (string.IsNullOrWhiteSpace(textCombined))
                    textCombined = textLab.Trim();

                if (string.IsNullOrWhiteSpace(textCombined))
                {
                    MessageBox.Show("No pathology text found in this record (textDxProcPath, textDxProcPe, textDxProcLabTests are all empty).",
                        "Test Site/Laterality", MessageBoxButtons.OK, MessageBoxIcon.Information);
                    SetStatusText($"Loaded: {Path.GetFileName(_state.CurrentFilePath)}");
                    return;
                }

                var parts = new List<string>();
                if (!string.IsNullOrWhiteSpace(textPath)) parts.Add($"textDxProcPath:\n{textPath}");
                if (!string.IsNullOrWhiteSpace(textPe)) parts.Add($"textDxProcPe:\n{textPe}");
                if (!string.IsNullOrWhiteSpace(textLab)) parts.Add($"textDxProcLabTests:\n{textLab}");
                sourceText = string.Join("\n\n", parts);

                result = RunSiteLateralityTest(textCombined, sourceInfo);
            }
            else // hl7
            {
                var message = _state.Hl7Messages[idx];
                string sourceInfo = $"Message {idx + 1}";
                if (!string.IsNullOrWhiteSpace(message.PatientName))
                    sourceInfo += $" — {message.PatientName}";

                if (!message.Segments.TryGetValue("OBX", out var rawObxList) || rawObxList.Count == 0)
                {
                    MessageBox.Show("No OBX segments found in this message.",
                        "Test Site/Laterality", MessageBoxButtons.OK, MessageBoxIcon.Information);
                    SetStatusText($"Loaded: {Path.GetFileName(_state.CurrentFilePath)}");
                    return;
                }

                obxSegments = rawObxList.ToArray();
                var skipConfig = _configService.GetObxSkipConfig();
                skipCodes = skipConfig.SkipCodes.ToArray();

                var skipCodesUpper = new HashSet<string>(
                    skipCodes.Select(c => c.ToUpperInvariant()),
                    StringComparer.OrdinalIgnoreCase);

                var textParts = new List<string>();
                foreach (var obx in obxSegments)
                {
                    var fields = obx.Split('|');
                    string obx3Code = (fields.Length > 3 ? fields[3].Split('^')[0] : "").Trim().ToUpperInvariant();
                    if (skipCodesUpper.Contains(obx3Code)) continue;

                    string obx5 = fields.Length > 5 ? fields[5] : "";
                    if (!string.IsNullOrWhiteSpace(obx5))
                        textParts.Add(Hl7EscapeHelper.Unescape(obx5));
                }

                if (textParts.Count == 0)
                {
                    MessageBox.Show("No text content found in OBX segments (after applying skip codes).",
                        "Test Site/Laterality", MessageBoxButtons.OK, MessageBoxIcon.Information);
                    SetStatusText($"Loaded: {Path.GetFileName(_state.CurrentFilePath)}");
                    return;
                }

                result = RunSiteLateralityTest(string.Join("\r\n", textParts), sourceInfo);
            }

            SetStatusText($"Loaded: {Path.GetFileName(_state.CurrentFilePath)}");
            using var resultsForm = new TestSiteLateralityForm(result, sourceText, obxSegments, skipCodes);
            resultsForm.ShowDialog(this);
        }
        catch (Exception ex)
        {
            _logger.LogError("Site/Laterality test failed", "TEST_HEURISTICS", ex);
            MessageBox.Show($"Error testing heuristics: {ex.Message}",
                "Test Site/Laterality - Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    /// <summary>Test Site/Laterality on custom text.</summary>
    private void OnTestSiteLatCustom()
    {
        try
        {
            using var inputForm = new TestSiteLateralityForm();
            if (inputForm.ShowDialog(this) != DialogResult.OK || string.IsNullOrEmpty(inputForm.InputText))
                return;

            SetStatusText("Testing site/laterality heuristics...");
            Refresh();

            string text = inputForm.InputText;
            var result = RunSiteLateralityTest(text, "Custom text");

            SetStatusText("Site/Lat test complete");
            using var resultsForm = new TestSiteLateralityForm(result, text);
            resultsForm.ShowDialog(this);
        }
        catch (Exception ex)
        {
            _logger.LogError("Site/Laterality test (custom) failed", "TEST_HEURISTICS", ex);
            MessageBox.Show($"Error testing heuristics: {ex.Message}",
                "Test Site/Laterality - Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    /// <summary>Runs site/laterality heuristics against the given text and returns test results.</summary>
    private SiteLateralityTestResult RunSiteLateralityTest(string text, string sourceInfo)
    {
        string topoPath = PathHelper.GetDictionaryPath("Topography.jsonl");
        string melTopoPath = PathHelper.GetDictionaryPath("TopographyMelanoma.jsonl");
        string latPath = PathHelper.GetDictionaryPath("Laterality.json");
        string rulesPath = PathHelper.GetDictionaryPath("SiteCodingRules.jsonl");

        var topoMap = File.Exists(topoPath)
            ? _siteLateralityService.ReadTopographyJson(topoPath)
                .Where(t => !string.IsNullOrEmpty(t.Code) && !string.IsNullOrEmpty(t.SearchPhrase) && !t.Code.StartsWith("C77"))
                .ToList()
            : new List<TopographyEntry>();

        var melTopoMap = File.Exists(melTopoPath)
            ? _siteLateralityService.ReadTopographyJson(melTopoPath)
            : new List<TopographyEntry>();

        var latCodes = File.Exists(latPath)
            ? _siteLateralityService.ReadLateralityJson(latPath)
            : new Dictionary<string, bool>();

        var rules = File.Exists(rulesPath)
            ? _siteLateralityService.ReadSiteCodingRules(rulesPath)
            : new List<SiteCodingRule>();

        string low = text.ToLowerInvariant();
        string siteCode = "";
        string matchType = "";
        string matchedPhrase = "";
        int? patternPriority = null;
        SiteCodingRule? matchedRule = null;

        foreach (var rule in rules)
        {
            var testResult = _siteLateralityService.TestSiteCodingRule(rule, low, topoMap);
            if (testResult.Matched)
            {
                string code = testResult.TopoCode ?? (rule.Code != "{topo}" ? rule.Code : "");
                if (!string.IsNullOrEmpty(code))
                {
                    siteCode = code;
                    matchType = "site-coding-rule";
                    matchedPhrase = testResult.MatchedTerm ?? "";
                    patternPriority = rule.Priority;
                    matchedRule = rule;
                    break;
                }
            }
        }

        if (string.IsNullOrEmpty(siteCode) && low.Contains("melanoma") && melTopoMap.Count > 0)
        {
            var (code, phrase) = FindBestDictMatch(melTopoMap, low);
            if (!string.IsNullOrEmpty(code))
            {
                siteCode = code;
                matchType = "melanoma-dict";
                matchedPhrase = phrase;
            }
        }

        if (string.IsNullOrEmpty(siteCode) && topoMap.Count > 0)
        {
            var (code, phrase) = FindBestDictMatch(topoMap, low);
            if (!string.IsNullOrEmpty(code))
            {
                siteCode = code;
                matchType = "standard-dict";
                matchedPhrase = phrase;
            }
        }

        string? latCode = null;
        string latDesc = "";
        bool siteRequiresLat = false;

        if (!string.IsNullOrEmpty(siteCode))
        {
            siteRequiresLat = latCodes.ContainsKey(siteCode);

            if (matchedRule?.ForceLaterality != null)
                latCode = matchedRule.ForceLaterality;
            else if (siteRequiresLat)
                latCode = _siteLateralityService.GetLaterality(low) ?? "9";
            else
                latCode = "0";

            latDesc = latCode switch
            {
                "0" => "Not a paired site",
                "1" => "Right",
                "2" => "Left",
                "9" => "Bilateral or unknown laterality",
                _ => latCode
            };
        }

        return new SiteLateralityTestResult
        {
            SourceInfo = sourceInfo,
            SiteCode = string.IsNullOrEmpty(siteCode) ? null : siteCode,
            MatchType = string.IsNullOrEmpty(matchType) ? null : matchType,
            PatternPriority = patternPriority,
            MatchedPhrase = string.IsNullOrEmpty(matchedPhrase) ? null : matchedPhrase,
            LateralityCode = latCode,
            LateralityDescription = string.IsNullOrEmpty(latDesc) ? null : latDesc,
            SiteRequiresLaterality = siteRequiresLat
        };
    }

    /// <summary>Finds the topography entry whose search phrase occurs earliest in the text.</summary>
    private static (string Code, string Phrase) FindBestDictMatch(List<TopographyEntry> map, string textLow)
    {
        string bestCode = "";
        string bestPhrase = "";
        int bestPos = 0;

        foreach (var entry in map)
        {
            if (string.IsNullOrEmpty(entry.SearchPhrase)) continue;
            string escaped = Regex.Escape(entry.SearchPhrase);
            var match = Regex.Match(textLow, $"(?<![a-zA-Z]){escaped}(?![a-zA-Z])");
            if (match.Success)
            {
                int pos = match.Index + 1;
                if (bestPos == 0 || pos < bestPos)
                {
                    bestPos = pos;
                    bestCode = entry.Code;
                    bestPhrase = entry.SearchPhrase;
                }
            }
        }

        return (bestCode, bestPhrase);
    }

    /// <summary>Split File — opens SplitFileForm.</summary>
    private void OnSplitFile()
    {
        try
        {
            // Open file dialog if no file loaded
            using var ofd = new OpenFileDialog
            {
                Filter = "NAACCR XML (*.xml)|*.xml|HL7 Files (*.hl7)|*.hl7|All files (*.*)|*.*",
                Title = "Select File to Split"
            };

            if (ofd.ShowDialog(this) != DialogResult.OK) return;

            var filePath = ofd.FileName;
            var ext = Path.GetExtension(filePath).ToLowerInvariant();
            var fileType = ext == ".hl7" ? "hl7" : "xml";

            SetStatusText("Scanning file for split...");
            Refresh();

            Dictionary<string, object> scanResult;
            if (fileType == "hl7")
                scanResult = _splitFileService.GetHl7FileSplitInfo(filePath);
            else
                scanResult = _splitFileService.GetXmlFileSplitInfo(filePath);

            var lastNames = scanResult.TryGetValue("LastNames", out var ln) && ln is List<string> names
                ? names : new List<string>();
            var totalRecords = scanResult.TryGetValue("TotalRecords", out var tr) && tr is int total
                ? total : 0;

            SetStatusText($"Loaded: {Path.GetFileName(_state.CurrentFilePath)}");

            using var splitForm = new SplitFileForm(_splitFileService, filePath, totalRecords, lastNames, fileType);
            if (splitForm.ShowDialog(this) != DialogResult.OK) return;

            SetStatusText("Splitting file...");
            Refresh();

            if (fileType == "hl7")
                _splitFileService.SplitHl7File(scanResult, filePath, splitForm.SplitCount, splitForm.OutputDirectory);
            else
                _splitFileService.SplitXmlFile(scanResult, filePath, splitForm.SplitCount, splitForm.OutputDirectory);

            _logger.Log("INFO", $"Split {Path.GetFileName(filePath)} into {splitForm.SplitCount} files", "SPLIT");
            SetStatusText($"Split complete: {splitForm.SplitCount} files created");

            MessageBox.Show($"File split into {splitForm.SplitCount} parts.\n\nOutput folder:\n{splitForm.OutputDirectory}",
                "Split Complete", MessageBoxButtons.OK, MessageBoxIcon.Information);
        }
        catch (Exception ex)
        {
            _logger.LogError("Split file failed", "SPLIT", ex);
            MessageBox.Show($"Error during file split: {ex.Message}", "Error",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    /// <summary>Concatenate XML — opens file picker then ConcatenateXmlForm.</summary>
    private void OnConcatenateXml()
    {
        try
        {
            using var ofd = new OpenFileDialog
            {
                Filter = "NAACCR XML (*.xml)|*.xml|All files (*.*)|*.*",
                Title = "Select XML files to concatenate",
                Multiselect = true
            };

            if (ofd.ShowDialog(this) != DialogResult.OK || ofd.FileNames.Length == 0) return;

            using var form = new ConcatenateXmlForm(_concatenateService, ofd.FileNames, _logger);
            form.ShowDialog(this);

            if (form.ShouldOpenOutput && !string.IsNullOrEmpty(form.OutputFilePath))
                _fileHandlers.OpenFile(form.OutputFilePath, this);
        }
        catch (Exception ex)
        {
            _logger.LogError("Concatenate XML failed", "CONCATENATE", ex);
            MessageBox.Show($"Error: {ex.Message}", "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    /// <summary>Concatenate HL7.</summary>
    private void OnConcatenateHl7()
    {
        try
        {
            using var ofd = new OpenFileDialog
            {
                Filter = "HL7 Files (*.hl7)|*.hl7|All files (*.*)|*.*",
                Title = "Select HL7 files to concatenate",
                Multiselect = true
            };

            if (ofd.ShowDialog(this) != DialogResult.OK || ofd.FileNames.Length == 0) return;

            using var form = new ConcatenateHl7Form(_concatenateService, ofd.FileNames, _logger);
            form.ShowDialog(this);

            if (form.ShouldOpenOutput && !string.IsNullOrEmpty(form.OutputFilePath))
                _fileHandlers.OpenFile(form.OutputFilePath, this);
        }
        catch (Exception ex)
        {
            _logger.LogError("Concatenate HL7 failed", "CONCATENATE", ex);
            MessageBox.Show($"Error: {ex.Message}", "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    /// <summary>Concatenate TXT.</summary>
    private void OnConcatenateTxt()
    {
        try
        {
            using var ofd = new OpenFileDialog
            {
                Filter = "Text Files (*.txt)|*.txt|All files (*.*)|*.*",
                Title = "Select TXT files to concatenate",
                Multiselect = true
            };

            if (ofd.ShowDialog(this) != DialogResult.OK || ofd.FileNames.Length == 0) return;

            using var form = new ConcatenateTxtForm(_concatenateService, ofd.FileNames, _logger);
            form.ShowDialog(this);

            if (form.ShouldOpenOutput && !string.IsNullOrEmpty(form.OutputFilePath))
                _fileHandlers.OpenFile(form.OutputFilePath, this);
        }
        catch (Exception ex)
        {
            _logger.LogError("Concatenate TXT failed", "CONCATENATE", ex);
            MessageBox.Show($"Error: {ex.Message}", "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    // =====================================================================
    //  SETTINGS HANDLERS
    // =====================================================================

    /// <summary>Manage Coding Tables — populates dropdown dynamically.</summary>
    private void OnManageTablesDropDownOpening(object? sender, EventArgs e)
    {
        var mnu = _menuBuilder.MnuManageCodingTables;
        mnu.DropDownItems.Clear();

        var lateralityPath = PathHelper.GetDictionaryPath("Laterality.json");
        var topographyPath = PathHelper.GetDictionaryPath("Topography.jsonl");
        var skinTopoPath = PathHelper.GetDictionaryPath("TopographyMelanoma.jsonl");
        var siteCodingRulesPath = PathHelper.GetDictionaryPath("SiteCodingRules.jsonl");

        var mnuLat = new ToolStripMenuItem("Laterality");
        mnuLat.Click += (s, ev) =>
        {
            using var form = new CodingTableEditorForm(_siteLateralityService, lateralityPath, "laterality", "Laterality", _logger);
            form.ShowDialog(this);
        };
        mnu.DropDownItems.Add(mnuLat);

        var mnuTopo = new ToolStripMenuItem("Topography");
        mnuTopo.Click += (s, ev) =>
        {
            using var form = new CodingTableEditorForm(_siteLateralityService, topographyPath, "topography", "Topography", _logger);
            form.ShowDialog(this);
        };
        mnu.DropDownItems.Add(mnuTopo);

        var mnuSkinTopo = new ToolStripMenuItem("Skin Topography");
        mnuSkinTopo.Click += (s, ev) =>
        {
            using var form = new CodingTableEditorForm(_siteLateralityService, skinTopoPath, "topography", "Skin Topography", _logger);
            form.ShowDialog(this);
        };
        mnu.DropDownItems.Add(mnuSkinTopo);

        mnu.DropDownItems.Add(new ToolStripSeparator());

        var mnuSiteCodingRules = new ToolStripMenuItem("Site Coding Rules");
        mnuSiteCodingRules.Click += (s, ev) =>
        {
            using var form = new SiteCodingRulesEditorForm(_siteLateralityService, siteCodingRulesPath, _logger);
            form.ShowDialog(this);
        };
        mnu.DropDownItems.Add(mnuSiteCodingRules);
    }

    /// <summary>NOAH Config — opens NOAH settings dialog.</summary>
    private void OnNoahConfig()
    {
        try
        {
            var config = _noahService.GetConfig();
            using var form = new NoahReportabilityForm(_noahService, config, NoahReportabilityForm.DialogMode.Settings, _logger);
            form.ShowDialog(this);
        }
        catch (Exception ex)
        {
            _logger.LogError("NOAH config failed", "SETTINGS", ex);
            MessageBox.Show($"Error opening NOAH settings: {ex.Message}", "Error",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    /// <summary>OBX Skip Codes — opens skip code config dialog.</summary>
    private void OnObxSkipCodes()
    {
        try
        {
            using var form = new ObxSkipConfigForm(_configService);
            form.ShowDialog(this);
        }
        catch (Exception ex)
        {
            _logger.LogError("OBX skip codes config failed", "SETTINGS", ex);
            MessageBox.Show($"Error opening OBX skip codes: {ex.Message}", "Error",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    private void OnGridColumns()
    {
        try
        {
            if (_state.FileType == "hl7")
            {
                MessageBox.Show("Grid column customization is only available for XML files.\nHL7 columns are fixed.",
                    "Grid Columns", MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }

            using var dialog = new GridColumnsDialog(
                _fileHandlers.GridSettingsService,
                _naaccrDictionary);

            if (dialog.ShowDialog(this) == DialogResult.OK && dialog.SettingsChanged
                && !string.IsNullOrEmpty(_state.CurrentFilePath))
            {
                _fileHandlers.OpenFile(_state.CurrentFilePath, this);
            }
        }
        catch (Exception ex)
        {
            _logger.LogError("Grid columns config failed", "SETTINGS", ex);
            MessageBox.Show($"Error opening grid columns: {ex.Message}", "Error",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    // =====================================================================
    //  HELP HANDLERS
    // =====================================================================

    /// <summary>User Manual — opens the PDF from docs/ directory.</summary>
    private void OnUserManual()
    {
        try
        {
            var docsDir = Path.Combine(PathHelper.RepoRoot, "docs");
            var pdfFiles = Directory.Exists(docsDir)
                ? Directory.GetFiles(docsDir, "*.pdf")
                : Array.Empty<string>();

            if (pdfFiles.Length > 0)
            {
                Process.Start(new ProcessStartInfo(pdfFiles[0]) { UseShellExecute = true });
            }
            else
            {
                MessageBox.Show("User manual PDF not found in the docs/ directory.",
                    "User Manual", MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
        }
        catch (Exception ex)
        {
            _logger.LogError("Failed to open user manual", "HELP", ex);
            MessageBox.Show($"Error opening user manual: {ex.Message}", "Error",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    /// <summary>Open Logs Folder — opens the logs directory in the system file manager.</summary>
    private void OnOpenLogsFolder()
    {
        try
        {
            var logsDir = PathHelper.LogsDir;
            PathHelper.EnsureDirectoryExists(logsDir);
            Process.Start(new ProcessStartInfo(logsDir) { UseShellExecute = true });
        }
        catch (Exception ex)
        {
            _logger.LogError("Failed to open logs folder", "FILE_OPEN", ex);
            MessageBox.Show($"Error opening logs folder: {ex.Message}", "Error",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    // =====================================================================
    //  HELPER METHODS
    // =====================================================================

    /// <summary>Opens the containing folder and selects the specified file.</summary>
    private void OpenFolderAndSelect(string filePath)
    {
        try
        {
            if (OperatingSystem.IsWindows())
            {
                Process.Start("explorer.exe", $"/select,\"{filePath}\"");
            }
            else if (OperatingSystem.IsMacOS())
            {
                Process.Start("open", $"-R \"{filePath}\"");
            }
            else
            {
                var dir = Path.GetDirectoryName(filePath);
                if (dir != null)
                    Process.Start(new ProcessStartInfo(dir) { UseShellExecute = true });
            }
        }
        catch (Exception ex)
        {
            // Non-critical: folder open is a convenience feature
            _logger.Log("WARN", $"Failed to open folder for file: {ex.Message}", "FILE_OPEN");
        }
    }

    /// <summary>Shows a simple variable selection dialog and returns selected NAACCR IDs.</summary>
    private static string[]? ShowVariableSelectionDialog(List<string> variables)
    {
        using var dlg = new Form
        {
            Text = "Select Variables to Remove",
            Width = 500,
            Height = 500,
            StartPosition = FormStartPosition.CenterParent,
            FormBorderStyle = FormBorderStyle.Sizable,
            MinimumSize = new System.Drawing.Size(400, 300)
        };

        var lst = new CheckedListBox
        {
            Location = new System.Drawing.Point(10, 10),
            Size = new System.Drawing.Size(460, 400),
            Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right | AnchorStyles.Bottom,
            CheckOnClick = true
        };

        foreach (var v in variables)
            lst.Items.Add(v);

        var btnOk = new Button
        {
            Text = "Remove",
            Location = new System.Drawing.Point(300, 420),
            Anchor = AnchorStyles.Bottom | AnchorStyles.Right,
            DialogResult = DialogResult.OK
        };

        var btnCancel = new Button
        {
            Text = "Cancel",
            Location = new System.Drawing.Point(390, 420),
            Anchor = AnchorStyles.Bottom | AnchorStyles.Right,
            DialogResult = DialogResult.Cancel
        };

        dlg.Controls.AddRange(new Control[] { lst, btnOk, btnCancel });
        dlg.AcceptButton = btnOk;
        dlg.CancelButton = btnCancel;

        if (dlg.ShowDialog() != DialogResult.OK) return null;

        var selected = new List<string>();
        foreach (var item in lst.CheckedItems)
            selected.Add(item.ToString()!);

        return selected.Count > 0 ? selected.ToArray() : null;
    }
}
