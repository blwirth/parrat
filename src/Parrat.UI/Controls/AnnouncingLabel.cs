using System.Windows.Forms;

namespace Parrat.UI.Controls;

/// <summary>
/// A label that tells assistive technology when its text changes.
///
/// A plain Label updates silently. That is fine for a caption, and useless for
/// a label whose whole job is to report a result the user just asked for — a
/// preview count, or a banner saying records are now hidden. Windows only
/// raises a name-change event when a control asks it to, and
/// <see cref="Control.AccessibilityNotifyClients"/> is protected, so the ask
/// has to live in the control itself.
/// </summary>
public class AnnouncingLabel : Label
{
    protected override void OnTextChanged(EventArgs e)
    {
        base.OnTextChanged(e);

        // -1 is the control itself rather than one of its children.
        AccessibilityNotifyClients(AccessibleEvents.NameChange, -1);
    }
}
