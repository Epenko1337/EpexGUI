using System;
using System.Drawing;
using System.Windows.Forms;

namespace WireSockUI.Extensions
{
    internal static class ImageListExtensions
    {
        public static void AddClonedIcon(
            this ImageList.ImageCollection images,
            string key,
            Icon icon)
        {
            if (images == null) throw new ArgumentNullException(nameof(images));
            if (string.IsNullOrWhiteSpace(key)) throw new ArgumentException("An image key is required.", nameof(key));
            if (icon == null) throw new ArgumentNullException(nameof(icon));

            // The keyed ImageList overload retains the caller's Icon until the
            // native image-list handle is created. The unkeyed overload clones
            // the Icon and transfers ownership of that clone to ImageList.
            var imageIndex = images.Count;
            images.Add(icon);
            images.SetKeyName(imageIndex, key);
        }
    }
}
