using System.Drawing;
using WireSockUI.Native;

namespace WireSockUI.Extensions
{
    internal static class BitmapExtensions
    {
        public static Bitmap DrawCircle(int size, int diameter, Brush color)
        {
            Bitmap bm = new Bitmap(size, size);

            using (Graphics gr = Graphics.FromImage(bm))
            {
                gr.PixelOffsetMode = System.Drawing.Drawing2D.PixelOffsetMode.HighQuality;
                gr.FillEllipse(color, 0, 0, diameter, diameter);
            }

            return bm;
        }

        /// <summary>
        /// Superimpose a secondary icon on top of the main icon
        /// </summary>
        /// <param name="icon"><see cref="Icon"/> to superimpose onto</param>
        /// <param name="size"><see cref="Icon"/> size to use</param>
        /// <param name="imposed"><see cref="WindowsIcons.Icons"/> to superimpose</param>
        /// <param name="imposedsize">Size of the superimposed icon</param>
        /// <param name="imposedOffset">Offset placement of the superimposed icon</param>
        /// <returns><see cref="Icon"/> with the superimposed icon</returns>
        public static Icon SuperImpose(this Icon icon, int size, WindowsIcons.Icons imposed, int imposedSize, int imposedOffset)
        {
            using (Bitmap bitmap = new Icon(icon, new Size(size, size)).ToBitmap())
            {
                using (Graphics gr = Graphics.FromImage(bitmap))
                {
                    gr.DrawIcon(WindowsIcons.GetWindowsIcon(imposed, imposedSize), imposedOffset, imposedOffset);
                }

                return Icon.FromHandle(bitmap.GetHicon());
            }
        }
    }
}
