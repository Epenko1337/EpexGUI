﻿using System;
using System.IO;
using System.Net;
using Windows.Data.Json;

namespace WireSockUI.Extensions
{
    internal static class GitHubExtensions
    {
        /// <summary>
        ///     Retrieve latest published release version from GitHub
        /// </summary>
        /// <returns><see cref="T:Version" /> or null</returns>
        public static Version GetLatestRelease(string repository)
        {
            if (string.IsNullOrEmpty(repository)) return null;
            var request = WebRequest.CreateHttp($"https://api.github.com/repos/{repository}/releases/latest");

            request.Method = "GET";
            request.Accept = "application/vnd.github+json";
            request.UserAgent = "WireSockUI";

            using (var response = request.GetResponse())
            {
                using (var reader = new StreamReader(response.GetResponseStream()))
                {
                    var data = reader.ReadToEnd();

                    if (!JsonObject.TryParse(data, out var json)) return null;
                    var tag = json.GetNamedString("tag_name");
                    tag = tag.Trim('v');

                    return new Version(tag);
                }
            }
        }
    }
}