using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace WireSockUI.Native
{
 
    /// <summary>
    /// Read and Write INI File format using Windows native APIs
    /// </summary>
    internal static class INIFile
    {
        // https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-getprivateprofilesectionnamesw
        [DllImport("kernel32")]
        private static extern uint GetPrivateProfileSectionNames([In, Out] char[] lpszReturnBuffer, int nSize, string lpFileName);

        // https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-getprivateprofilesectiona
        [DllImport("kernel32")]
        private static extern uint GetPrivateProfileSection(string lpAppName, [In, Out] char[] lpszReturnBuffer, int nSize, string lpFileName);

        // https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-getprivateprofilestring
        [DllImport("kernel32")]
        private static extern uint GetPrivateProfileString(string lpAppName, string lpKeyName, string lpDefault, [In, Out] char[] lpReturnedString, int nSize, string lpFileName);

        // https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-getprivateprofileint
        [DllImport("kernel32")]
        private static extern uint GetPrivateProfileInt(string lpAppName, string lpKeyName, string lpDefault, [In, Out] char[] lpReturnedString, int nSize, string lpFileName);

        // https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-writeprivateprofilestringa
        [DllImport("kernel32")]
        private static extern long WritePrivateProfileString(string name, string key, string val, string filePath);

        /// <summary>
        /// Enumerate all available section names in the specified INI file
        /// </summary>
        /// <param name="fileName">Path to INI file</param>
        /// <returns><see cref="IEnumerable{string}"/> with all section names</returns>
        public static IEnumerable<string> GetSectionNames(string fileName)
        {
            const int BUFFER_SIZE = 32 * 1024;

            // MSDN specifies maximum of 32 KB
            char[] buffer = new char[BUFFER_SIZE];

            uint length = GetPrivateProfileSectionNames(buffer, BUFFER_SIZE, fileName);

            if (length != (BUFFER_SIZE - 2))
            {
                string value = new string(buffer, 0, (int)length);

                foreach (string entry in value.Trim('\0').Split('\0'))
                {
                    yield return entry;
                }
            }
        }

        /// <summary>
        /// Enumerate all available keys in a <paramref name="sectionName"/> in the specified INI file
        /// </summary>        
        /// <param name="fileName">Path to INI file</param>
        /// <param name="sectionName">Section name to lookup</param>
        /// <returns><see cref="IEnumerable{string}"/> with all section values</returns>
        public static Dictionary<string, string> GetSection(string fileName, string sectionName)
        {
            const int BUFFER_SIZE = 32 * 1024;

            // MSDN specifies maximum of 32 KB
            char[] buffer = new char[BUFFER_SIZE];

            uint length = GetPrivateProfileSection(sectionName, buffer, BUFFER_SIZE, fileName);

            Dictionary<string, string> section = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

            if (length != (BUFFER_SIZE - 2))
            {
                string value = new string(buffer, 0, (int)length);

                foreach (string entry in value.Trim('\0').Split('\0'))
                {
                    section.Add(entry.Substring(0, entry.IndexOf('=')), entry.Substring(entry.IndexOf('=') + 1));
                }
            }

            return section;
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="fileName">Path to INI file</param>
        /// <param name="sectionName">Section name to lookup</param>
        /// <param name="key">Value key</param>
        /// <returns><see cref="String"/ or empty</returns>

        public static string ReadString(string fileName, string sectionName, string key)
        {
            const int BUFFER_SIZE = 2 * 1024;

            char[] buffer = new char[BUFFER_SIZE];

            uint length = GetPrivateProfileString(sectionName, key, null, buffer, BUFFER_SIZE, fileName);

            if (length != (BUFFER_SIZE -2))
            {
                return new string(buffer, 0, (int)length);
            }

            return String.Empty;
        }

    }
}
