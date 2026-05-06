using System.Drawing;
using System.Windows.Forms;

namespace Parrat.UI.Forms;

/// <summary>
/// Base form that applies the PARRAT application icon to all windows
/// and handles DPI-aware scaling so the UI renders correctly on
/// high-DPI displays (e.g. 4K monitors at 200% scaling).
/// </summary>
public class ParratFormBase : Form
{
    private static Icon? _appIcon;
    private bool _hasScaled;

    protected ParratFormBase()
    {
        AutoScaleMode = AutoScaleMode.None;

        _appIcon ??= Icon.ExtractAssociatedIcon(Environment.ProcessPath!);
        if (_appIcon != null)
            Icon = _appIcon;
    }

    protected override void OnLoad(EventArgs e)
    {
        base.OnLoad(e);

        var didScale = false;
        if (!_hasScaled)
        {
            _hasScaled = true;
            var scale = DeviceDpi / 96f;
            if (scale > 1.01f || scale < 0.99f)
            {
                ApplyDpiScale(scale);
                didScale = true;
            }
        }

        if (WindowState == FormWindowState.Normal)
        {
            var area = Screen.FromControl(this).WorkingArea;

            if (Width > area.Width) Width = area.Width;
            if (Height > area.Height) Height = area.Height;

            if (didScale ||
                StartPosition == FormStartPosition.CenterScreen ||
                StartPosition == FormStartPosition.CenterParent)
            {
                Location = new Point(
                    area.X + Math.Max(0, (area.Width - Width) / 2),
                    area.Y + Math.Max(0, (area.Height - Height) / 2));
            }
            else
            {
                var x = Math.Max(area.X, Math.Min(Location.X, area.Right - Width));
                var y = Math.Max(area.Y, Math.Min(Location.Y, area.Bottom - Height));
                if (x != Location.X || y != Location.Y)
                    Location = new Point(x, y);
            }
        }
    }

    private void ApplyDpiScale(float scale)
    {
        // Bottom/Right anchors are the source of every cut-off-buttons bug
        // on high-DPI displays. At construction time on a 192-DPI monitor,
        // chrome (title bar + borders) eats more of the outer Size than at
        // 96 DPI design, so the as-constructed ClientSize is *smaller* than
        // the design intent. Bottom-anchored controls are already overflowing
        // by the time their Anchor distance is captured — that distance is
        // negative, and Form.Scale plus our ClientSize grow both preserve it
        // (the anchor pulls the control back to "20px past the bottom" no
        // matter how big we make the form).
        //
        // Fix: reset every anchor to Top|Left while we scale and resize, then
        // restore originals so distances re-capture against the now-correct
        // ClientSize.
        var origAnchors = new List<(Control control, AnchorStyles anchor)>();
        CollectAnchors(this, origAnchors);
        foreach (var (c, _) in origAnchors)
            c.Anchor = AnchorStyles.Top | AnchorStyles.Left;

        SuspendLayout();
        try
        {
            var origClient = ClientSize;
            Scale(new SizeF(scale, scale));

            // Only grow ClientSize for non-maximized forms. A maximized form's
            // visible client area is locked to the working area minus chrome —
            // setting ClientSize to a larger value leaves the form in an
            // inconsistent state where ClientSize reports our set value while
            // the actual visible area is smaller, which breaks the layout
            // until the user toggles minimize/maximize.
            if (WindowState == FormWindowState.Normal)
            {
                int needW = (int)Math.Round(origClient.Width * scale);
                int needH = (int)Math.Round(origClient.Height * scale);
                int childPad = (int)Math.Round(10 * scale);
                foreach (Control c in Controls)
                {
                    if (!c.Visible) continue;
                    if (c.Right + childPad > needW) needW = c.Right + childPad;
                    if (c.Bottom + childPad > needH) needH = c.Bottom + childPad;
                }
                ClientSize = new Size(needW, needH);
            }
        }
        finally
        {
            // Restoring the original anchor recaptures the distances against
            // the current (now-correct) parent ClientSize.
            foreach (var (c, anchor) in origAnchors)
                c.Anchor = anchor;
            ResumeLayout(true);
        }
    }

    private static void CollectAnchors(Control parent, List<(Control, AnchorStyles)> sink)
    {
        foreach (Control c in parent.Controls)
        {
            sink.Add((c, c.Anchor));
            CollectAnchors(c, sink);
        }
    }
}
