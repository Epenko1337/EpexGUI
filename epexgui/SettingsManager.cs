using System;
using System.IO;
using IniParser;
using IniParser.Model;
using System.Diagnostics;

namespace epexgui
{
    internal class SettingsManager
    {
        public struct Settings
        {
            public bool AutoRun;
            public bool MinimizeOnStart;
            public bool ConnectOnStart;
            public bool EnableDebugLog;
            public bool VirtualAdapterMode;
            public string LastConfig;
        }

        public Settings AppSettings;
        private readonly FileIniDataParser _parser;
        private readonly IniData _data;
        public SettingsManager() 
        {
            if (!File.Exists(Global.SettingsFile)) CreateSettings();
            InitSettings();
            _parser = new FileIniDataParser();
            _data = _parser.ReadFile(Global.SettingsFile);
            Update();
        }

        public void Update()
        {
            try
            {
                AppSettings.AutoRun = bool.Parse(_data["Settings"]["autorun"]);
                AppSettings.MinimizeOnStart = bool.Parse(_data["Settings"]["minimize"]);
                AppSettings.ConnectOnStart = bool.Parse(_data["Settings"]["connect"]);
                AppSettings.EnableDebugLog = bool.Parse(_data["Settings"]["log"]);
                AppSettings.VirtualAdapterMode = bool.Parse(_data["Settings"]["mode"]);
                AppSettings.LastConfig = _data["Settings"]["last"];
            }
            catch
            {
                CreateSettings();
            }
        }
        public void Write()
        {
            if (AppSettings.AutoRun) CheckTask();
            else DeleteTask();
            _data["Settings"]["autorun"] = AppSettings.AutoRun.ToString();
            _data["Settings"]["minimize"] = AppSettings.MinimizeOnStart.ToString();
            _data["Settings"]["connect"] = AppSettings.ConnectOnStart.ToString();
            _data["Settings"]["log"] = AppSettings.EnableDebugLog.ToString();
            _data["Settings"]["mode"] = AppSettings.VirtualAdapterMode.ToString();
            _data["Settings"]["last"] = AppSettings.LastConfig;
            _parser.WriteFile(Global.SettingsFile, _data);
        }
        private void AddToStartup()
        {
            DeleteTask();
            var task = Properties.Resources.Task.Replace("PathToExecutable", CurrentPath());
            var tempTaskPath = Path.Combine(Path.GetTempPath(), "epexguitask.xml");
            File.WriteAllText(tempTaskPath, task);
            Shell($@"schtasks /Create /xml ""{tempTaskPath}"" /tn ""\EpexGUI""");
            File.Delete(tempTaskPath);
        }
        public void CheckTask()
        {
            var output = Shell(@"schtasks /Query /xml /tn ""\EpexGUI""");
            if (!output.Contains(CurrentPath()))
            {
                AddToStartup();
            }
        }
        private void DeleteTask()
        {
            Shell(@"schtasks /Delete /tn ""\EpexGUI"" /F");
        }
        private static string CurrentPath()
        {
            return Path.Combine(AppDomain.CurrentDomain.BaseDirectory, AppDomain.CurrentDomain.FriendlyName);
        }
        private void InitSettings()
        {
            AppSettings.AutoRun = false;
            AppSettings.MinimizeOnStart = false;
            AppSettings.ConnectOnStart = false;
            AppSettings.EnableDebugLog = false;
            AppSettings.VirtualAdapterMode = false;
            AppSettings.LastConfig = string.Empty;
        }
        private static string Shell(string command)
        {
            var shell = new Process();
            var startInfo = new ProcessStartInfo
            {
                Arguments = $@"/c {command}",
                FileName = "cmd.exe",
                Verb = "runas",
                UseShellExecute = false,
                RedirectStandardOutput = true,
                CreateNoWindow = true
            };
            shell.StartInfo = startInfo;
            shell.Start();
            var output = shell.StandardOutput.ReadToEnd();
            shell.WaitForExit();
            return output;
        }
        private static void CreateSettings()
        {
            try
            {
                File.Delete(Global.SettingsFile);
                File.Create(Global.SettingsFile).Close();
            }
            catch
            {
                // ignored
            }

            File.WriteAllLines(Global.SettingsFile, new[]{ @"[Settings]", @"autorun = false", @"minimize = false", @"connect = false", @"last = none"});
        }

    }
}
