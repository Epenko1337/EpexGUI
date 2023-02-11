using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.IO;
using IniParser;
using IniParser.Model;
using epexgui.Properties;
using System.Diagnostics;

namespace epexgui
{
    internal class SettingsManager
    {
        public struct Settings
        {
            public bool Autorun;
            public bool MinimizeOnStart;
            public bool ConnectOnStart;
            public string LastConfig;
        }

        public Settings settings;
        private FileIniDataParser parser;
        private IniData data;
        public SettingsManager() 
        {
            if (!File.Exists(Global.SettingsFile)) CreateSettings();
            InitSettings();
            parser = new FileIniDataParser();
            data = parser.ReadFile(Global.SettingsFile);
            Update();
        }

        public void Update()
        {
            try
            {
                settings.Autorun = bool.Parse(data["Settings"]["autorun"]);
                settings.MinimizeOnStart = bool.Parse(data["Settings"]["minimize"]);
                settings.ConnectOnStart = bool.Parse(data["Settings"]["connect"]);
                settings.LastConfig = data["Settings"]["last"];
            }
            catch
            {
                CreateSettings();
            }
        }
        public void Write()
        {
            if (settings.Autorun == true) CheckTask();
            else DeleteTask();
            data["Settings"]["autorun"] = settings.Autorun.ToString();
            data["Settings"]["minimize"] = settings.MinimizeOnStart.ToString();
            data["Settings"]["connect"] = settings.ConnectOnStart.ToString();
            data["Settings"]["last"] = settings.LastConfig;
            parser.WriteFile(Global.SettingsFile, data);
        }
        private void AddToStartup()
        {
            DeleteTask();
            string Task = Properties.Resources.Task.Replace("PathToExecutable", CurrentPath());
            string tempTaskPath = Path.Combine(Path.GetTempPath(), "epexguitask.xml");
            File.WriteAllText(tempTaskPath, Task);
            Shell($@"schtasks /Create /xml ""{tempTaskPath}"" /tn ""\EpexGUI""");
            File.Delete(tempTaskPath);
        }
        public void CheckTask()
        {
            string output = Shell($@"schtasks /Query /xml /tn ""\EpexGUI""");
            if (!output.Contains(CurrentPath()))
            {
                AddToStartup();
            }
        }
        private void DeleteTask()
        {
            Shell($@"schtasks /Delete /tn ""\EpexGUI"" /F");
        }
        private string CurrentPath()
        {
            return Path.Combine(AppDomain.CurrentDomain.BaseDirectory, System.AppDomain.CurrentDomain.FriendlyName);
        }
        private void InitSettings()
        {
            settings.Autorun = false;
            settings.MinimizeOnStart = false;
            settings.ConnectOnStart = false;
            settings.LastConfig = string.Empty;
        }
        private string Shell(string command)
        {
            Process shell = new Process();
            ProcessStartInfo startInfo = new ProcessStartInfo();
            startInfo.Arguments = $@"/c {command}";
            startInfo.FileName = "cmd.exe";
            startInfo.Verb = "runas";
            startInfo.UseShellExecute = false;
            startInfo.RedirectStandardOutput = true;
            startInfo.CreateNoWindow = true;
            shell.StartInfo = startInfo;
            shell.Start();
            string output = shell.StandardOutput.ReadToEnd();
            shell.WaitForExit();
            return output;
        }
        private void CreateSettings()
        {
            try
            {
                File.Delete(Global.SettingsFile);
                File.Create(Global.SettingsFile).Close();
            }
            catch { }
            File.WriteAllLines(Global.SettingsFile, new string[]{ "[Settings]", "autorun = false", "minimize = false", "connect = false", "last = none"});
        }

    }
}
