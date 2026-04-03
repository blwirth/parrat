using System.Drawing;
using System.Windows.Forms;

namespace Parrat.UI.Forms;

/// <summary>
/// Base form that applies the PARRAT application icon to all windows.
/// </summary>
public class ParratFormBase : Form
{
    private static Icon? _appIcon;

    protected ParratFormBase()
    {
        _appIcon ??= Icon.ExtractAssociatedIcon(Environment.ProcessPath!);
        if (_appIcon != null)
            Icon = _appIcon;
    }
}
