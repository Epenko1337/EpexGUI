using System.Windows.Forms;

namespace WireSockUI.Forms
{
    internal sealed class BufferedListView : ListView
    {
        internal BufferedListView()
        {
            DoubleBuffered = true;
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer, true);
        }
    }
}
