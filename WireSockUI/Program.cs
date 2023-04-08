using Microsoft.Win32;
using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;
using WireSockUI.Forms;
using WireSockUI.Properties;

namespace WireSockUI
{
    internal static class Global
    {
        public static string MainFolder = $"{Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData)}\\WireSockUI";
        public static string ConfigsFolder = MainFolder + "\\Configs";
    }

    internal static class Program
    {
        [STAThread]
        private static void Main()
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);

            Application.ApplicationExit += (sender, eventArgs) =>
            {
                // Ensure we de-register from toast notifications on exit
                //ToastNotificationManagerCompat.Uninstall();
            };

            if (!Directory.Exists(Global.MainFolder)) Directory.CreateDirectory(Global.MainFolder);
            if (!Directory.Exists(Global.ConfigsFolder)) Directory.CreateDirectory(Global.ConfigsFolder);
            
            if (!IsWireSockInstalled())
            {
                MessageBox.Show(Resources.AppNoWireSockMessage, Resources.AppNoWireSockTitle, MessageBoxButtons.OK, MessageBoxIcon.Information);

                string target = Resources.AppWireSockURL;

                try
                {
                    Process.Start(target);
                }
                catch
                {
                }

                Application.Exit();
            }

            Application.Run(new frmMain());
        }

        private static bool IsWireSockInstalled()
        {
            using (RegistryKey key = Registry.LocalMachine.OpenSubKey("SOFTWARE\\NTKernelResources\\WinpkFilterForVPNClient"))
            {
                if (key == null) return false;
                string wiresockLocation = key.GetValue("InstallLocation") + "bin\\wiresock-client.exe";

                // Add the directory containing the wgbooster.dll to the system's path if it is not added
                string installPath = key.GetValue("InstallLocation").ToString();
                string binPath = Path.Combine(installPath, "bin");

                string environmentPath = Environment.GetEnvironmentVariable("PATH");

                if (environmentPath == null || environmentPath.Contains(binPath))
                    return File.Exists(wiresockLocation);

                environmentPath = $"{binPath};{environmentPath}";
                Environment.SetEnvironmentVariable("PATH", environmentPath);

                return File.Exists(wiresockLocation);
            }
        }
    }
}
