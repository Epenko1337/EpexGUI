using epexgui.Properties;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using System.Windows.Forms;
using Microsoft.Win32;
using System.IO;
using System.Diagnostics;

namespace epexgui
{
    static class Global
    {
        public static string MainFolder = $"{Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData)}\\EpexGUI";
        public static string ConfigsFolder = MainFolder + "\\Configs";
        public static string SettingsFile = MainFolder + "\\Settings.txt";
        public static string WireSock = string.Empty;
        public static SettingsManager setMan;
    }
    internal static class Program
    {
        [STAThread]
        static void Main()
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);

            if (!Directory.Exists(Global.MainFolder)) Directory.CreateDirectory(Global.MainFolder);
            if (!Directory.Exists(Global.ConfigsFolder)) Directory.CreateDirectory(Global.ConfigsFolder);
            Global.setMan = new SettingsManager();
            
            if (!IsWiresockInstalled())
            {
                MessageBox.Show("Wiresock will be installed now", "Wiresock not found", MessageBoxButtons.OK, MessageBoxIcon.Information);
                InstallWiresock();
                if (!IsWiresockInstalled())
                {
                    MessageBox.Show("Try to install wiresock by yourself from wiresock.net", "Installation failed", MessageBoxButtons.OK, MessageBoxIcon.Error);
                    Application.Exit();
                }
                MessageBox.Show("Wiresock successfully installed", "Installation complete", MessageBoxButtons.OK, MessageBoxIcon.Information);
            }

            if (Global.setMan.settings.Autorun) Global.setMan.CheckTask();
            Application.Run(new Main());
        }

        private static bool IsWiresockInstalled()
        {
            RegistryKey key = Registry.LocalMachine.OpenSubKey("SOFTWARE\\NTKernelResources\\WinpkFilterForVPNClient");
            if (key != null)
            {
                Global.WireSock = key.GetValue("InstallLocation").ToString() + "bin\\wiresock-client.exe";
                return File.Exists(Global.WireSock);
            }
            return false;
        }

        private static void InstallWiresock() 
        {
            string msipath = Path.Combine(Path.GetTempPath(), "wiresock-installer.msi");
            File.WriteAllBytes(msipath, Resources.wiresockInstaller);
            Process installerProcess = new Process();
            ProcessStartInfo processInfo = new ProcessStartInfo();
            processInfo.Arguments = $@"/i {msipath} /q";
            processInfo.FileName = "msiexec";
            installerProcess.StartInfo = processInfo;
            installerProcess.Start();
            installerProcess.WaitForExit();

            File.Delete(msipath);
        }
    }
}
