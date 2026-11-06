using System;
using System.ComponentModel;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using WireSockUI;
using WireSockUI.Config;
using WireSockUI.Native;

namespace WireSockUI.Tests
{
    internal static partial class Program
    {
        private static void GlobalRejectsUntrustedPreexistingSecureData()
        {
            var originalSecureMainFolder = Global.SecureMainFolder;
            var originalOwnerWriteFailure = SecureFileSystem.AllowOwnerWriteFailureForTests;
            var directory = Path.Combine(Path.GetTempPath(), "WireSockUI.Tests", Guid.NewGuid().ToString("N"));

            try
            {
                Directory.CreateDirectory(directory);
                var preseededSettings = Path.Combine(directory, "PrivilegedSettings.xml");
                File.WriteAllText(preseededSettings, "attacker-controlled");
                AssertTrue(WireSockUI.Program.IsPotentiallyUserWritableDirectory(directory),
                    "Expected the test directory to represent a non-administrator-controlled pre-seed.");
                var securityBefore = Directory.GetAccessControl(directory).GetSecurityDescriptorBinaryForm();

                Global.SecureMainFolder = directory;
                SecureFileSystem.AllowOwnerWriteFailureForTests = false;
                AssertThrows<UnauthorizedAccessException>(
                    () => Global.EnsureSecureMainFolderExists(),
                    "Refusing to change security");

                var securityAfter = Directory.GetAccessControl(directory).GetSecurityDescriptorBinaryForm();
                AssertTrue(securityBefore.SequenceEqual(securityAfter),
                    "Expected startup trust validation not to rewrite the untrusted directory ACL.");
                AssertEqual("attacker-controlled", File.ReadAllText(preseededSettings));
            }
            finally
            {
                Global.SecureMainFolder = originalSecureMainFolder;
                SecureFileSystem.AllowOwnerWriteFailureForTests = originalOwnerWriteFailure;
                TryDeleteDirectory(directory, true);
            }
        }

        private static void LegacyMigrationCleansManagedOrphansBeforeCatalogLimit()
        {
            WithTemporaryLegacyMigrationFolders((legacyFolder, pendingFolder) =>
            {
                Directory.CreateDirectory(pendingFolder);
                for (var index = 0; index <= LegacyProfileMigrationService.MaxLegacyCatalogEntries; index++)
                    File.WriteAllText(
                        Path.Combine(pendingFolder, Guid.NewGuid().ToString("N") + ".tmp"),
                        "orphan");

                File.WriteAllText(Path.Combine(pendingFolder, "office.conf"), ValidConfig());
                var pendingNames = LegacyProfileMigrationService.GetPendingProfileNames();

                AssertEqual(1, pendingNames.Count);
                AssertEqual("office", pendingNames[0]);
                AssertFalse(Directory.EnumerateFiles(pendingFolder, "*.tmp").Any(),
                    "Expected managed migration temporaries to be removed before applying the catalog limit.");
            });
        }

        private static void ProfileTransactionRecoveryCleansManagedOrphansBeforeEntryLimit()
        {
            WithTemporaryConfigFolder(() =>
            {
                Global.EnsureProfileTransactionsFolderExists();
                for (var index = 0; index <= 256; index++)
                    File.WriteAllText(
                        Path.Combine(
                            Global.ProfileTransactionsFolder,
                            Guid.NewGuid().ToString("N") + ".profile.tmp"),
                        "orphan");

                ProfileFileTransaction.RecoverInterruptedTransactions();

                AssertFalse(Directory.EnumerateFileSystemEntries(Global.ProfileTransactionsFolder).Any(),
                    "Expected managed transaction temporaries to be removed before applying the entry limit.");
            });
        }

        private static void ShellLinkPropVariantInteropIsSafe()
        {
            var propVariantType = typeof(ShellLink).GetNestedType(
                "PropVariant", BindingFlags.NonPublic);
            if (propVariantType == null)
                throw new InvalidOperationException("ShellLink.PropVariant was not found.");

            AssertEqual(ShellLink.NativePropVariantSize, Marshal.SizeOf(propVariantType));
            AssertEqual(IntPtr.Size == 8 ? 24 : 16, ShellLink.NativePropVariantSize);

            var propVariant = Activator.CreateInstance(propVariantType, true);
            try
            {
                propVariantType.GetProperty("VarType")?.SetValue(
                    propVariant, VarEnum.VT_UI4, null);
                try
                {
                    propVariantType.GetProperty("Value")?.GetValue(propVariant, null);
                    throw new InvalidOperationException(
                        "Expected a non-string PROPVARIANT to be rejected.");
                }
                catch (TargetInvocationException ex) when (ex.InnerException is InvalidDataException)
                {
                }
            }
            finally
            {
                (propVariant as IDisposable)?.Dispose();
            }

            var directory = Path.Combine(Path.GetTempPath(), "WireSockUI.Tests", Guid.NewGuid().ToString("N"));
            var shortcutPath = Path.Combine(directory, "property.lnk");
            var targetPath = Assembly.GetExecutingAssembly().Location;
            const string appUserModelId = "WireSock.Foundation.Tests.PropVariant";
            try
            {
                Directory.CreateDirectory(directory);
                using (var shortcut = new ShellLink
                {
                    TargetPath = targetPath,
                    AppUserModelId = appUserModelId
                })
                    shortcut.Save(shortcutPath);

                using (var shortcut = new ShellLink(shortcutPath))
                    AssertEqual(appUserModelId, shortcut.AppUserModelId);
            }
            finally
            {
                TryDeleteDirectory(directory, true);
            }
        }
    }
}
