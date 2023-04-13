using System;
using WireSockUI.Properties;

namespace WireSockUI.Extensions
{
    internal static class NumberExtensions
    {
        internal static string AsHumanReadable(this ulong value)
        {
            var n2 = value == 0 ? 0 : (int)Math.Log10(value) / 3;
            var n3 = value == 0 ? 0 : value / Math.Pow(1e3, n2);

            return
                $"{n3:f2} {new[] { Resources.SizeBytes, Resources.SizeKB, Resources.SizeMB, Resources.SizeGB, Resources.SizeTB, Resources.SizePB }[n2]}";
        }
    }
}