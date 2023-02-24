using System;
using System.IO;
using System.Linq;
using System.Windows.Forms;

namespace epexgui.Forms
{
    public partial class EditForm : Form
    {
        public bool successfull = false;
        ConfigManager configManager;
        string[] TempAllowedIPs;
        public string lastname;
        string firstname;
        public EditForm(string config)
        {
            InitializeComponent();
            Text = $"Editing configuration {config}";
            configManager = new ConfigManager($"{Global.ConfigsFolder}\\{config}.conf");
            ConfigName.Text = config;
            firstname = config;
            PrivateKey.Text = configManager.Config.PrivateKey;
            PublicKey.Text = configManager.Config.PublicKey;
            InterfaceAddress.Text = configManager.Config.InterfaceAddress;
            Endpoint.Text = configManager.Config.Endpoint;
            Dns.Text = configManager.Config.Dns;
            TextToListbox(ExcludedAppsList, configManager.Config.DisallowedApps);
            TextToListbox(ExcludedIPList, configManager.Config.DisallowedIPs);
            TextToListbox(IncludedAppsList, configManager.Config.AllowedApps);
            TextToListbox(IncludedIPList, configManager.Config.AllowedIPs);
        }

        public void TextToListbox(ListBox lbox, string text)
        {
            if (text != null)
            {
                string[] items = text.Split(',');
                if (items.Length == 1 && items[0] == "") return;
                lbox.Items.AddRange(items);
            }
        }

        public string ListboxToText(ListBox lbox)
        {
            if (lbox.Items.Count > 0)
            {
                string result = "";
                foreach (string item in lbox.Items)
                {
                    result += item;
                    if (item != (string)lbox.Items[lbox.Items.Count - 1]) result += ", ";
                }
                return result;
            }
            return null;
        }

        public string ConfigPathToName(string path)
        { return path.Remove(path.LastIndexOf('.'), 5).Substring(path.LastIndexOf('\\') + 1); }
        private void SaveButton_Click(object sender, EventArgs e)
        {
            foreach (string file in Directory.GetFiles(Global.ConfigsFolder))
            {
                if (ConfigPathToName(file).ToLower() == ConfigName.Text.ToLower() && ConfigName.Text.ToLower() != firstname.ToLower())
                {
                    MessageBox.Show(@"Configuration with this name already exists", @"Save error", MessageBoxButtons.OK, MessageBoxIcon.Error);
                    return;
                }
            }
            successfull = true;
            lastname = ConfigName.Text;
            configManager.Config.ConfigName = ConfigName.Text;
            configManager.Config.PrivateKey = PrivateKey.Text;
            configManager.Config.PublicKey = PublicKey.Text;
            configManager.Config.Dns = Dns.Text;
            configManager.Config.InterfaceAddress = InterfaceAddress.Text;
            configManager.Config.Endpoint = Endpoint.Text;
            configManager.Config.AllowedApps = ListboxToText(IncludedAppsList);
            configManager.Config.AllowedIPs = ListboxToText(IncludedIPList);
            configManager.Config.DisallowedIPs = ListboxToText(ExcludedIPList);
            configManager.Config.DisallowedApps = ListboxToText(ExcludedAppsList);
            configManager.Write();
            Close();
        }

        private void killswitch_CheckedChanged(object sender, EventArgs e)
        {
            if (killswitch.Checked)
            {
                TempAllowedIPs = new string[] { };
                foreach (object item in IncludedIPList.Items)
                {
                    TempAllowedIPs = TempAllowedIPs.Append(item.ToString()).ToArray();
                }
                IncludedIPList.Items.Clear();
                IncludedIPList.Items.Add("0.0.0.0/0");
            }
            else
            {
                IncludedIPList.Items.Clear();
                IncludedIPList.Items.AddRange(TempAllowedIPs);
            }
        }

        private void ExcludedIPBox_KeyPress(object sender, KeyPressEventArgs e)
        {
            e.Handled = e.KeyChar == ',' || e.KeyChar == ' ';
        }

        private void ListBoxEdit_Click(object sender, EventArgs e)
        {
            ListBox lbox;
            Button btn = sender as Button;
            TextBox tbox;
            if (btn.AccessibleDescription[0] == 'e')
            {
                if (btn.AccessibleDescription[1] == 'i')
                {
                    lbox = ExcludedIPList;
                    tbox = ExcludedIPBox;
                }
                else
                {
                    lbox = ExcludedAppsList;
                    tbox = ExcludedAppsBox;
                }
            }
            else
            {
                if (btn.AccessibleDescription[1] == 'i')
                {
                    lbox = IncludedIPList;
                    tbox = IncludedIPBox;
                }
                else
                {
                    lbox = IncludedAppsList;
                    tbox = IncludedAppsBox;
                }
            }
            if (btn.AccessibleDescription[2] == '+')
            {
                if (!lbox.Items.Contains(tbox.Text))
                {
                    lbox.Items.Add(tbox.Text);
                }
                tbox.Text = "";
            }
            else
            {
                if (lbox.SelectedItem != null) 
                {
                    lbox.Items.Remove(lbox.SelectedItem);
                }
            }
        }

        private void FindTaskE_Click(object sender, EventArgs e)
        {
            Taskmgr tmgr = new Taskmgr();
            tmgr.ShowDialog();
            if ((sender as Button).AccessibleDescription == "e")
            {
                ExcludedAppsBox.Text = tmgr.ReturnName;
            }
            else
            {
                IncludedAppsBox.Text = tmgr.ReturnName;
            }
        }

        private void InfoBtn_Click(object sender, EventArgs e)
        {
            MessageBox.Show(@"IncludedApps – specifies comma separated list of application names (or partial names) to forward over VPN tunnel. This parameter narrows IncludedIPs, so the traffic to be tunneled should match both IncludedIPs and IncludedApps. For example, ‘IncludedApps = chrome’ and ‘IncludedIPs = 0.0.0.0/0’ will result in forwarding only Chrome browser over the VPN connection, everything else will bypass the tunnel.

ExcludedApps – specifies comma separated list of application names (or partial names) to be excluded from the tunneling. This parameter is the opposite of IncludedApps. Please note that IncludedApps takes precedence, and if both are specified, then IncludedApps is matched first.

ExcludedIPs – specifies comma separated list of IP subnets to be excluded from the tunneling. For example, IncludedIPs = 0.0.0.0/0 and ExcludedIPs = 192.168.0.1/24 will exclude 192.168.0.1/24 from the tunneling.", @"Info", MessageBoxButtons.OK, MessageBoxIcon.Information);
        }
    }
}
