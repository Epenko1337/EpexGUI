using System;
using System.IO;
using System.Net;
using System.Reflection;
using System.Windows.Forms;
using Windows.Data.Json;

namespace WireSockUI.Extensions
{
    internal static class GitHubExtensions
    {
        /// <summary>
        /// Retrieve latest published release version from GitHub
        /// </summary>
        /// <returns><see cref="T:Version"/> or null</returns>
        public static Version GetLatestRelease(string repository)
        {
            if (!String.IsNullOrEmpty(repository))
            {

                HttpWebRequest request = WebRequest.CreateHttp($"https://api.github.com/repos/{repository}/releases/latest");

                request.Method = "GET";
                request.Accept = "application/vnd.github+json";
                request.UserAgent = "WireSockUI";

                using (WebResponse response = request.GetResponse())
                {
                    using (StreamReader reader = new StreamReader(response.GetResponseStream()))
                    {
                        string data = reader.ReadToEnd();

                        if (JsonObject.TryParse(data, out JsonObject json))
                        {
                            string tag = json.GetNamedString("tag_name");
                            tag = tag.Trim(new char[] { 'v' });

                            return new Version(tag);
                        }
                    }
                }

            }

            return null;
        }
    }
}
