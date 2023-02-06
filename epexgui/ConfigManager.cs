using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.IO;
using IniParser;
using IniParser.Model;
using System.Windows.Forms;

namespace epexgui
{
    struct WireguardConfig
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
        public string DNS;
    }

    internal class ConfigManager
    {
        public WireguardConfig Config;
        private FileIniDataParser parser;
        private IniData data;
        public string cfgpath;
        public string oldname;
        public string ConfigPathToName(string path)
        { return path.Remove(path.LastIndexOf('.'), 5).Substring(path.LastIndexOf('\\') + 1); }
        public ConfigManager(string path) 
        {
            cfgpath = path;
            parser = new FileIniDataParser();
            parser.Parser.Configuration.SkipInvalidLines = true;
            parser.Parser.Configuration.NewLineStr = "\n";
            data = parser.ReadFile(path);
            Config.ConfigName = ConfigPathToName(path);
            oldname = Config.ConfigName;
            Parser();
        }
        private void Parser()
        {
            try
            {
                Config.PrivateKey = data["Interface"]["PrivateKey"];
                Config.InterfaceAddress = data["Interface"]["Address"];
                Config.DNS = data["Interface"]["DNS"];
                Config.PublicKey = data["Peer"]["PublicKey"];
                Config.AllowedIPs = TrimSpaces(data["Peer"]["AllowedIPs"]);
                Config.AllowedApps = TrimSpaces(data["Peer"]["AllowedApps"]);
                Config.Endpoint = data["Peer"]["Endpoint"];
                Config.DisallowedIPs = TrimSpaces(data["Peer"]["DisallowedIPs"]);
                Config.DisallowedApps = TrimSpaces(data["Peer"]["DisallowedApps"]);
            }
            catch (Exception e) 
            {
                MessageBox.Show(e.Message, "Configuration parsing error", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        public void Write()
        {
            data["Interface"]["PrivateKey"] = Config.PrivateKey;
            data["Interface"]["Address"] = Config.InterfaceAddress;
            data["Interface"]["DNS"] = Config.DNS;
            data["Peer"]["PublicKey"] = Config.PublicKey;
            data["Peer"]["AllowedIPs"] = Config.AllowedIPs;
            data["Peer"]["AllowedApps"] = Config.AllowedApps;
            data["Peer"]["Endpoint"] = Config.Endpoint;
            data["Peer"]["DisallowedIPs"] = Config.DisallowedIPs;
            data["Peer"]["DisallowedApps"] = Config.DisallowedApps;
            if (Config.AllowedIPs == null) data["Peer"].RemoveKey("AllowedIPs");
            if (Config.AllowedApps == null) data["Peer"].RemoveKey("AllowedApps");
            if (Config.DisallowedIPs == null) data["Peer"].RemoveKey("DisallowedIPs");
            if (Config.DisallowedApps == null) data["Peer"].RemoveKey("DisallowedApps");
            File.WriteAllText(cfgpath, data.ToString()); //not using parser.write cuz it will add 3 extra bytes (EF BB BF) aka UTF8-BOM and wiresock will not able to parse this config
            try
            {
                File.Move(Path.Combine(Global.ConfigsFolder, oldname + ".conf"), Path.Combine(Global.ConfigsFolder, Config.ConfigName + ".conf"));
            }
            catch (Exception e)
            {
                MessageBox.Show(e.Message, "Unable to rename config", MessageBoxButtons.OK,MessageBoxIcon.Error);
            }
        }

        public string TrimSpaces(string text)
        {
            if (text != null)
            {
                return text.Replace(" ", "");
            }
            return text;
        }
    }
}
