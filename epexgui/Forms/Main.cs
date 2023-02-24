using System;
using System.IO;
using System.Linq;
using System.Windows.Forms;

namespace epexgui.Forms
{
    /**
     * @brief The main form of the application.
     */
    public partial class Main : Form
    {
        /**
     * @brief The configuration file that is currently in use.
     */
        public string ConfigInUse = string.Empty;

        /**
         * @brief The manager that handles the Wireguard connections.
         */
        private readonly WiresockManager _wiresock;

        /**
         * @brief Initializes a new instance of the Main class.
         */
        public Main()
        {
            InitializeComponent();

            // Create the context menu.
            components = new System.ComponentModel.Container();
            contextMenu1 = new ContextMenu();
            menuItem1 = new MenuItem();
            contextMenu1.MenuItems.AddRange(new[] { menuItem1 });
            menuItem1.Index = 0;
            menuItem1.Text = @"Exit";
            menuItem1.Click += MenuItem1_Click;

            // Configure the system tray icon.
            tray.ContextMenu = contextMenu1;
            tray.Icon = Properties.Resources.ico;

            // Update the list of available configurations.
            UpdateConfigList();

            // Create a new WiresockManager instance.
            _wiresock = new WiresockManager(LogBox, Global.SetMan.AppSettings.VirtualAdapterMode);

            // Connect to the last used configuration, if required.
            if (!Global.SetMan.AppSettings.ConnectOnStart) return;
            if (File.Exists(ConfigNameToPath(Global.SetMan.AppSettings.LastConfig)))
            {
                Connect(Global.SetMan.AppSettings.LastConfig);
            }
            else
            {
                MessageBox.Show(@"Last saved config not found", @"Connect on start", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        /**
         * @brief Updates the system tray icon to reflect the current connection status.
         */
        public void TrayIco()
        {
            tray.Icon = _wiresock.Connected ? Properties.Resources.icoconnected : Properties.Resources.ico;
        }

        private static void MenuItem1_Click(object sender, EventArgs e)
        {
            Application.Exit();
        }

        private void Main_FormClosing(object sender, FormClosingEventArgs e)
        {
            if (e.CloseReason != CloseReason.UserClosing) return;
            e.Cancel = true;
            Hide();
        }

        private void EpexGUI_Click(object sender, EventArgs e)
        {
            Visible = true;
            ShowInTaskbar = true;
            Opacity = 100;
            Show();
        }

        public bool ConfigUsed(string name)
        {
            return ConfigInUse == name;
        }

        public void UpdateConfigList()
        {
            ConfigList.Items.Clear();
            var files = Directory.GetFiles(Global.ConfigsFolder);
            foreach (var file in files)
            {
                if (!file.EndsWith(".conf")) continue;
                ConfigList.Items.Add(ConfigUsed(ConfigPathToName(file))
                    ? AddPrefix(ConfigPathToName(file), true)
                    : AddPrefix(ConfigPathToName(file), false));
            }
        }

        public string ConfigPathToName(string path)
        { return path.Remove(path.LastIndexOf('.'), 5).Substring(path.LastIndexOf('\\') + 1); }
        public string ConfigNameToPath(string name)
        { return Path.Combine(Global.ConfigsFolder, Prefix(name, true) + ".conf"); }

        protected override void OnLoad(EventArgs e)
        {
            if (Global.SetMan.AppSettings.MinimizeOnStart)
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
            if (ConfigList.SelectedItem == null) return;
            var selectedConf = Prefix(ConfigList.SelectedItem.ToString(), true);
            if (MessageBox.Show($@"Do you really want to remove configuration {selectedConf}?", @"Confirmation",
                    MessageBoxButtons.YesNo, MessageBoxIcon.Exclamation) != DialogResult.Yes) return;
            if (_wiresock.Connected && ConfigUsed(selectedConf))
            {
                Disconnect();
            }
            File.Delete(ConfigNameToPath(selectedConf));
            UpdateConfigList();
        }

        private void AddConfig_Click(object sender, EventArgs e)
        {
            using (var openFileDialog = new OpenFileDialog())
            {
                openFileDialog.Title = @"Select configuration file";
                openFileDialog.InitialDirectory = "c:\\";
                openFileDialog.Filter = @"Wireguard configuration files (*.conf)|*.conf";
                openFileDialog.RestoreDirectory = true;

                if (openFileDialog.ShowDialog() != DialogResult.OK) return;
                var filePath = openFileDialog.FileName;
                if (Directory.GetFiles(Global.ConfigsFolder).Any(file =>
                        string.Equals(ConfigPathToName(file), ConfigPathToName(filePath), StringComparison.CurrentCultureIgnoreCase)))
                {
                    MessageBox.Show(@"Configuration with this name already exists", @"Import error",
                        MessageBoxButtons.OK, MessageBoxIcon.Error);
                    return;
                }
                File.Copy(filePath, Path.Combine(Global.ConfigsFolder,
                    filePath.Substring(filePath.LastIndexOf('\\') + 1)));
                UpdateConfigList();
            }
        }

        public bool IsConfigExists(string configName)
        {
            return ConfigList.Items.Contains(AddPrefix(configName, true)) ||
                   ConfigList.Items.Contains(AddPrefix(configName, true));
        }

        private void EditConfig_Click(object sender, EventArgs e)
        {
            if (ConfigList.SelectedItem == null) return;
            var temp = ConfigList.SelectedItem.ToString().Substring(2);
            var edit = new EditForm(temp);
            edit.ShowDialog();
            if (!edit.successfull) return;
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

        private void SettingsBtn_Click(object sender, EventArgs e)
        {
            var settingsForm = new SettingsForm();

            // set the owner of the child form to the main form instance
            settingsForm.Owner = this;

            settingsForm.ShowDialog();
        }

        public string Prefix(string config, bool remove = false)
        {
            if (config == null) return null;
            if (!remove) return config[0] == '⚫' ? config.Replace('⚫', '⚪') : config.Replace('⚪', '⚫');
            if (config[0] == '⚫' || config[0] == '⚪')
            {
                return config.Substring(2);
            }
            return config;

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
                    ConnectedToLabel.Text = @"Not connected";
                    tray.Text = @"EpexGUI" + Environment.NewLine + @"Not Connected";
                    TrayIco();
                    break;
                case ConnectionState.Connecting:
                    ConnectButton.Enabled = false;
                    ConnectedToLabel.Text = @"Connecting...";
                    tray.Text = @"EpexGUI" + Environment.NewLine + @"Connecting...";
                    TrayIco();
                    break;
                case ConnectionState.Connected:
                    ConnectButton.Enabled = true;
                    var cm = new ConfigManager(ConfigNameToPath(ConfigInUse));
                    ConnectedToLabel.Text = $@"Connected to {cm.Config.Endpoint} ({cm.Config.ConfigName})";
                    tray.Text = @"EpexGUI" + Environment.NewLine + $@"Connected to {cm.Config.Endpoint} ({cm.Config.ConfigName})";
                    TrayIco();
                    break;
                default:
                    throw new ArgumentOutOfRangeException(nameof(state), state, null);
            }
        }

        /**
         * @brief Connects to the specified configuration.
         * @param config The name of the configuration to connect to.
         */
        public void Connect(string config)
        {
            // Disconnect from the current configuration, if necessary.
            if (_wiresock.Connected)
            {
                Disconnect();
            }

            // Clear the log box and update the configuration in use.
            LogBox.Clear();
            config = Prefix(config, true);

            // Save the last used configuration, if required.
            if (Global.SetMan.AppSettings.ConnectOnStart)
            {
                Global.SetMan.AppSettings.LastConfig = config;
                Global.SetMan.Write();
            }
            ConfigInUse = config;

            // Update the list of configurations and set the connection state to "Connecting".
            ConfigList.Items[ConfigList.Items.IndexOf(AddPrefix(config, false))] = AddPrefix(config, true);
            UpdateState(ConnectionState.Connecting);

            // Connect to the specified configuration using the WiresockManager instance.
            _wiresock.Connect(ConfigNameToPath(config));

            // Start the label updater.
            LabelUpdater.Start();
        }

        /**
         * @brief Disconnects from the current configuration.
         */
        public async void Disconnect()
        {
            // If the currently selected configuration is in use, update the Connect button text.
            if (ConfigList.SelectedItem != null)
            {
                if (Prefix(ConfigList.SelectedItem.ToString(), true) == ConfigInUse)
                {
                    ConnectButton.Text = @"Connect";
                }
            }

            // Disconnect from the current configuration using the WiresockManager instance and update the connection state.
            await _wiresock.DisconnectAsync();
            UpdateState(ConnectionState.NotConnected);
            ConfigList.Items[ConfigList.Items.IndexOf(AddPrefix(ConfigInUse, true))] = AddPrefix(ConfigInUse, false);
            ConfigInUse = null;
        }

        private void ConnectButton_Click(object sender, EventArgs e)
        {
            if (ConnectButton.Text == @"Disconnect")
            {
                Disconnect();
                ConnectButton.Text = @"Connect";
            }
            else
            {
                if (ConfigList.SelectedItem == null) return;
                ConnectButton.Text = @"Disconnect";
                Connect(ConfigList.SelectedItem.ToString());
            }
        }

        private void LabelUpdater_Tick(object sender, EventArgs e)
        {
            if (!_wiresock.Connected) return;
            UpdateState(ConnectionState.Connected);
            LabelUpdater.Stop();
        }

        private void ConfigList_SelectedIndexChanged(object sender, EventArgs e)
        {
            if (ConfigList.SelectedItem == null) return;
            if (Prefix(ConfigList.SelectedItem.ToString(), true) == ConfigInUse)
            {
                if (_wiresock.Connected) ConnectButton.Text = @"Disconnect";
            }
            else ConnectButton.Text = @"Connect";
        }

        public void EnableDebugLog(bool enableLogChecked)
        {
            _wiresock.EnableDebugLog(enableLogChecked);
        }

        public void SetAdapterMode(bool enableAdapterMode)
        {
            _wiresock.SetAdapterMode(enableAdapterMode);
        }
    }
}
