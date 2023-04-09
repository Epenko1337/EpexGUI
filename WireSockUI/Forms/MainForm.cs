using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Threading;
using System.Windows.Forms;
using WireSockUI.Config;
using WireSockUI.Extensions;
using WireSockUI.Native;
using WireSockUI.Properties;
using static System.Windows.Forms.AxHost;
using static WireSockUI.Native.WireguardBoosterExports;

namespace WireSockUI.Forms
{
    /**
     * @brief The main form of the application.
     */
    public partial class frmMain : Form
    {
        public enum ConnectionState { Connecting, Connected, Disconnected }

        /**
         * @brief The manager that handles the Wireguard connections.
         */
        private readonly WireSockManager _wiresock;
        private readonly BackgroundWorker _tunnelConnectionWorker;
        private readonly BackgroundWorker _tunnelStateWorker;

        /// <summary>
        /// Initialize a <see cref="T:BackgroundWorker" /> which retrieves tunnel connecting / connecting state and updates it in the UI
        /// </summary>
        /// <returns><see cref="T:BackgroundWorker" /></returns>
        private BackgroundWorker InitializeTunnelConnectionWorker()
        {
            BackgroundWorker worker = new BackgroundWorker()
            {
                WorkerSupportsCancellation = true,
                WorkerReportsProgress = true
            };

            worker.DoWork += (object s, DoWorkEventArgs e) =>
            {

                do
                {
                    Thread.Sleep(500);
                    worker.ReportProgress(0, _wiresock.Connected);
                } while (!worker.CancellationPending && !_wiresock.Connected);
            };

            worker.ProgressChanged += (object s, ProgressChangedEventArgs e) =>
            {
                if ((bool)e.UserState)
                    UpdateState(ConnectionState.Connected);
            };

            return worker;
        }

        /// <summary>
        /// Initialize a <see cref="T:BackgroundWorker" /> which retrieves the connected tunnel state and updates it in the UI
        /// </summary>
        /// <returns><see cref="T:BackgroundWorker" /></returns>
        private BackgroundWorker InitTunnelStateWorker()
        {
            BackgroundWorker worker = new BackgroundWorker()
            {
                WorkerSupportsCancellation = true,
                WorkerReportsProgress = true
            };

            worker.DoWork += (object s, DoWorkEventArgs e) =>
            {
                while (!worker.CancellationPending)
                {
                    Thread.Sleep(1000);

                    Debug.WriteLine("Doing work.");

                    if (_wiresock.Connected)
                    {
                        WgbStats stats = _wiresock.GetState();
                        worker.ReportProgress(0, stats);
                    }
                }
            };

            worker.ProgressChanged += (object s, ProgressChangedEventArgs e) =>
            {
                if (e.UserState is WgbStats stats)
                {
                    if (layoutState.Controls["txtHandshake"] is TextBox txtHandshake)
                        txtHandshake.Text = stats.time_since_last_handshake.AsTimeAgo();

                    if (layoutState.Controls["txtTransfer"] is TextBox txtTransfer)
                        txtTransfer.Text = String.Format(Resources.StateTransferValue,
                            stats.rx_bytes.AsHumanReadable(),
                            stats.tx_bytes.AsHumanReadable());

                    if (layoutState.Controls["txtRTT"] is TextBox txtRTT)
                        txtRTT.Text = String.Format(Resources.StateRTTValue, stats.estimated_rtt);

                    if (layoutState.Controls["txtLoss"] is TextBox txtLoss)
                        txtLoss.Text = String.Format(Resources.StateLossValue, stats.estimated_loss * 100);
                }
            };

            return worker;
        }

        /// <summary>
        /// Reload profile list and optionally pre-select a profile
        /// </summary>
        /// <param name="selectedProfile">Optional profile to automatically select</param>
        private void LoadProfiles(String selectedProfile = "")
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
                        OnProfileClick(lstProfiles, EventArgs.Empty);
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

        /// <summary>
        /// Update the connection state of the WireSock tunnel
        /// </summary>
        /// <param name="state"><see cref="T:ConnectionState"/></param>
        /// <remarks>This updates both the actual tunnel state and all related UI elements.</remarks>
        private void UpdateState(ConnectionState state)
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

                    lstProfiles.Items[_wiresock.ProfileName].ImageKey = ConnectionState.Connecting.ToString();

                    trayIcon.Text = Resources.TrayActivating;

                    if (!_tunnelConnectionWorker.IsBusy)
                        _tunnelConnectionWorker.RunWorkerAsync();
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
                        if (item is ToolStripMenuItem menuItem && String.Equals(menuItem.Tag, "tunnel"))
                            menuItem.Checked = (menuItem.Text == _wiresock.ProfileName);
                    }

                    lstProfiles.Items[_wiresock.ProfileName].ImageKey = ConnectionState.Connected.ToString();

                    Settings.Default.LastProfile = _wiresock.ProfileName;
                    Settings.Default.Save();

                    gbxState.Visible = true;

                    if (!_tunnelStateWorker.IsBusy)
                        _tunnelStateWorker.RunWorkerAsync();

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
                        if (item is ToolStripMenuItem menuItem && String.Equals(menuItem.Tag, "tunnel"))
                            menuItem.Checked = false;
                    }

                    lstProfiles.Items[_wiresock.ProfileName].ImageKey = ConnectionState.Disconnected.ToString();

                    gbxState.Visible = false;
                    _tunnelStateWorker.CancelAsync();

                    Notifications.Notify(Resources.ToastInactiveTitle, String.Format(Resources.ToastInactiveMessage, _wiresock.ProfileName));

                    _wiresock.Disconnect();
                    break;
            }
        }

        /**
         * @brief Initializes a new instance of the Main class.
         */
        public frmMain()
        {
            InitializeComponent();

            _tunnelConnectionWorker = InitializeTunnelConnectionWorker();
            _tunnelStateWorker = InitTunnelStateWorker();

            // Configure icons
            this.Icon = trayIcon.Icon = Resources.ico;
            cmiStatus.Image = BitmapExtensions.DrawCircle(16, 15, Brushes.DarkGray);

            // Populate menu items with Windows supplied icons
            ddmAddTunnel.Image = WindowsIcons.GetWindowsIcon(WindowsIcons.Icons.Addtunnel, 16).ToBitmap();
            mniImportTunnel.Image = WindowsIcons.GetWindowsIcon(WindowsIcons.Icons.OpenTunnel, 16).ToBitmap();
            mniNewTunnel.Image = WindowsIcons.GetWindowsIcon(WindowsIcons.Icons.NewTunnel, 16).ToBitmap();
            mniDeleteTunnel.Image = WindowsIcons.GetWindowsIcon(WindowsIcons.Icons.DeleteTunnel, 16).ToBitmap();
            mniSettings.Image = WindowsIcons.GetWindowsIcon(WindowsIcons.Icons.Settings, 16).ToBitmap();

            // Populate profile image list with Windows supplied icons
            imlProfiles.Images.Clear();
            imlProfiles.Images.Add(ConnectionState.Disconnected.ToString(),
                WindowsIcons.GetWindowsIcon(WindowsIcons.Icons.DisconnectedTunnel, 24));
            imlProfiles.Images.Add(ConnectionState.Connected.ToString(),
                WindowsIcons.GetWindowsIcon(WindowsIcons.Icons.ConnectedTunnel, 24));
            imlProfiles.Images.Add(ConnectionState.Connecting.ToString(),
                WindowsIcons.GetWindowsIcon(WindowsIcons.Icons.ConnectingTunnel, 24));

            // Ensure the profile list rows fill the entire width, but no scrollbar appears
            lstProfiles.Columns[0].Width = lstProfiles.Size.Width - 4;

            OnLogWindowResize(lstLog, EventArgs.Empty);

            // Update the list of available configurations.
            LoadProfiles();

            // Create a new WireSockManager instance, attached to the logging control
            _wiresock = new WireSockManager(lstLog, this.OnWireSockLogMessage);
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
                OnProfileClick(lstProfiles, EventArgs.Empty);
            else
                MessageBox.Show(Resources.LastProfileNotFound, Resources.DialogAutoConnect, MessageBoxButtons.OK, MessageBoxIcon.Error);
        }

        private void OnExitClick(object sender, EventArgs e)
        {
            Application.Exit();
        }

        private void OnFormClosing(object sender, FormClosingEventArgs e)
        {
            if (e.CloseReason != CloseReason.UserClosing) return;
            e.Cancel = true;
            Hide();
        }

        private void OnFormShow(object sender, EventArgs e)
        {
            Show();
            this.WindowState = FormWindowState.Normal;
        }

        private void OnFormMinimize(object sender, EventArgs e)
        {
            if (this.WindowState == FormWindowState.Minimized)
                Hide();
        }

        private void OnNewProfileClick(object sender, EventArgs e)
        {
            using (Form form = new frmEdit())
            {
                if (form.ShowDialog() == DialogResult.OK)
                    LoadProfiles();
            }
        }

        private void OnAddProfileClick(object sender, EventArgs e)
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

        private void OnEditProfileClick(object sender, EventArgs e)
        {
            String profile = lstProfiles.SelectedItems[0].Text;

            using (frmEdit form = new frmEdit(profile))
            {
                if (form.ShowDialog() == DialogResult.OK)
                {
                    LoadProfiles(form.ReturnValue);

                    if (_wiresock.Connected && _wiresock.ProfileName == profile)
                        OnProfileClick(lstProfiles, EventArgs.Empty);
                }
            }
        }

        private void OnDeleteProfileClick(object sender, EventArgs e)
        {
            String selectedConf = lstProfiles.SelectedItems[0].Text;

            if (MessageBox.Show(String.Format(Resources.DeleteProfileConfirmMsg, selectedConf), Resources.DeleteProfileConfirmTitle,
                    MessageBoxButtons.YesNo, MessageBoxIcon.Exclamation) != DialogResult.Yes)
                return;

            if (_wiresock.Connected && _wiresock.ProfileName == selectedConf)
                UpdateState(ConnectionState.Disconnected);

            File.Delete(Profile.GetProfilePath(selectedConf));
            LoadProfiles();
        }

        private void OnSettingsClick(object sender, EventArgs e)
        {
            using (frmSettings form = new frmSettings())
            {
                // set the owner of the child form to the main form instance
                form.Owner = this;

                if (form.ShowDialog() == DialogResult.OK)
                    _wiresock.LogLevel = _wiresock.LogLevelSetting;
            }
        }

        private void OnProfileClick(object sender, EventArgs e)
        {
            if (lstProfiles.SelectedItems.Count == 0) return;

            if (_wiresock.Connected)
            {
                UpdateState(ConnectionState.Disconnected);
            }
            else
            {
                _wiresock.TunnelMode = Properties.Settings.Default.UseAdapter ? WireSockManager.Mode.VirtualAdapter : WireSockManager.Mode.Transparent;

                string profile = lstProfiles.SelectedItems[0].Text;

                if (_wiresock.Connect(profile))
                    UpdateState(ConnectionState.Connecting);
            }
        }

        private void OnWireSockLogMessage(WireSockManager.LogMessage logMessage)
        {
            lstLog.Items.Add(new ListViewItem(new string[] { logMessage.Timestamp.ToString(Resources.LogTimestampFormat), logMessage.Message }));
        }

        #region Layout

        private void OnProfileChange(object sender, ListViewItemSelectionChangedEventArgs e)
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

                    btnActivate.Click += OnProfileClick;

                    layoutInterface.Controls.Add(btnActivate, 1, layoutInterface.RowCount - 1);

                    layoutInterface.RowStyles.Add(new RowStyle(SizeType.AutoSize));
                    gbxInterface.Visible = true;

                    OnLayoutPanelResize(layoutInterface, EventArgs.Empty);

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

                    OnLayoutPanelResize(layoutPeer, EventArgs.Empty);

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

        private void OnLayoutPanelResize(object sender, EventArgs e)
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

        private void OnLogWindowResize(object sender, EventArgs e)
        {
            // Ensure the log list rows fill the entire width, but no scrollbar appears
            lstLog.Columns[1].Width = lstLog.Columns[0].Width + lstLog.Size.Width - 4;
        }

        private void OnLogDrawHeader(object sender, DrawListViewItemEventArgs e)
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

        private void OnLogDrawColumnHeader(object sender, DrawListViewColumnHeaderEventArgs e)
        {
            e.DrawDefault = true;
        }
        #endregion

    }
}
