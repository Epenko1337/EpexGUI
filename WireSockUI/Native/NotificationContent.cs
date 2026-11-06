using System;
using System.IO;
using System.Xml.Linq;

namespace WireSockUI.Native
{
    internal static class NotificationContent
    {
        internal static string BuildLocalImageUri(string path)
        {
            if (string.IsNullOrWhiteSpace(path))
                throw new ArgumentException("A notification image path is required.", nameof(path));

            return new Uri(Path.GetFullPath(path), UriKind.Absolute).AbsoluteUri;
        }

        internal static string BuildToastXml(
            string title,
            string body,
            string iconPath,
            string applicationName,
            Version windowsVersion)
        {
            if (windowsVersion == null)
                throw new ArgumentNullException(nameof(windowsVersion));

            var iconUri = BuildLocalImageUri(iconPath);
            XElement binding;
            if (windowsVersion.Major >= 10)
            {
                binding = new XElement("binding",
                    new XAttribute("template", "ToastGeneric"),
                    new XElement("text", title),
                    new XElement("text", body),
                    new XElement("image",
                        new XAttribute("src", iconUri),
                        new XAttribute("alt", applicationName),
                        new XAttribute("placement", "appLogoOverride"),
                        new XAttribute("hint-crop", "circle")));
            }
            else
            {
                binding = new XElement("binding",
                    new XAttribute("template", "ToastImageAndText02"),
                    new XElement("image",
                        new XAttribute("id", "1"),
                        new XAttribute("src", iconUri),
                        new XAttribute("alt", applicationName)),
                    new XElement("text", new XAttribute("id", "1"), title),
                    new XElement("text", new XAttribute("id", "2"), body));
            }

            return new XElement("toast", new XElement("visual", binding))
                .ToString(SaveOptions.DisableFormatting);
        }
    }
}
