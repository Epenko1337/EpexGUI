using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Data;
using System.Drawing;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.Windows.Forms;
using System.IO;
using static System.Windows.Forms.VisualStyles.VisualStyleElement;

namespace epexgui
{
    public partial class Main : Form
    {
        public string ConfigInUse = string.Empty;
        private WiresockManager wiresock;
        public Main()
        {
            InitializeComponent();
            this.components = new System.ComponentModel.Container();
            this.contextMenu1 = new System.Windows.Forms.ContextMenu();
            this.menuItem1 = new System.Windows.Forms.MenuItem();
            this.contextMenu1.MenuItems.AddRange(
            new System.Windows.Forms.MenuItem[] { this.menuItem1 });
            this.menuItem1.Index = 0;
            this.menuItem1.Text = "Exit";
            this.menuItem1.Click += new System.EventHandler(this.menuItem1_Click);
            tray.ContextMenu = contextMenu1;
            tray.Icon = Properties.Resources.ico;
            UpdateConfigList();
            wiresock = new WiresockManager(LogBox);
            if (Global.setMan.settings.ConnectOnStart)
            {
                if (File.Exists(ConfigNameToPath(Global.setMan.settings.LastConfig)))
                {
                    Connect(Global.setMan.settings.LastConfig);
                }
                else
                {
                    MessageBox.Show("Last saved config not found", "Connect on start", MessageBoxButtons.OK, MessageBoxIcon.Error);
                }
            }
        }

        public void TrayIco()
        {
            if (wiresock.Connected)
            {
                tray.Icon = Properties.Resources.icoconnected;
            }
            else
            {
                tray.Icon = Properties.Resources.ico;
            }
        }

        private void menuItem1_Click(object Sender, EventArgs e)
        {
            Application.Exit();
        }

        private void Main_FormClosing(object sender, FormClosingEventArgs e)
        {
            if (e.CloseReason == CloseReason.UserClosing)
            {
                e.Cancel = true;
                Hide();
            }
        }

        private void EpexGUI_Click(object sender, EventArgs e)
        {
            Visible = true;
            ShowInTaskbar = true;
            Opacity = 100;
            this.Show();
        }

        public bool ConfigUsed(string name)
        {
            return ConfigInUse == name;
        }

        public void UpdateConfigList()
        {
            ConfigList.Items.Clear();
            string[] files = Directory.GetFiles(Global.ConfigsFolder);
            foreach (string file in files)
            {
                if (file.EndsWith(".conf"))
                {
                    if (ConfigUsed(ConfigPathToName(file)))
                    {
                        ConfigList.Items.Add(AddPrefix(ConfigPathToName(file), true));
                    }
                    else ConfigList.Items.Add(AddPrefix(ConfigPathToName(file), false));
                }
            }
        }

        public string ConfigPathToName(string path)
        { return path.Remove(path.LastIndexOf('.'), 5).Substring(path.LastIndexOf('\\') + 1); }
        public string ConfigNameToPath(string name)
        { return Path.Combine(Global.ConfigsFolder, Prefix(name, true) + ".conf"); }

        protected override void OnLoad(EventArgs e)
        {
            if (Global.setMan.settings.MinimizeOnStart)
            {
                Visible = false;
                ShowInTaskbar = false;
                Opacity = 0;
                Hide();
            }
            base.OnLoad(e);
        }

        private void RemoveConfig_Click(object sender, EventArgs e)
        {
            if (ConfigList.SelectedItem != null) 
            {
                string SelectedConf = Prefix(ConfigList.SelectedItem.ToString(), true);
                if (MessageBox.Show($"Do you really want to remove configuration {SelectedConf}?", "Confirmation", MessageBoxButtons.YesNo, MessageBoxIcon.Exclamation) == DialogResult.Yes)
                {
                    if (wiresock.Connected && ConfigUsed(SelectedConf))
                    {
                        Disconnect();
                    }
                    File.Delete(ConfigNameToPath(SelectedConf));
                    UpdateConfigList();
                }
            }
        }

        private void AddConfig_Click(object sender, EventArgs e)
        {
            var filePath = string.Empty;
            using (OpenFileDialog openFileDialog = new OpenFileDialog())
            {
                openFileDialog.Title = "Select configuration file";
                openFileDialog.InitialDirectory = "c:\\";
                openFileDialog.Filter = "Wireguard configuration files (*.conf)|*.conf";
                openFileDialog.RestoreDirectory = true;

                if (openFileDialog.ShowDialog() == DialogResult.OK)
                {
                    filePath = openFileDialog.FileName;
                    foreach (string file in Directory.GetFiles(Global.ConfigsFolder))
                    {
                        if (ConfigPathToName(file).ToLower() == ConfigPathToName(filePath).ToLower())
                        {
                            MessageBox.Show("Configuration with this name already exists", "Import error", MessageBoxButtons.OK, MessageBoxIcon.Error);
                            return;
                        }
                    }
                    File.Copy(filePath, Path.Combine(Global.ConfigsFolder, filePath.Substring(filePath.LastIndexOf('\\') + 1)));
                    UpdateConfigList();
                }
            }
        }

        public bool IsConfigExists(string ConfigName)
        {
            if (ConfigList.Items.Contains(AddPrefix(ConfigName, true)) || ConfigList.Items.Contains(AddPrefix(ConfigName, true)))
            {
                return true;
            }
            return false;
        }

        private void EditConfig_Click(object sender, EventArgs e)
        {
            if (ConfigList.SelectedItem != null)
            {
                string temp = ConfigList.SelectedItem.ToString().Substring(2);
                EditForm edit = new EditForm(temp);
                edit.ShowDialog();
                if (edit.successfull)
                {
                    if (ConfigUsed(temp))
                    {
                        Disconnect();
                        UpdateConfigList();
                        Connect(edit.lastname);
                    }
                    else
                    {
                        UpdateConfigList();
                    }
                }
            }
        }

        private void SettingsBtn_Click(object sender, EventArgs e)
        {
            Forms.SettingsForm settingsForm = new Forms.SettingsForm();
            settingsForm.ShowDialog();
        }

        public string Prefix(string config, bool remove = false)
        {
            if (config == null) return null;
            if (remove)
            {
                if (config[0] == '⚫' || config[0] == '⚪')
                {
                    return config.Substring(2);
                }
                return config;
            }
            string result = config;
            if (config[0] == '⚫')
            {
                return config.Replace('⚫', '⚪');
            }
            else
            {
                return config.Replace('⚪', '⚫');
            }
        }
        public string AddPrefix(string config, bool connected)
        {
            if (connected) return "⚫ " + config;
            return "⚪ " + config;
        }

        public enum ConnectionState
        {
            Connected,
            NotConnected,
            Connecting
        }

        public void UpdateState(ConnectionState state)
        {
            switch (state)
            {
                case ConnectionState.NotConnected:
                    ConnectButton.Enabled = true;
                    ConnectedToLabel.Text = "Not connected";
                    tray.Text = $"EpexGUI\nNot Connected";
                    TrayIco();
                    break;
                case ConnectionState.Connecting:
                    ConnectButton.Enabled = false;
                    ConnectedToLabel.Text = "Connecting...";
                    tray.Text = "EpexGUI\nConnecting...";
                    TrayIco();
                    break;
                case ConnectionState.Connected:
                    ConnectButton.Enabled = true;
                    ConfigManager cm = new ConfigManager(ConfigNameToPath(ConfigInUse));
                    ConnectedToLabel.Text = $"Connected to {cm.Config.Endpoint} ({cm.Config.ConfigName})";
                    tray.Text = $"EpexGUI\nConnected to {cm.Config.Endpoint} ({cm.Config.ConfigName})";
                    TrayIco();
                    break;
            }
        }

        public void Connect(string config)
        {
            if (wiresock.Connected)
            {
                Disconnect();
            }
            LogBox.Clear();
            config = Prefix(config, true);
            if (Global.setMan.settings.ConnectOnStart)
            {
                Global.setMan.settings.LastConfig = config;
                Global.setMan.Write();
            }
            ConfigInUse = config;
            ConfigList.Items[ConfigList.Items.IndexOf(AddPrefix(config, false))] = AddPrefix(config, true);
            UpdateState(ConnectionState.Connecting);
            wiresock.Connect(ConfigNameToPath(config), this);
            LabelUpdater.Start();
        }

        public void Disconnect()
        {
            if (ConfigList.SelectedItem!= null)
            {
                if (Prefix(ConfigList.SelectedItem.ToString(), true) == ConfigInUse) ConnectButton.Text = "Connect";
            }
            wiresock.Kill();
            UpdateState(ConnectionState.NotConnected);
            ConfigList.Items[ConfigList.Items.IndexOf(AddPrefix(ConfigInUse, true))] = AddPrefix(ConfigInUse, false);
            ConfigInUse = null;
        }

        private void ConnectButton_Click(object sender, EventArgs e)
        {
            if (ConnectButton.Text == "Disconnect")
            {
                Disconnect();
                ConnectButton.Text = "Connect";
            }
            else
            {
                if (ConfigList.SelectedItem != null)
                {
                    ConnectButton.Text = "Disconnect";
                    Connect(ConfigList.SelectedItem.ToString());
                }
            }
        }

        private void LabelUpdater_Tick(object sender, EventArgs e)
        {
            if (wiresock.Connected)
            {
                UpdateState(ConnectionState.Connected);
                LabelUpdater.Stop();
            }
        }

        private void ConfigList_SelectedIndexChanged(object sender, EventArgs e)
        {
            if (ConfigList.SelectedItem != null)
            {
                if (Prefix(ConfigList.SelectedItem.ToString(), true) == ConfigInUse)
                {
                    if (wiresock.Connected) ConnectButton.Text = "Disconnect";
                }
                else ConnectButton.Text = "Connect";
            }
        }
    }
}
