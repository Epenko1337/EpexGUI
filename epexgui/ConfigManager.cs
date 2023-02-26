using System;
using System.IO;
using IniParser;
using IniParser.Model;
using System.Windows.Forms;

namespace epexgui
{
    internal struct WireguardConfig
    {
        public string ConfigName;
        public string PrivateKey;
        public string PublicKey;
        public string AllowedIPs;
        public string AllowedApps;
        public string InterfaceAddress;
        public string Endpoint;
        public string DisallowedIPs;
        public string DisallowedApps;
        public string Dns;
    }

    internal class ConfigManager
    {
        public WireguardConfig Config;
        private readonly IniData _data;
        public string ConfigPath;
        public string OldName;
        public string ConfigPathToName(string path)
        { return path.Remove(path.LastIndexOf('.'), 5).Substring(path.LastIndexOf('\\') + 1); }
        public ConfigManager(string path) 
        {
            ConfigPath = path;
            var parser = new FileIniDataParser();
            parser.Parser.Configuration.SkipInvalidLines = true;
            parser.Parser.Configuration.NewLineStr = "\n";
            _data = parser.ReadFile(path);
            Config.ConfigName = ConfigPathToName(path);
            OldName = Config.ConfigName;
            Parser();
        }
        private void Parser()
        {
            try
            {
                Config.PrivateKey = _data["Interface"]["PrivateKey"];
                Config.InterfaceAddress = _data["Interface"]["Address"];
                Config.Dns = _data["Interface"]["DNS"];
                Config.PublicKey = _data["Peer"]["PublicKey"];
                Config.AllowedIPs = TrimSpaces(_data["Peer"]["AllowedIPs"]);
                Config.AllowedApps = TrimSpaces(_data["Peer"]["AllowedApps"]);
                Config.Endpoint = _data["Peer"]["Endpoint"];
                Config.DisallowedIPs = TrimSpaces(_data["Peer"]["DisallowedIPs"]);
                Config.DisallowedApps = TrimSpaces(_data["Peer"]["DisallowedApps"]);
            }
            catch (Exception e) 
            {
                MessageBox.Show(e.Message, @"Configuration parsing error", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        public void Write()
        {
            _data["Interface"]["PrivateKey"] = Config.PrivateKey;
            _data["Interface"]["Address"] = Config.InterfaceAddress;
            _data["Interface"]["DNS"] = Config.Dns;
            _data["Peer"]["PublicKey"] = Config.PublicKey;
            _data["Peer"]["AllowedIPs"] = Config.AllowedIPs;
            _data["Peer"]["AllowedApps"] = Config.AllowedApps;
            _data["Peer"]["Endpoint"] = Config.Endpoint;
            _data["Peer"]["DisallowedIPs"] = Config.DisallowedIPs;
            _data["Peer"]["DisallowedApps"] = Config.DisallowedApps;
            if (Config.AllowedIPs == null) _data["Peer"].RemoveKey("AllowedIPs");
            if (Config.AllowedApps == null) _data["Peer"].RemoveKey("AllowedApps");
            if (Config.DisallowedIPs == null) _data["Peer"].RemoveKey("DisallowedIPs");
            if (Config.DisallowedApps == null) _data["Peer"].RemoveKey("DisallowedApps");
            File.WriteAllText(ConfigPath, _data.ToString()); //not using parser.write cuz it will add 3 extra bytes (EF BB BF) aka UTF8-BOM and wiresock will not able to parse this config
            try
            {
                File.Move(Path.Combine(Global.ConfigsFolder, OldName + ".conf"), Path.Combine(Global.ConfigsFolder, Config.ConfigName + ".conf"));
            }
            catch (Exception e)
            {
                MessageBox.Show(e.Message, @"Unable to rename config", MessageBoxButtons.OK,MessageBoxIcon.Error);
            }
        }

        public string TrimSpaces(string text)
        {
            return text?.Replace(" ", "");
        }
    }
}
