using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Windows.Forms;
using WireSockUI.Config;
using WireSockUI.Extensions;
using WireSockUI.Native;
using WireSockUI.Properties;
using static WireSockUI.Native.WireguardBoosterExports;

namespace WireSockUI.Forms
{
    /**
     * @brief The main form of the application.
     */
    public partial class frmMain : Form
    {
        public enum ConnectionState
        {
            Connected,
            Disconnected,
            Connecting
        }

        /**
         * @brief The manager that handles the Wireguard connections.
         */
        private readonly WireSockManager _wiresock;

        /**
         * @brief Initializes a new instance of the Main class.
         */
        public frmMain()
        {
            InitializeComponent();

            // Configure icons
            this.Icon = Resources.ico;
            trayIcon.Icon = Resources.ico;
            cmiStatus.Image = BitmapExtensions.DrawCircle(16, 15, Brushes.DarkGray);

            // Populate menu items with Windows supplied icons
            ddmAddTunnel.Image = WindowsIcons.GetWindowsIcon(WindowsIcons.Icons.Addtunnel, 16).ToBitmap();
            mniImportTunnel.Image = WindowsIcons.GetWindowsIcon(WindowsIcons.Icons.OpenTunnel, 16).ToBitmap();
            mniNewTunnel.Image = WindowsIcons.GetWindowsIcon(WindowsIcons.Icons.NewTunnel, 16).ToBitmap();
            mniDeleteTunnel.Image = WindowsIcons.GetWindowsIcon(WindowsIcons.Icons.DeleteTunnel, 16).ToBitmap();
            mniSettings.Image = WindowsIcons.GetWindowsIcon(WindowsIcons.Icons.Settings, 16).ToBitmap();

            // Populate profile image list with Windows supplied icons
            imlProfiles.Images.Clear();
            imlProfiles.Images.Add("disconnected", WindowsIcons.GetWindowsIcon(WindowsIcons.Icons.DisconnectedTunnel, 24));
            imlProfiles.Images.Add("connected", WindowsIcons.GetWindowsIcon(WindowsIcons.Icons.ConnectedTunnel, 24));
            imlProfiles.Images.Add("connecting", WindowsIcons.GetWindowsIcon(WindowsIcons.Icons.ConnectingTunnel, 24));

            // Ensure the profile list rows fill the entire width, but no scrollbar appears
            lstProfiles.Columns[0].Width = lstProfiles.Size.Width - 4;

            LogWindowResize(lstLog, EventArgs.Empty);

            // Update the list of available configurations.
            LoadProfiles();

            // Create a new WireSockManager instance.
            _wiresock = new WireSockManager(lstLog, this.LogMessage);
        }

        protected override void OnLoad(EventArgs e)
        {
            base.OnLoad(e);

            if (Properties.Settings.Default.AutoMinimize)
            {
                this.WindowState = FormWindowState.Minimized;
                this.ShowInTaskbar = false;
                Hide();
            }

            if (lstProfiles.Items.ContainsKey(Properties.Settings.Default.LastProfile))
                lstProfiles.Items[Properties.Settings.Default.LastProfile].Selected = true;

            // Connect to the last used configuration, if required.
            if (!Properties.Settings.Default.AutoConnect) return;

            if (lstProfiles.Items.ContainsKey(Properties.Settings.Default.LastProfile))
                ProfileStateChange(lstProfiles, EventArgs.Empty);
            else
                MessageBox.Show(Resources.LastProfileNotFound, Resources.DialogAutoConnect, MessageBoxButtons.OK, MessageBoxIcon.Error);
        }

        private void menuExit_Click(object sender, EventArgs e)
        {
            Application.Exit();
        }

        private void Main_FormClosing(object sender, FormClosingEventArgs e)
        {
            if (e.CloseReason != CloseReason.UserClosing) return;
            e.Cancel = true;
            Hide();
        }

        private void ShowForm(object sender, EventArgs e)
        {
            Show();
            this.WindowState = FormWindowState.Normal;
        }

        private void MinimizeForm(object sender, EventArgs e)
        {
            if (this.WindowState == FormWindowState.Minimized)
                Hide();
        }

        /// <summary>
        /// Reload profile list and optionally pre-select a 
        /// </summary>
        /// <param name="selectedProfile">Optional profile to automatically select</param>
        public void LoadProfiles(String selectedProfile = "")
        {
            lstProfiles.Items.Clear();

            List<string> profiles = Profile.GetProfiles().ToList();
            profiles.Sort();

            lstProfiles.Items.AddRange(profiles
                    .Select(p => new ListViewItem(p, "disconnected") { Name = p }).ToArray());

            // Clear any previously loaded tunnels
            for (int i = mnuContext.Items.Count - 1; i >= 0; i--)
            {
                ToolStripItem item = mnuContext.Items[i];

                if (String.Equals(item.Tag, "tunnel"))
                    mnuContext.Items.Remove(item);
            }

            if (profiles.Any())
            {
                int insertIndex = mnuContext.Items.IndexOf(cmiSepTunnels);

                mnuContext.Items.Insert(insertIndex + 1, new ToolStripSeparator() { Tag = "tunnel" });

                foreach (string profile in profiles.Reverse<string>())
                {
                    ToolStripMenuItem item = new ToolStripMenuItem(profile) { Tag = "tunnel", Text = profile };
                    item.Click += (s, e) =>
                    {
                        lstProfiles.Items[item.Text].Selected = true;
                        ProfileStateChange(lstProfiles, EventArgs.Empty);
                    };

                    mnuContext.Items.Insert(insertIndex + 1, item);
                }
            }

            if (lstProfiles.Items.Count > 0)
            {
                if (!String.IsNullOrWhiteSpace(selectedProfile))
                {
                    ListViewItem profile = lstProfiles.Items[selectedProfile];

                    if (profile != null)
                    {
                        profile.Selected = true;
                        return;
                    }
                }

                lstProfiles.Items[0].Selected = true;
            }
        }

        /**
         * @brief Disconnects from the current configuration.
         */
        public void Disconnect()
        {
            // Disconnect from the current configuration using the WireSockManager instance and update the connection state.
            UpdateState(ConnectionState.Disconnected);
            _wiresock.Disconnect();
        }

        private void NewProfile(object sender, EventArgs e)
        {
            using (Form form = new frmEdit())
            {
                if (form.ShowDialog() == DialogResult.OK)
                    LoadProfiles();
            }
        }

        private void AddProfile(object sender, EventArgs e)
        {
            using (OpenFileDialog openFileDialog = new OpenFileDialog())
            {
                openFileDialog.Title = Resources.DialogOpenFileTitle;
                openFileDialog.InitialDirectory = Environment.GetFolderPath(Environment.SpecialFolder.Recent);
                openFileDialog.Filter = Resources.DialogOpenFileFilter;
                openFileDialog.RestoreDirectory = true;

                if (openFileDialog.ShowDialog() != DialogResult.OK)
                    return;

                String filePath = openFileDialog.FileName;

                String profileName = Path.GetFileNameWithoutExtension(filePath);

                if (Profile.GetProfiles().Contains(profileName, StringComparer.OrdinalIgnoreCase))
                {
                    MessageBox.Show(String.Format(Resources.AddProfileExistsMsg, profileName), Resources.AddProfileExistsTitle,
                        MessageBoxButtons.OK, MessageBoxIcon.Error);
                    return;
                }

                File.Copy(filePath, Profile.GetProfilePath(profileName));
                LoadProfiles();
            }
        }

        private void EditProfile(object sender, EventArgs e)
        {
            String profile = lstProfiles.SelectedItems[0].Text;

            using (frmEdit form = new frmEdit(profile))
            {
                if (form.ShowDialog() == DialogResult.OK)
                {
                    LoadProfiles(form.ReturnValue);

                    if (_wiresock.Connected && _wiresock.ProfileName == profile)
                        ProfileStateChange(lstProfiles, EventArgs.Empty);
                }
            }
        }

        private void DeleteProfile(object sender, EventArgs e)
        {
            String selectedConf = lstProfiles.SelectedItems[0].Text;

            if (MessageBox.Show(String.Format(Resources.DeleteProfileConfirmTitle, selectedConf), Resources.DeleteProfileConfirmTitle,
                    MessageBoxButtons.YesNo, MessageBoxIcon.Exclamation) != DialogResult.Yes)
                return;

            if (_wiresock.Connected && _wiresock.ProfileName == selectedConf)
                Disconnect();

            File.Delete(Profile.GetProfilePath(selectedConf));
            LoadProfiles();
        }

        private void Settings(object sender, EventArgs e)
        {
            using (frmSettings form = new frmSettings())
            {
                // set the owner of the child form to the main form instance
                form.Owner = this;

                if (form.ShowDialog() == DialogResult.OK)
                    _wiresock.LogLevel = _wiresock.LogLevelSetting;
            }
        }

        public void UpdateState(ConnectionState state)
        {
            Button btnActivate = layoutInterface.Controls["btnActivate"] as Button;
            PictureBox imgStatus = layoutInterface.Controls.Find("imgStatus", true).FirstOrDefault() as PictureBox;
            TextBox txtStatus = layoutInterface.Controls.Find("txtStatus", true).FirstOrDefault() as TextBox;
            TextBox txtAddresses = layoutInterface.Controls["txtAddresses"] as TextBox;

            switch (state)
            {
                case ConnectionState.Connecting:
                    btnActivate.Text = Resources.ButtonActivating;
                    btnActivate.Enabled = false;
                    imgStatus.Focus();

                    lstProfiles.Items[_wiresock.ProfileName].ImageKey = "connecting";

                    // Start the label updater
                    tmrConnect.Start();
                    trayIcon.Text = Resources.TrayActivating;
                    break;
                case ConnectionState.Connected:
                    btnActivate.Text = Resources.ButtonActive;
                    btnActivate.Enabled = true;

                    imgStatus.Image = WindowsIcons.GetWindowsIcon(WindowsIcons.Icons.Activated, 16).ToBitmap();
                    txtStatus.Text = Resources.InterfaceStatusActive;

                    trayIcon.Icon = Resources.ico.SuperImpose(64, WindowsIcons.Icons.Activated, 48, 24);
                    trayIcon.Text = Resources.TrayActive;

                    cmiStatus.Image = imgStatus.Image;
                    cmiStatus.Text = Resources.ContextMenuActive;

                    cmiAddresses.Text = txtAddresses.Text;
                    cmiAddresses.Visible = true;

                    foreach (ToolStripItem item in mnuContext.Items)
                    {
                        ToolStripMenuItem menuItem = item as ToolStripMenuItem;

                        if (menuItem != null && String.Equals(menuItem.Tag, "tunnel"))
                            menuItem.Checked = (menuItem.Text == _wiresock.ProfileName);
                    }

                    lstProfiles.Items[_wiresock.ProfileName].ImageKey = "connected";

                    Properties.Settings.Default.LastProfile = _wiresock.ProfileName;
                    Properties.Settings.Default.Save();

                    gbxState.Visible = true;
                    tmrStats.Start();

                    Notifications.Notify(Resources.ToastActiveTitle, String.Format(Resources.ToastActiveMessage, _wiresock.ProfileName));
                    break;
                case ConnectionState.Disconnected:
                    btnActivate.Text = Resources.ButtonInactive;
                    btnActivate.Enabled = true;

                    imgStatus.Image = BitmapExtensions.DrawCircle(16, 15, Brushes.DarkGray);
                    txtStatus.Text = Resources.InterfaceStatusInactive;

                    trayIcon.Icon = Resources.ico;
                    trayIcon.Text = Resources.TrayInactive;

                    cmiStatus.Image = imgStatus.Image;
                    cmiStatus.Text = Resources.ContextMenuInactive;
                    
                    cmiAddresses.Text = String.Empty;
                    cmiAddresses.Visible = false;

                    foreach (ToolStripItem item in mnuContext.Items)
                    {
                        ToolStripMenuItem menuItem = item as ToolStripMenuItem;

                        if (menuItem != null && String.Equals(menuItem.Tag, "tunnel"))
                            menuItem.Checked = false;
                    }

                    lstProfiles.Items[_wiresock.ProfileName].ImageKey = "disconnected";

                    gbxState.Visible = false;
                    tmrStats.Stop();

                    Notifications.Notify(Resources.ToastInactiveTitle, String.Format(Resources.ToastInactiveMessage, _wiresock.ProfileName));
                    break;
            }
        }

        private void ProfileStateChange(object sender, EventArgs e)
        {
            if (lstProfiles.SelectedItems.Count == 0) return;

            if (_wiresock.Connected)
            {
                UpdateState(ConnectionState.Disconnected);
                Disconnect();
            }
            else
            {
                _wiresock.TunnelMode = Properties.Settings.Default.UseAdapter ? WireSockManager.Mode.VirtualAdapter : WireSockManager.Mode.Transparent;

                string profile = lstProfiles.SelectedItems[0].Text;

                if (_wiresock.Connect(profile))
                    UpdateState(ConnectionState.Connecting);
            }
        }

        private void timerConnect(object sender, EventArgs e)
        {
            if (!_wiresock.Connected)
                return;

            UpdateState(ConnectionState.Connected);
            tmrConnect.Stop();
        }

        #region Layout

        private void ProfileSelectionChange(object sender, ListViewItemSelectionChangedEventArgs e)
        {
            TextBox addRow(TableLayoutPanel container, string name, string key, string value, bool isOptional = false, Bitmap icon = null)
            {
                if (isOptional && String.IsNullOrWhiteSpace(value))
                    return null;

                container.RowStyles.Add(new RowStyle(SizeType.AutoSize));
                container.RowCount = container.RowStyles.Count;

                Label label = new Label()
                { 
                    Dock = DockStyle.Fill,
                    Name = $"lbl{name}",
                    Height = 18,
                    Margin = new Padding(0, 0, 0, 0),
                    Padding = new Padding(0),
                    TextAlign = ContentAlignment.TopRight,
                    Text = $"{key}:"
                };

                container.Controls.Add(label, 0, container.RowCount - 1);

                if (icon != null)
                {
                    TableLayoutPanel panel = new TableLayoutPanel()
                    {
                        AutoSize = true,
                        AutoSizeMode = AutoSizeMode.GrowAndShrink,
                        Dock = DockStyle.Fill,
                        Margin = new Padding(0),
                        Padding = new Padding(0),

                    };

                    panel.RowStyles.Add(new RowStyle(SizeType.Absolute, 20));
                    panel.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 20));
                    panel.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));

                    panel.RowCount = panel.RowStyles.Count;
                    panel.ColumnCount = panel.ColumnStyles.Count;

                    panel.Controls.Add(new PictureBox()
                    {
                        Dock = DockStyle.Fill,
                        Height = 16,
                        Image = icon,
                        Margin = new Padding(0),
                        Name = $"img{name}",
                        Padding = new Padding(0),
                        Width = 16,
                    }, 0, 0);

                    panel.Controls.Add(new TextBox()
                    {
                        BorderStyle = BorderStyle.None,
                        BackColor = Color.FromKnownColor(KnownColor.Control),
                        Dock = DockStyle.Fill,
                        Margin = new Padding(0),
                        Multiline = true,
                        Name = $"txt{name}",
                        Padding = new Padding(0),
                        ReadOnly = true,
                        Text = value
                    });

                    container.Controls.Add(panel, 1, container.RowCount - 1);
                }
                else
                {
                    TextBox textBox = new TextBox()
                    {
                        BorderStyle = BorderStyle.None,
                        BackColor = Color.FromKnownColor(KnownColor.Control),
                        Dock = DockStyle.Fill,
                        Margin = new Padding(0),
                        Multiline = true,
                        Name = $"txt{name}",
                        Padding = new Padding(0),
                        ReadOnly = true,
                        Text = value
                    };

                    container.Controls.Add(textBox, 1, container.RowCount - 1);
                }

                return null;
            }

            gbxInterface.Visible = false;
            gbxInterface.Text = string.Empty;
            layoutInterface.Controls.Clear();
            layoutInterface.RowStyles.Clear();

            gbxPeer.Visible = false;
            layoutPeer.Controls.Clear();
            layoutPeer.RowStyles.Clear();

            gbxState.Visible = false;
            layoutState.Controls.Clear();
            layoutState.RowStyles.Clear();

            if (e.IsSelected)
            {
                String selectedConf = lstProfiles.SelectedItems[0].Text;

                try
                {
                    Profile profile = Profile.LoadProfile(selectedConf);

                    // Interface Panel
                    gbxInterface.Text = String.Format(Resources.InterfaceTitle, selectedConf);

                    addRow(layoutInterface, "Status", Resources.InterfaceStatus, Resources.InterfaceStatusInactive, false, BitmapExtensions.DrawCircle(16, 15, Brushes.DarkGray));
                    addRow(layoutInterface, "PrivateKey", Resources.InterfacePublicKey, profile.PublicKey);
                    addRow(layoutInterface, "MTU", Resources.InterfaceMTU, profile.MTU, true);
                    addRow(layoutInterface, "Addresses", Resources.InterfaceAddresses, profile.Address);

                    layoutInterface.RowStyles.Add(new RowStyle(SizeType.Absolute, 10));
                    layoutInterface.RowStyles.Add(new RowStyle(SizeType.Absolute, 35));
                    layoutInterface.RowCount = layoutInterface.RowStyles.Count;

                    Button btnActivate = new Button()
                    {
                        AutoSize = true,
                        AutoSizeMode = AutoSizeMode.GrowAndShrink,
                        Dock = DockStyle.Left,
                        Name = "btnActivate",
                        Text = "Activate"
                    };

                    btnActivate.Click += ProfileStateChange;

                    layoutInterface.Controls.Add(btnActivate, 1, layoutInterface.RowCount - 1);

                    layoutInterface.RowStyles.Add(new RowStyle(SizeType.AutoSize));
                    gbxInterface.Visible = true;

                    LayoutPanelResize(layoutInterface, EventArgs.Empty);

                    // Peer Panel
                    addRow(layoutPeer, "PublicKey", Resources.PeerPublicKey, profile.PeerKey);
                    addRow(layoutPeer, "PresharedKey", Resources.PeerPresharedKey, !String.IsNullOrWhiteSpace(profile.PresharedKey) ? Resources.PeerPresharedKeyValue : String.Empty, true);
                    addRow(layoutPeer, "AllowedIPs", Resources.PeerAllowedIPs, profile.AllowedIPs);
                    addRow(layoutPeer, "Endpoint", Resources.PeerEndpoint, profile.Endpoint);
                    addRow(layoutPeer, "PersistentKeepAlive", Resources.PeerPersistentKeepAlive, profile.PersistentKeepAlive, true);

                    layoutPeer.RowStyles.Add(new RowStyle(SizeType.Absolute, 20));

                    addRow(layoutPeer, "AllowedApps", Resources.PeerAllowedApps, profile.AllowedApps, true);
                    addRow(layoutPeer, "DisallowedApps", Resources.PeerDisallowedApps, profile.DisallowedApps, true);
                    addRow(layoutPeer, "DisallowedIPs", Resources.PeerDisallowedIPs, profile.DisallowedIPs, true);
                    addRow(layoutPeer, "Socks5Proxy", Resources.PeerSocks5Proxy, profile.Socks5Proxy, true);
                    addRow(layoutPeer, "Socks5Username", Resources.PeerSocks5Username, profile.Socks5ProxyUsername, true);
                    addRow(layoutPeer, "Socks5Password", Resources.PeerSocks5Password, !String.IsNullOrWhiteSpace(profile.Socks5ProxyPassword) ? Resources.PeerSocks5PasswordValue : String.Empty, true);

                    if (!String.IsNullOrWhiteSpace(profile.AllowedApps) ||
                        !String.IsNullOrWhiteSpace(profile.DisallowedApps) ||
                        !String.IsNullOrWhiteSpace(profile.DisallowedIPs) ||
                        !String.IsNullOrWhiteSpace(profile.Socks5Proxy))
                        layoutPeer.RowStyles.Add(new RowStyle(SizeType.Absolute, 20));

                    layoutPeer.RowStyles.Add(new RowStyle(SizeType.AutoSize));
                    gbxPeer.Visible = true;

                    LayoutPanelResize(layoutPeer, EventArgs.Empty);

                    // Layout state                    
                    addRow(layoutState, "Handshake", Resources.StateHandshake, "");
                    addRow(layoutState, "Transfer", Resources.StateTransfer, "");
                    addRow(layoutState, "RTT", Resources.StateRTT, "");
                    addRow(layoutState, "Loss", Resources.StateLoss, "");

                    layoutState.RowStyles.Add(new RowStyle(SizeType.AutoSize));
                }
                catch (Exception ex)
                {
                    MessageBox.Show(ex.Message, Resources.ProfileError, MessageBoxButtons.OK, MessageBoxIcon.Error);
                }
            }

            mniDeleteTunnel.Enabled = e.IsSelected;
            btnEdit.Enabled = e.IsSelected;
        }

        private void UpdateStats(object sender, EventArgs e)
        {
            if (_wiresock.Connected)
            {
                WgbStats stats = _wiresock.GetState();

                TextBox txtHandshake = layoutState.Controls["txtHandshake"] as TextBox;
                TextBox txtTransfer = layoutState.Controls["txtTransfer"] as TextBox;
                TextBox txtRTT = layoutState.Controls["txtRTT"] as TextBox;
                TextBox txtLoss = layoutState.Controls["txtLoss"] as TextBox;

                if (txtHandshake != null)
                    txtHandshake.Text = stats.time_since_last_handshake.AsTimeAgo();
                
                if (txtTransfer != null)
                    txtTransfer.Text = String.Format(Resources.StateTransferValue,
                        stats.rx_bytes.AsHumanReadable(),
                        stats.tx_bytes.AsHumanReadable());

                if (txtRTT != null)
                    txtRTT.Text = String.Format(Resources.StateRTTValue, stats.estimated_rtt);

                if (txtLoss != null)
                    txtLoss.Text = String.Format(Resources.StateLossValue, stats.estimated_loss * 100);
            }
        }

        private void LayoutPanelResize(object sender, EventArgs e)
        {
            TableLayoutPanel panel = sender as TableLayoutPanel;
            if (panel.Width > 0)
                panel.ColumnStyles[1].Width = panel.Width - panel.ColumnStyles[0].Width;

            foreach (Control control in panel.Controls)
            {
                if (control is TextBox)
                {
                    TextBox textBox = control as TextBox;

                    int textHeight = TextRenderer.MeasureText(
                        textBox.Text,
                        textBox.Font,
                        new Size(
                            textBox.ClientSize.Width,
                            textBox.ClientSize.Height),
                        TextFormatFlags.WordBreak | TextFormatFlags.TextBoxControl).Height;

                    textBox.Height = textHeight + 0 + (textHeight / textBox.Font.Height);
                }
            }
        }
        #endregion

        #region LogWindow

        private void LogWindowResize(object sender, EventArgs e)
        {
            // Ensure the log list rows fill the entire width, but no scrollbar appears
            lstLog.Columns[1].Width = lstLog.Columns[0].Width + lstLog.Size.Width - 4;
        }

        private void LogDrawHeader(object sender, DrawListViewItemEventArgs e)
        {
            e.DrawDefault = true;

            if ((e.ItemIndex % 2) == 1)
            {
                e.Item.BackColor = Color.FromArgb(
                    (int)(e.Item.BackColor.R * 0.95),
                    (int)(e.Item.BackColor.G * 0.95),
                    (int)(e.Item.BackColor.B * 0.95));

                e.Item.UseItemStyleForSubItems = true;
            }
        }

        private void LogDrawColumnHeader(object sender, DrawListViewColumnHeaderEventArgs e)
        {
            e.DrawDefault = true;
        }

        private void LogMessage(WireSockManager.LogMessage logMessage)
        {
            lstLog.Items.Add(new ListViewItem(new string[] { logMessage.Timestamp.ToString(Resources.LogTimestampFormat), logMessage.Message }));
        }

        #endregion

    }
}
