using System;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Windows.Forms;

namespace WireSockUI.Native
{
    internal class WindowsApplicationContext : ApplicationContext
    {
        private readonly string _executablePath;
        private readonly object _notificationShortcutSyncRoot = new object();
        private bool _notificationShortcutReady;

        private WindowsApplicationContext(
            string name,
            string appUserModelId,
            string executablePath,
            bool notificationShortcutReady)
        {
            Name = name;
            AppUserModelId = appUserModelId;
            _executablePath = executablePath;
            _notificationShortcutReady = notificationShortcutReady;
        }

        /// <summary>
        /// </summary>
        public string Name { get; }

        public string AppUserModelId { get; }

        internal bool NotificationShortcutReady
        {
            get
            {
                lock (_notificationShortcutSyncRoot)
                    return _notificationShortcutReady;
            }
        }

        internal bool TryEnsureNotificationShortcutReady()
        {
            lock (_notificationShortcutSyncRoot)
            {
                if (_notificationShortcutReady)
                    return true;

                _notificationShortcutReady = EnsureNotificationShortcut(Name, _executablePath);
                return _notificationShortcutReady;
            }
        }

        [DllImport("shell32.dll")]
        private static extern int SetCurrentProcessExplicitAppUserModelID(
            [MarshalAs(UnmanagedType.LPWStr)] string appId);

        public static WindowsApplicationContext FromCurrentProcess(
            string customName = null,
            string appUserModelId = null,
            string activationExecutablePath = null)
        {
            string executablePath;
            if (!string.IsNullOrWhiteSpace(activationExecutablePath))
            {
                executablePath = Path.GetFullPath(activationExecutablePath);
            }
            else
            {
                using (var process = Process.GetCurrentProcess())
                    executablePath = process.MainModule?.FileName;
            }

            if (executablePath == null) throw new InvalidOperationException("No valid process module found.");

            var appName = customName ?? Path.GetFileNameWithoutExtension(executablePath);
            var aumid = appUserModelId ?? BuildDefaultAppUserModelId(appName);

            var result = SetCurrentProcessExplicitAppUserModelID(aumid);
            if (result < 0)
                Marshal.ThrowExceptionForHR(result);

            var notificationShortcutReady = EnsureNotificationShortcut(appName, executablePath);

            return new WindowsApplicationContext(appName, aumid, executablePath, notificationShortcutReady);
        }

        private static bool EnsureNotificationShortcut(string appName, string executablePath)
        {
            try
            {
                var userStartMenuPath = Environment.GetFolderPath(Environment.SpecialFolder.Programs);
                if (string.IsNullOrWhiteSpace(userStartMenuPath))
                    throw new DirectoryNotFoundException(
                        "The current user's Start Menu Programs folder is unavailable.");

                using (SecureFileSystem.OpenDirectoryChainForStableChildCreation(userStartMenuPath))
                    DeleteLegacyNotificationShortcuts(userStartMenuPath, appName, executablePath);

                var commonStartMenuPath = Environment.GetFolderPath(Environment.SpecialFolder.CommonPrograms);
                if (string.IsNullOrWhiteSpace(commonStartMenuPath))
                    throw new DirectoryNotFoundException(
                        "The all-users Start Menu Programs folder is unavailable.");

                var shortcutFile = BuildInstalledShortcutPath(commonStartMenuPath, appName);
                if (!TryGetAttributes(shortcutFile, out var attributes))
                {
                    Trace.TraceInformation(
                        "WireSock UI notifications are disabled because the optional installer Start menu shortcut is not installed.");
                    return false;
                }

                if ((attributes & (FileAttributes.Directory | FileAttributes.ReparsePoint)) != 0 ||
                    Program.IsPotentiallyUserWritableFile(shortcutFile))
                    throw new InvalidOperationException(
                        $"The installer-owned notification shortcut '{shortcutFile}' is not a protected regular file. Repair WireSock UI and retry.");

                return true;
            }
            catch (Exception ex) when (ex is IOException ||
                                       ex is UnauthorizedAccessException ||
                                       ex is Win32Exception ||
                                       ex is COMException ||
                                       ex is CryptographicException ||
                                       ex is InvalidOperationException)
            {
                Trace.TraceWarning($"Unable to ensure the WireSock UI notification shortcut: {ex.Message}");
                return false;
            }
        }

        private static void DeleteLegacyNotificationShortcuts(
            string startMenuPath,
            string appName,
            string executablePath)
        {
            var executableName = Path.GetFileNameWithoutExtension(executablePath);
            foreach (var shortcutName in new[]
                     {
                         BuildShortcutFileName(appName),
                         BuildLegacyShortcutFileName(executableName, executablePath),
                         BuildLegacyShortcutFileName(appName, executablePath)
                     })
            {
                var shortcutPath = Path.Combine(startMenuPath, shortcutName);
                if (!TryGetAttributes(shortcutPath, out var attributes))
                    continue;

                Trace.TraceInformation(
                    $"Removing legacy per-user notification shortcut '{shortcutPath}' without parsing its contents.");
                DeleteExistingShortcut(shortcutPath, attributes);
            }
        }

        private static void DeleteExistingShortcut(string shortcutFile, FileAttributes attributes)
        {
            if ((attributes & FileAttributes.Directory) != 0)
            {
                if ((attributes & FileAttributes.ReparsePoint) != 0)
                {
                    using (var shortcut = SecureFileSystem.OpenReparsePointForDelete(shortcutFile, true))
                        shortcut.Delete();
                    return;
                }

                throw new InvalidOperationException(
                    $"The notification shortcut path '{shortcutFile}' points to a directory.");
            }

            if ((attributes & FileAttributes.ReparsePoint) != 0)
            {
                using (var shortcut = SecureFileSystem.OpenReparsePointForDelete(shortcutFile, false))
                    shortcut.Delete();
                return;
            }

            using (var shortcut = SecureFileSystem.OpenFileForDelete(shortcutFile))
                shortcut.Delete();
        }

        private static bool TryGetAttributes(string path, out FileAttributes attributes)
        {
            try
            {
                attributes = File.GetAttributes(path);
                return true;
            }
            catch (FileNotFoundException)
            {
                attributes = default(FileAttributes);
                return false;
            }
            catch (DirectoryNotFoundException)
            {
                attributes = default(FileAttributes);
                return false;
            }
        }

        private static string BuildDefaultAppUserModelId(string appName)
        {
            const int maxAppUserModelIdLength = 128;
            const string prefix = "WireSock.Foundation";

            var segment = SanitizeAppUserModelIdSegment(appName);
            var maxSegmentLength = maxAppUserModelIdLength - prefix.Length - 1;
            if (segment.Length > maxSegmentLength)
                segment = segment.Substring(0, maxSegmentLength).Trim('.');

            return $"{prefix}.{segment}";
        }

        private static string SanitizeAppUserModelIdSegment(string value)
        {
            var builder = new StringBuilder();
            foreach (var character in value ?? string.Empty)
                builder.Append(char.IsLetterOrDigit(character) ? character : '.');

            var segment = builder.ToString().Trim('.');
            return string.IsNullOrWhiteSpace(segment) ? "WireSockUI" : segment;
        }

        internal static string BuildShortcutFileName(string appName)
        {
            return $"{SanitizeShortcutFileNameSegment(appName)}.lnk";
        }

        internal static string BuildInstalledShortcutPath(string commonStartMenuPath, string appName)
        {
            if (string.IsNullOrWhiteSpace(commonStartMenuPath))
                throw new ArgumentException("The all-users Start Menu path is required.", nameof(commonStartMenuPath));

            return Path.Combine(commonStartMenuPath, BuildShortcutFileName(appName));
        }

        internal static string BuildLegacyShortcutFileName(string appName, string executablePath)
        {
            return $"{SanitizeShortcutFileNameSegment(appName)}-{BuildPathSeed(executablePath)}.lnk";
        }

        private static string SanitizeShortcutFileNameSegment(string value)
        {
            const int maxSegmentLength = 80;
            var builder = new StringBuilder();

            foreach (var character in value ?? string.Empty)
                builder.Append(char.IsLetterOrDigit(character) || character == ' ' || character == '-' ||
                               character == '_'
                    ? character
                    : '_');

            var segment = builder.ToString().Trim().TrimEnd('.');
            if (string.IsNullOrWhiteSpace(segment))
                segment = "WireSockUI";
            if (segment.Length > maxSegmentLength)
                segment = segment.Substring(0, maxSegmentLength).TrimEnd('.');

            return segment;
        }

        internal static string BuildPathSeed(string path)
        {
            using (var sha256 = SHA256.Create())
            {
                var normalizedPath = Path.GetFullPath(path ?? string.Empty).ToUpperInvariant();
                var hash = sha256.ComputeHash(Encoding.Unicode.GetBytes(normalizedPath));
                var builder = new StringBuilder(16);
                for (var index = 0; index < 8; index++)
                    builder.Append(hash[index].ToString("x2"));

                return builder.ToString();
            }
        }
    }
}
