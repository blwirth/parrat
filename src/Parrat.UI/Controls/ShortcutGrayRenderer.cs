using System.Drawing;
using System.Windows.Forms;

namespace Parrat.UI.Controls;

/// <summary>
/// Custom ToolStrip renderer that draws keyboard shortcut text in gray
/// to visually distinguish it from the menu item label text.
/// Ported from inline C# in parrat.ps1 lines 108-134.
/// </summary>
public class ShortcutGrayRenderer : ToolStripProfessionalRenderer
{
    protected override void OnRenderItemText(ToolStripItemTextRenderEventArgs e)
    {
        if (e.Item is ToolStripMenuItem menuItem
            && menuItem.ShowShortcutKeys
            && menuItem.ShortcutKeys != Keys.None)
        {
            string? shortcutText = menuItem.ShortcutKeyDisplayString;
            if (string.IsNullOrEmpty(shortcutText))
            {
                var converter = new KeysConverter();
                shortcutText = converter.ConvertToString(menuItem.ShortcutKeys);
            }

            if (e.Text == shortcutText)
            {
                e.TextColor = SystemColors.GrayText;
            }
        }

        base.OnRenderItemText(e);
    }
}
