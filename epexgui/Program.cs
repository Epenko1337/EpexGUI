using epexgui.Properties;
using System;
using System.Windows.Forms;
using Microsoft.Win32;
using System.IO;
using System.Diagnostics;
using System.Runtime.InteropServices;
using epexgui.Forms;

namespace epexgui
{
    internal static class Global
    {
        public static string MainFolder = $"{Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData)}\\EpexGUI";
        public static string ConfigsFolder = MainFolder + "\\Configs";
        public static string SettingsFile = MainFolder + "\\Settings.txt";
        public static string WireSock = string.Empty;
        public static SettingsManager SetMan;
    }
    internal static class Program
    {
        [STAThread]
        private static void Main()
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);

            if (!Directory.Exists(Global.MainFolder)) Directory.CreateDirectory(Global.MainFolder);
            if (!Directory.Exists(Global.ConfigsFolder)) Directory.CreateDirectory(Global.ConfigsFolder);
            Global.SetMan = new SettingsManager();
            
            if (!IsWiresockInstalled())
            {
                MessageBox.Show(@"Wiresock will be installed now", @"Wiresock not found", MessageBoxButtons.OK, MessageBoxIcon.Information);
                InstallWiresock();
                if (!IsWiresockInstalled())
                {
                    MessageBox.Show(@"Try to install wiresock by yourself from wiresock.net", @"Installation failed", MessageBoxButtons.OK, MessageBoxIcon.Error);
                    Application.Exit();
                }
                MessageBox.Show(@"Wiresock successfully installed", @"Installation complete", MessageBoxButtons.OK, MessageBoxIcon.Information);
            }

            if (Global.SetMan.AppSettings.AutoRun) Global.SetMan.CheckTask();
            Application.Run(new Main());
        }

        private static bool IsWiresockInstalled()
        {
            var key = Registry.LocalMachine.OpenSubKey("SOFTWARE\\NTKernelResources\\WinpkFilterForVPNClient");
            if (key == null) return false;
            Global.WireSock = key.GetValue("InstallLocation") + "bin\\wiresock-client.exe";

            // Add the directory containing the wgbooster.dll to the system's path if it is not added
            var installPath = key.GetValue("InstallLocation").ToString();
            var binPath = Path.Combine(installPath, "bin");

            var environmentPath = Environment.GetEnvironmentVariable("PATH");
            if (environmentPath == null || environmentPath.Contains(binPath)) return File.Exists(Global.WireSock);
            environmentPath = $"{binPath};{environmentPath}";
            Environment.SetEnvironmentVariable("PATH", environmentPath);

            return File.Exists(Global.WireSock);
        }

        private static void InstallWiresock() 
        {
            var msiPath = Path.Combine(Path.GetTempPath(), "wiresock-installer.msi");
            var architecture = RuntimeInformation.ProcessArchitecture;
            switch (architecture)
            {
                case Architecture.X86:
                    File.WriteAllBytes(msiPath, Resources.wiresockInstallerX86);
                    break;
                case Architecture.X64:
                    File.WriteAllBytes(msiPath, Resources.wiresockInstallerX64);
                    break;
                case Architecture.Arm64:
                case Architecture.Arm:
                default:
                    MessageBox.Show(@"Unsupported target platform", @"Error",
                        MessageBoxButtons.OK, MessageBoxIcon.Error);
                    Console.WriteLine(@"Unsupported target platform");
                    return;
            }
            
            var installerProcess = new Process();
            var processInfo = new ProcessStartInfo
            {
                Arguments = $@"/i {msiPath} /q",
                FileName = "msiexec"
            };
            installerProcess.StartInfo = processInfo;
            installerProcess.Start();
            installerProcess.WaitForExit();

            File.Delete(msiPath);
        }
    }
}
