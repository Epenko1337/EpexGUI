using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Xml;
using System.Xml.Linq;
using WireSockUI.Native;
using WireSockUI.Properties;

namespace WireSockUI.Config
{
    internal static class LegacyUserSettingsMigrationService
    {
        internal const int MaximumSearchEntries = 2048;
        internal const int MaximumSearchDepth = 5;
        internal const int MaximumSettingsFileBytes = 256 * 1024;
        private const int MaximumValueCharacters = 4096;

        internal sealed class Snapshot
        {
            internal bool? AutoConnect { get; set; }
            internal bool? AutoMinimize { get; set; }
            internal bool? AutoUpdate { get; set; }
            internal bool? EnableKillSwitch { get; set; }
            internal bool? EnableNotifications { get; set; }
            internal string LastProfile { get; set; }
            internal string LogLevel { get; set; }
            internal bool? UseAdapter { get; set; }
        }

        private sealed class Candidate
        {
            internal string Path { get; set; }
            internal Version Version { get; set; }
            internal DateTime LastWriteTimeUtc { get; set; }
        }

        private sealed class PendingDirectory
        {
            internal string Path { get; set; }
            internal int Depth { get; set; }
        }

        internal static bool ApplyLatest(Settings settings, string currentConfigurationPath)
        {
            return ApplyLatest(
                settings,
                currentConfigurationPath,
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData));
        }

        internal static bool ApplyLatest(
            Settings settings,
            string currentConfigurationPath,
            string localApplicationData)
        {
            if (settings == null) throw new ArgumentNullException(nameof(settings));

            try
            {
                foreach (var candidate in FindConfigurations(
                             currentConfigurationPath,
                             localApplicationData))
                {
                    try
                    {
                        if (TryReadConfiguration(candidate.Path, out var snapshot))
                        {
                            Apply(settings, snapshot);
                            Trace.TraceInformation(
                                "Imported bounded legacy per-user settings into the native-host application identity.");
                            return true;
                        }
                    }
                    catch (Exception ex) when (IsInvalidLegacySettingsException(ex))
                    {
                        Trace.TraceWarning(
                            $"Skipping an invalid legacy per-user settings file: {ex.Message}");
                    }
                }
                return true;
            }
            catch (Exception ex)
            {
                // These settings are cosmetic or are separately confirmed before
                // entering the privileged store. A malformed legacy file must not
                // prevent an otherwise safe startup.
                Trace.TraceWarning(
                    $"Unable to inspect legacy per-user settings: {ex.Message}");
                return false;
            }
        }

        internal static bool TryParse(Stream stream, out Snapshot snapshot)
        {
            snapshot = null;
            if (stream == null || !stream.CanRead)
                return false;

            var readerSettings = new XmlReaderSettings
            {
                DtdProcessing = DtdProcessing.Prohibit,
                IgnoreComments = true,
                IgnoreProcessingInstructions = true,
                MaxCharactersFromEntities = 0,
                MaxCharactersInDocument = MaximumSettingsFileBytes,
                XmlResolver = null
            };

            XDocument document;
            using (var reader = XmlReader.Create(stream, readerSettings))
                document = XDocument.Load(reader, LoadOptions.None);

            var parsed = new Snapshot();
            var found = false;
            foreach (var setting in document.Descendants("setting"))
            {
                if (setting.Parent == null ||
                    !string.Equals(
                        setting.Parent.Name.LocalName,
                        "WireSockUI.Properties.Settings",
                        StringComparison.Ordinal))
                    continue;

                var name = (string)setting.Attribute("name");
                var valueElement = setting.Element("value");
                if (string.IsNullOrEmpty(name) || valueElement == null)
                    continue;

                var value = valueElement.Value;
                if (value.Length > MaximumValueCharacters)
                    continue;

                switch (name)
                {
                    case "AutoConnect":
                        found |= TryAssignBoolean(value, result => parsed.AutoConnect = result);
                        break;
                    case "AutoMinimize":
                        found |= TryAssignBoolean(value, result => parsed.AutoMinimize = result);
                        break;
                    case "AutoUpdate":
                        found |= TryAssignBoolean(value, result => parsed.AutoUpdate = result);
                        break;
                    case "EnableKillSwitch":
                        found |= TryAssignBoolean(value, result => parsed.EnableKillSwitch = result);
                        break;
                    case "EnableNotifications":
                        found |= TryAssignBoolean(value, result => parsed.EnableNotifications = result);
                        break;
                    case "UseAdapter":
                        found |= TryAssignBoolean(value, result => parsed.UseAdapter = result);
                        break;
                    case "LastProfile":
                        if (Profile.IsValidProfileName(value))
                        {
                            parsed.LastProfile = value;
                            found = true;
                        }
                        break;
                    case "LogLevel":
                        if (IsSupportedLogLevel(value))
                        {
                            parsed.LogLevel = value;
                            found = true;
                        }
                        break;
                    default:
                        // AutoRun is deliberately omitted: the verified Task
                        // Scheduler definition, not user.config, is authoritative.
                        break;
                }
            }

            if (!found)
                return false;
            snapshot = parsed;
            return true;
        }

        private static Candidate[] FindConfigurations(
            string currentConfigurationPath,
            string localApplicationData)
        {
            if (string.IsNullOrWhiteSpace(localApplicationData) ||
                !Path.IsPathRooted(localApplicationData))
                throw new DirectoryNotFoundException(
                    "Windows did not provide an absolute LocalApplicationData path for legacy settings migration.");
            if (!IsLocalFixedPath(localApplicationData))
                throw new DirectoryNotFoundException(
                    "Windows did not provide a fixed local LocalApplicationData volume for legacy settings migration.");

            var roots = new[]
            {
                Path.Combine(localApplicationData, "WireSockUI"),
                Path.Combine(localApplicationData, "WireSock UI")
            };
            var candidates = new List<Candidate>();
            var inspectedEntries = 0;
            var currentVersion =
                typeof(LegacyUserSettingsMigrationService).Assembly.GetName().Version ??
                new Version(0, 0, 0, 0);
            string normalizedCurrentConfigurationPath = null;
            if (!string.IsNullOrWhiteSpace(currentConfigurationPath))
            {
                try
                {
                    normalizedCurrentConfigurationPath =
                        Path.GetFullPath(currentConfigurationPath);
                }
                catch (Exception ex)
                {
                    throw new IOException(
                        "Unable to normalize the current settings path.",
                        ex);
                }
            }

            foreach (var root in roots)
            {
                try
                {
                    if (!Directory.Exists(root) ||
                        IsReparsePoint(root))
                        continue;
                }
                catch (Exception ex)
                {
                    throw new IOException(
                        $"Unable to inspect legacy settings root '{root}'.",
                        ex);
                }

                var pending = new Queue<PendingDirectory>();
                pending.Enqueue(new PendingDirectory { Path = root, Depth = 0 });
                while (pending.Count > 0)
                {
                    var current = pending.Dequeue();
                    try
                    {
                        foreach (var entry in Directory.EnumerateFileSystemEntries(
                                     current.Path, "*", SearchOption.TopDirectoryOnly))
                        {
                            inspectedEntries++;
                            if (inspectedEntries > MaximumSearchEntries)
                                throw new InvalidDataException(
                                    $"Legacy settings search exceeded {MaximumSearchEntries} entries.");
                            FileAttributes attributes;
                            try
                            {
                                attributes = File.GetAttributes(entry);
                            }
                            catch (Exception ex)
                            {
                                throw new IOException(
                                    $"Unable to inspect legacy settings entry '{entry}'.",
                                    ex);
                            }
                            if ((attributes & FileAttributes.ReparsePoint) != 0)
                                continue;

                            if ((attributes & FileAttributes.Directory) != 0)
                            {
                                if (current.Depth < MaximumSearchDepth)
                                {
                                    pending.Enqueue(new PendingDirectory
                                    {
                                        Path = entry,
                                        Depth = current.Depth + 1
                                    });
                                }
                                continue;
                            }

                            if (!string.Equals(
                                    Path.GetFileName(entry),
                                    "user.config",
                                    StringComparison.OrdinalIgnoreCase))
                                continue;

                            try
                            {
                                var normalizedEntry = Path.GetFullPath(entry);
                                if (normalizedCurrentConfigurationPath != null &&
                                    string.Equals(
                                        normalizedEntry,
                                        normalizedCurrentConfigurationPath,
                                        StringComparison.OrdinalIgnoreCase))
                                    continue;

                                var file = new FileInfo(normalizedEntry);
                                if (!TryGetLegacyVersion(
                                        file.Directory, currentVersion, out var version))
                                    continue;
                                candidates.Add(new Candidate
                                {
                                    Path = file.FullName,
                                    Version = version,
                                    LastWriteTimeUtc = file.LastWriteTimeUtc
                                });
                            }
                            catch (Exception ex)
                            {
                                throw new IOException(
                                    $"Unable to inspect legacy settings metadata for '{entry}'.",
                                    ex);
                            }
                        }
                    }
                    catch (InvalidDataException)
                    {
                        throw;
                    }
                    catch (Exception ex)
                    {
                        throw new IOException(
                            $"Unable to enumerate legacy settings directory '{current.Path}'.",
                            ex);
                    }
                }
            }

            candidates.Sort((left, right) =>
            {
                var versionComparison = right.Version.CompareTo(left.Version);
                if (versionComparison != 0)
                    return versionComparison;
                var writeTimeComparison =
                    right.LastWriteTimeUtc.CompareTo(left.LastWriteTimeUtc);
                return writeTimeComparison != 0
                    ? writeTimeComparison
                    : StringComparer.OrdinalIgnoreCase.Compare(left.Path, right.Path);
            });
            return candidates.ToArray();
        }

        internal static bool TryReadConfiguration(string path, out Snapshot snapshot)
        {
            snapshot = null;
            var directory = Path.GetDirectoryName(Path.GetFullPath(path));
            if (string.IsNullOrWhiteSpace(directory))
                return false;

            using (SecureFileSystem.OpenDirectoryChain(directory))
            using (var file = SecureFileSystem.OpenFileForBoundedRead(
                       path, MaximumSettingsFileBytes))
            {
                var parsed = false;
                Snapshot parsedSnapshot = null;
                file.UseReadStream(
                    stream => parsed = TryParse(stream, out parsedSnapshot));
                snapshot = parsedSnapshot;
                return parsed;
            }
        }

        internal static bool IsKnownLegacyIdentityDirectory(string directoryName)
        {
            if (string.IsNullOrWhiteSpace(directoryName))
                return false;
            const string urlPrefix = "WireSockUI.exe_Url_";
            const string strongNamePrefix = "WireSockUI.exe_StrongName_";
            return (directoryName.StartsWith(
                        urlPrefix, StringComparison.OrdinalIgnoreCase) &&
                    directoryName.Length > urlPrefix.Length) ||
                   (directoryName.StartsWith(
                        strongNamePrefix, StringComparison.OrdinalIgnoreCase) &&
                    directoryName.Length > strongNamePrefix.Length);
        }

        private static bool IsInvalidLegacySettingsException(Exception exception)
        {
            return exception is XmlException ||
                   exception is FormatException ||
                   exception is InvalidDataException ||
                   exception is DecoderFallbackException;
        }

        internal static bool IsEligibleLegacyVersion(
            Version candidateVersion,
            Version currentVersion)
        {
            return candidateVersion != null &&
                   currentVersion != null &&
                   candidateVersion.Major >= 0 &&
                   candidateVersion.CompareTo(currentVersion) <= 0;
        }

        private static bool TryGetLegacyVersion(
            DirectoryInfo directory,
            Version currentVersion,
            out Version version)
        {
            version = null;
            return directory != null &&
                   directory.Parent != null &&
                   IsKnownLegacyIdentityDirectory(directory.Parent.Name) &&
                   Version.TryParse(directory.Name, out version) &&
                   IsEligibleLegacyVersion(version, currentVersion);
        }

        private static bool IsReparsePoint(string path)
        {
            return (File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0;
        }

        internal static bool IsLocalFixedPath(string path)
        {
            if (string.IsNullOrWhiteSpace(path) || !Path.IsPathRooted(path))
                throw new DirectoryNotFoundException(
                    "The LocalApplicationData path must be absolute.");

            var root = Path.GetPathRoot(Path.GetFullPath(path));
            if (string.IsNullOrWhiteSpace(root))
                throw new DirectoryNotFoundException(
                    "The LocalApplicationData volume root could not be resolved.");

            return new DriveInfo(root).DriveType == DriveType.Fixed;
        }

        private static bool TryAssignBoolean(string value, Action<bool> assign)
        {
            if (!bool.TryParse(value, out var parsed))
                return false;
            assign(parsed);
            return true;
        }

        private static bool IsSupportedLogLevel(string value)
        {
            return string.Equals(value, "Error", StringComparison.Ordinal) ||
                   string.Equals(value, "Info", StringComparison.Ordinal) ||
                   string.Equals(value, "Warning", StringComparison.Ordinal) ||
                   string.Equals(value, "Debug", StringComparison.Ordinal) ||
                   string.Equals(value, "All", StringComparison.Ordinal);
        }

        private static void Apply(Settings settings, Snapshot snapshot)
        {
            if (snapshot.AutoConnect.HasValue)
                settings.AutoConnect = snapshot.AutoConnect.Value;
            if (snapshot.AutoMinimize.HasValue)
                settings.AutoMinimize = snapshot.AutoMinimize.Value;
            if (snapshot.AutoUpdate.HasValue)
                settings.AutoUpdate = snapshot.AutoUpdate.Value;
            if (snapshot.EnableKillSwitch.HasValue)
                settings.EnableKillSwitch = snapshot.EnableKillSwitch.Value;
            if (snapshot.EnableNotifications.HasValue)
                settings.EnableNotifications = snapshot.EnableNotifications.Value;
            if (snapshot.UseAdapter.HasValue)
                settings.UseAdapter = snapshot.UseAdapter.Value;
            if (snapshot.LastProfile != null)
                settings.LastProfile = snapshot.LastProfile;
            if (snapshot.LogLevel != null)
                settings.LogLevel = snapshot.LogLevel;
        }
    }
}
