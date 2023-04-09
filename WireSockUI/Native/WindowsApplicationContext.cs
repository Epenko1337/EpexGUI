using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace WireSockUI.Native
{
    internal class WindowsApplicationContext : ApplicationContext
    {
        private WindowsApplicationContext(string name, string appUserModelId)
        {
            Name = name;
            AppUserModelId = appUserModelId;
        }

        /// <summary>
        /// </summary>
        public string Name { get; }

        public string AppUserModelId { get; }

        [DllImport("shell32.dll", SetLastError = true)]
        private static extern void SetCurrentProcessExplicitAppUserModelID(
            [MarshalAs(UnmanagedType.LPWStr)] string appId);

        public static WindowsApplicationContext FromCurrentProcess(
            string customName = null,
            string appUserModelId = null)
        {
            ProcessModule mainModule = Process.GetCurrentProcess().MainModule;

            if (mainModule?.FileName == null)
            {
                throw new InvalidOperationException("No valid process module found.");
            }

            string appName = customName ?? Path.GetFileNameWithoutExtension(mainModule.FileName);
            string aumid = appUserModelId ?? appName; //TODO: Add seeded bits to avoid collisions?

            SetCurrentProcessExplicitAppUserModelID(aumid);

            using (ShellLink shortcut = new ShellLink
            {
                TargetPath = mainModule.FileName,
                Arguments = string.Empty,
                AppUserModelID = aumid
            })
            {
                string appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
                string startMenuPath = Path.Combine(appData, @"Microsoft\Windows\Start Menu\Programs");
                string shortcutFile = Path.Combine(startMenuPath, $"{appName}.lnk");

                shortcut.Save(shortcutFile);
            }

            return new WindowsApplicationContext(appName, aumid);
        }
    }
}
