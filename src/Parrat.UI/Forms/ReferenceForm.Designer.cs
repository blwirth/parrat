using System.Drawing;
using System.Windows.Forms;

namespace Parrat.UI.Forms;

partial class ReferenceForm
{
    private System.ComponentModel.IContainer components = null;

    protected override void Dispose(bool disposing)
    {
        if (disposing && (components != null))
        {
            components.Dispose();
        }
        base.Dispose(disposing);
    }

    private void InitializeComponent()
    {
        components = new System.ComponentModel.Container();

        // ── StatusStrip ──────────────────────────────────────────────────
        _statusStrip = new StatusStrip();
        _lblStatus = new ToolStripStatusLabel();
        _lblFileName = new ToolStripStatusLabel();

        _statusStrip.Dock = DockStyle.Bottom;
        _statusStrip.SuspendLayout();

        _lblStatus.Text = "No reference file loaded";
        _lblStatus.Spring = true;
        _lblStatus.TextAlign = ContentAlignment.MiddleLeft;

        _lblFileName.Text = "";
        _lblFileName.BorderSides = ToolStripStatusLabelBorderSides.Left;

        _statusStrip.Items.AddRange(new ToolStripItem[] { _lblStatus, _lblFileName });
        _statusStrip.ResumeLayout(false);
        _statusStrip.PerformLayout();

        // ── Main content panel ───────────────────────────────────────────
        _mainPanel = new Panel();
        _mainPanel.Dock = DockStyle.Fill;
        _mainPanel.Padding = new Padding(10, 10, 10, 0);

        // ── Outer split container: grid (left) | content (right) ─────────
        _splitOuter = new SplitContainer();
        _splitOuter.Dock = DockStyle.Fill;
        _splitOuter.Orientation = Orientation.Vertical;
        _splitOuter.IsSplitterFixed = false;
        _splitOuter.Panel1MinSize = 200;

        // ── Inner split container: path text (left) | items (right) ──────
        _splitInner = new SplitContainer();
        _splitInner.Dock = DockStyle.Fill;
        _splitInner.Orientation = Orientation.Vertical;
        _splitInner.IsSplitterFixed = false;
        _splitInner.Panel1MinSize = 200;

        // ── DataGridView (left panel — fully read-only, no checkboxes) ───
        _gridNav = new DataGridView();
        _gridNav.Dock = DockStyle.Fill;
        _gridNav.AllowUserToAddRows = false;
        _gridNav.AllowUserToDeleteRows = false;
        _gridNav.RowHeadersVisible = false;
        _gridNav.ReadOnly = true;
        _gridNav.MultiSelect = false;
        _gridNav.SelectionMode = DataGridViewSelectionMode.FullRowSelect;

        // ── Search panel (docked above grid) ─────────────────────────────
        _pnlSearch = new Panel();
        _pnlSearch.Dock = DockStyle.Top;
        _pnlSearch.Height = 30;
        _pnlSearch.Visible = false;

        _txtSearch = new TextBox();
        _txtSearch.Dock = DockStyle.Fill;
        _txtSearch.Font = new Font("Segoe UI", 9f);

        _lblSearchCount = new Label();
        _lblSearchCount.Dock = DockStyle.Right;
        _lblSearchCount.Width = 70;
        _lblSearchCount.TextAlign = ContentAlignment.MiddleCenter;
        _lblSearchCount.ForeColor = Color.Gray;
        _lblSearchCount.Text = "";

        _btnClearSearch = new Button();
        _btnClearSearch.Dock = DockStyle.Right;
        _btnClearSearch.Width = 25;
        _btnClearSearch.FlatStyle = FlatStyle.Flat;
        _btnClearSearch.FlatAppearance.BorderSize = 0;
        _btnClearSearch.Text = "\u2715";
        _btnClearSearch.Font = new Font("Segoe UI", 8f);

        _pnlSearch.Controls.Add(_txtSearch);
        _pnlSearch.Controls.Add(_lblSearchCount);
        _pnlSearch.Controls.Add(_btnClearSearch);

        // ── Auto-sync checkbox (above match status) ─────────────────────
        _chkAutoSync = new CheckBox();
        _chkAutoSync.Text = "Auto-sync";
        _chkAutoSync.Dock = DockStyle.Top;
        _chkAutoSync.Height = 22;
        _chkAutoSync.Font = new Font("Segoe UI", 8f);
        _chkAutoSync.Padding = new Padding(2, 0, 0, 0);
        _chkAutoSync.Checked = false;

        // ── Match status label (above search, shows Find in Reference results) ──
        _lblMatchStatus = new Label();
        _lblMatchStatus.Dock = DockStyle.Top;
        _lblMatchStatus.Height = 24;
        _lblMatchStatus.TextAlign = ContentAlignment.MiddleLeft;
        _lblMatchStatus.Font = new Font("Segoe UI", 9f, FontStyle.Italic);
        _lblMatchStatus.ForeColor = Color.DarkSlateGray;
        _lblMatchStatus.Padding = new Padding(4, 0, 0, 0);
        _lblMatchStatus.Text = "";
        _lblMatchStatus.Visible = false;

        // ── RichTextBox — path/text panel (middle) ───────────────────────
        _rtbPath = new RichTextBox();
        _rtbPath.Multiline = true;
        _rtbPath.ScrollBars = RichTextBoxScrollBars.Both;
        _rtbPath.WordWrap = true;
        _rtbPath.ReadOnly = true;
        _rtbPath.Font = new Font("Consolas", 10f);
        _rtbPath.Dock = DockStyle.Fill;

        // ── RichTextBox — items panel (right) ────────────────────────────
        _rtbItems = new RichTextBox();
        _rtbItems.Multiline = true;
        _rtbItems.ScrollBars = RichTextBoxScrollBars.Both;
        _rtbItems.WordWrap = true;
        _rtbItems.ReadOnly = true;
        _rtbItems.Font = new Font("Consolas", 9f);
        _rtbItems.Dock = DockStyle.Fill;

        // ── Bottom navigation panel ──────────────────────────────────────
        _bottomPanel = new Panel();
        _bottomPanel.Dock = DockStyle.Bottom;
        _bottomPanel.Height = 40;
        _bottomPanel.Padding = new Padding(10, 5, 10, 5);

        _btnPrev = new Button();
        _btnPrev.Text = "<";
        _btnPrev.Width = 32;
        _btnPrev.Height = 24;
        _btnPrev.Location = new Point(10, 5);
        _btnPrev.Enabled = false;
        _btnPrev.Anchor = AnchorStyles.Left | AnchorStyles.Bottom;

        _btnNext = new Button();
        _btnNext.Text = ">";
        _btnNext.Width = 32;
        _btnNext.Height = 24;
        _btnNext.Location = new Point(50, 5);
        _btnNext.Enabled = false;
        _btnNext.Anchor = AnchorStyles.Left | AnchorStyles.Bottom;

        _lblIndex = new Label();
        _lblIndex.AutoSize = true;
        _lblIndex.Location = new Point(90, 8);
        _lblIndex.Text = "";
        _lblIndex.Anchor = AnchorStyles.Left | AnchorStyles.Bottom;

        // ── Copy buttons (right-aligned in bottom panel) ────────────────
        _pnlCopyBar = new FlowLayoutPanel();
        _pnlCopyBar.Dock = DockStyle.Right;
        _pnlCopyBar.AutoSize = true;
        _pnlCopyBar.AutoSizeMode = AutoSizeMode.GrowAndShrink;
        _pnlCopyBar.WrapContents = false;
        _pnlCopyBar.FlowDirection = FlowDirection.RightToLeft;
        _pnlCopyBar.Padding = new Padding(0);
        _pnlCopyBar.Visible = false;

        _btnCopyFields = new Button[4];
        var copyLabels = new[] { "Last", "First", "DOB", "Path#" };
        for (int i = 0; i < 4; i++)
        {
            var btn = new Button();
            btn.AutoSize = true;
            btn.AutoSizeMode = AutoSizeMode.GrowAndShrink;
            btn.FlatStyle = FlatStyle.Flat;
            btn.FlatAppearance.BorderColor = Color.Silver;
            btn.FlatAppearance.BorderSize = 1;
            btn.Font = new Font("Segoe UI", 8f);
            btn.Padding = new Padding(2, 0, 2, 0);
            btn.Margin = new Padding(2, 5, 2, 5);
            btn.Cursor = Cursors.Hand;
            btn.Text = copyLabels[i];
            btn.Visible = false;
            btn.Tag = "";
            _btnCopyFields[i] = btn;
        }
        for (int i = _btnCopyFields.Length - 1; i >= 0; i--)
            _pnlCopyBar.Controls.Add(_btnCopyFields[i]);

        _bottomPanel.Controls.AddRange(new Control[] { _btnPrev, _btnNext, _lblIndex, _pnlCopyBar });

        // ── Wire panels into split containers ────────────────────────────
        _splitOuter.Panel1.Controls.Add(_gridNav);
        _splitOuter.Panel1.Controls.Add(_pnlSearch);
        _splitOuter.Panel1.Controls.Add(_lblMatchStatus);
        _splitOuter.Panel1.Controls.Add(_chkAutoSync);
        _splitInner.Panel1.Controls.Add(_rtbPath);
        _splitInner.Panel2.Controls.Add(_rtbItems);
        _splitOuter.Panel2.Controls.Add(_splitInner);

        _mainPanel.Controls.Add(_splitOuter);

        // ── Add all to form ──────────────────────────────────────────────
        Controls.AddRange(new Control[]
        {
            _mainPanel,
            _bottomPanel,
            _statusStrip
        });

        // ── Form properties ──────────────────────────────────────────────
        Text = "PARRAT Reference";
        StartPosition = FormStartPosition.CenterScreen;
        Width = 1400;
        Height = 900;
        KeyPreview = true;
    }

    // ── Control fields ───────────────────────────────────────────────────

    private StatusStrip _statusStrip = null!;
    private ToolStripStatusLabel _lblStatus = null!;
    private ToolStripStatusLabel _lblFileName = null!;
    private Panel _mainPanel = null!;
    private SplitContainer _splitOuter = null!;
    private SplitContainer _splitInner = null!;
    private DataGridView _gridNav = null!;
    private Panel _pnlSearch = null!;
    private TextBox _txtSearch = null!;
    private Label _lblSearchCount = null!;
    private Button _btnClearSearch = null!;
    private Label _lblMatchStatus = null!;
    private CheckBox _chkAutoSync = null!;
    private RichTextBox _rtbPath = null!;
    private RichTextBox _rtbItems = null!;
    private FlowLayoutPanel _pnlCopyBar = null!;
    private Button[] _btnCopyFields = null!;
    private Panel _bottomPanel = null!;
    private Button _btnPrev = null!;
    private Button _btnNext = null!;
    private Label _lblIndex = null!;
}
