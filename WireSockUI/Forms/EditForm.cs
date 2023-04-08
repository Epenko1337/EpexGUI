using System;
using System.Drawing;
using System.IO;
using System.Text.RegularExpressions;
using System.Windows.Forms;
using WireSockUI.Config;
using WireSockUI.Native;
using WireSockUI.Properties;

namespace WireSockUI.Forms
{
    public partial class frmEdit : Form
    {
        private static Regex profileMatch = new Regex(@"^\s*((?<comment>[;#].*)|(?<section>\[\w+\])|((?<key>[a-zA-Z0-9]+)[ \t]*=[ \t]*(?<value>.*?)))$", RegexOptions.Multiline | RegexOptions.Compiled);
        private static Regex multiValueMatch = new Regex(@"[^, ]*", RegexOptions.IgnoreCase | RegexOptions.Compiled);

        public String ReturnValue
        {
            get; private set;
        }

        private void applySyntaxHighlighting()
        {
            bool hasErrors = false;

            // Saving the original settings
            int originalIndex = txtEditor.SelectionStart;
            int originalLength = txtEditor.SelectionLength;
            Color originalColor = Color.Black;

            lblName.Focus();

            // removes any previous highlighting
            txtEditor.SelectionStart = 0;
            txtEditor.SelectionLength = txtEditor.Text.Length;
            txtEditor.SelectionColor = originalColor;
            txtEditor.SelectionFont = new Font(txtEditor.SelectionFont, FontStyle.Regular);

            foreach (Match m in profileMatch.Matches(txtEditor.Text))
            {
                if (m.Groups["comment"].Success)
                {
                    txtEditor.SelectionStart = m.Groups["comment"].Index;
                    txtEditor.SelectionLength = m.Groups["comment"].Length;
                    txtEditor.SelectionFont = new Font(txtEditor.SelectionFont, FontStyle.Italic);

                    switch (m.Groups["comment"].Value[0])
                    {
                        case '#':
                            txtEditor.SelectionColor = Color.LightSlateGray;
                            break;
                        case ';':
                            txtEditor.SelectionColor = Color.SaddleBrown;
                            break;
                    }

                    continue;
                }

                if (m.Groups["section"].Success)
                {
                    txtEditor.SelectionStart = m.Groups["section"].Index;
                    txtEditor.SelectionLength = m.Groups["section"].Length;
                    txtEditor.SelectionColor = Color.DarkBlue;
                    txtEditor.SelectionFont = new Font(txtEditor.SelectionFont, FontStyle.Bold);

                    switch (m.Groups["section"].Value.ToLowerInvariant())
                    {
                        case "[interface]":
                        case "[peer]":
                            break;
                        // Unrecognized sections
                        default:
                            txtEditor.UnderlineSelection();
                            hasErrors = true;
                            break;
                    }

                    continue;
                }

                if (m.Groups["key"].Success)
                {
                    txtEditor.SelectionStart = m.Groups["key"].Index;
                    txtEditor.SelectionLength = m.Groups["key"].Length;
                    txtEditor.SelectionColor = Color.Navy;

                    string key = m.Groups["key"].Value.ToLowerInvariant();
                    string value = String.Empty;

                    if (m.Groups["value"].Success)
                    {
                        txtEditor.SelectionStart = m.Groups["value"].Index;
                        txtEditor.SelectionLength = m.Groups["value"].Length;
                        txtEditor.SelectionColor = Color.DarkGreen;

                        value = m.Groups["value"].Value;
                    }

                    switch (key)
                    {
                        // base64 256-bit keys
                        case "privatekey":
                        case "publickey":
                            case "presharedkey":
                            {
                                if (!String.IsNullOrEmpty(value))
                                {
                                    try
                                    {
                                        if (key == "privatekey")
                                            txtPublicKey.Text = String.Empty;

                                        byte[] binaryKey = Convert.FromBase64String(value);

                                        if (binaryKey.Length != 32)
                                            throw new FormatException();

                                        // Convert Peer.PrivateKey into PublicKey for display
                                        if (key == "privatekey")
                                            txtPublicKey.Text = Convert.ToBase64String(Curve25519.GetPublicKey(binaryKey));
                                    }
                                    catch (FormatException)
                                    {
                                        txtEditor.UnderlineSelection();
                                        hasErrors = true;
                                    }
                                }
                            }
                            break;
                        // IPv4/IPv6 CIDR notation values
                        case "address":
                        case "allowedips":
                        case "disallowedips":
                            {
                                foreach (Match e in multiValueMatch.Matches(value))
                                {
                                    if (!String.IsNullOrWhiteSpace(e.Value) && !IPHelper.IsValidIPNetwork(e.Value))
                                    {
                                        txtEditor.SelectionStart = m.Groups["value"].Index + e.Index;
                                        txtEditor.SelectionLength = e.Length;
                                        txtEditor.UnderlineSelection();
                                        hasErrors = true;
                                    }
                                }

                            }
                            break;
                        // IPv4/IPv6 values
                        case "dns":
                            {
                                foreach (Match e in multiValueMatch.Matches(value))
                                {
                                    if (!String.IsNullOrWhiteSpace(e.Value) && !IPHelper.IsValidIPAddress(e.Value))
                                    {
                                        txtEditor.SelectionStart = m.Groups["value"].Index + e.Index;
                                        txtEditor.SelectionLength = e.Length;
                                        txtEditor.UnderlineSelection();
                                        hasErrors = true;
                                    }
                                }
                            }

                            break;
                        // IPv4, IPv6 or DNS value
                        case "endpoint":
                        case "socks5proxy":
                            if (!IPHelper.IsValidAddress(value))
                            {
                                txtEditor.UnderlineSelection();
                                hasErrors = true;
                            }
                            break;
                        // Numerical values
                        case "mtu":
                        case "persistentkeepalive":
                            {
                                if (!int.TryParse(m.Groups["value"].Value, out int intValue))
                                {
                                    txtEditor.UnderlineSelection();
                                    hasErrors = true;
                                }
                                else
                                {
                                    if (intValue < 0 || intValue > 65535)
                                    {
                                        txtEditor.UnderlineSelection();
                                        hasErrors = true;
                                    }
                                }
                            }
                            break;
                        // Comma-delimited string values
                        case "allowedapps":
                        case "disallowedapps":
                            {
                                foreach (Match e in multiValueMatch.Matches(value))
                                {
                                    if (!String.IsNullOrWhiteSpace(e.Value) && !Regex.IsMatch(e.Value, @"^[a-z0-9_-]+$", RegexOptions.IgnoreCase))
                                    {
                                        txtEditor.SelectionStart = m.Groups["value"].Index + e.Index;
                                        txtEditor.SelectionLength = e.Length;
                                        txtEditor.UnderlineSelection();
                                        hasErrors = true;
                                    }
                                }
                            }
                            break;
                        // String values
                        case "socks5proxyusername":
                        case "socks5proxypassword":
                            break;
                        // Unrecognized keys
                        default:
                            txtEditor.SelectionStart = m.Groups["key"].Index;
                            txtEditor.SelectionLength = m.Groups["key"].Length;
                            txtEditor.UnderlineSelection();
                            hasErrors = true;
                            break;
                    }

                }
            }

            // restoring the original settings
            txtEditor.SelectionStart = originalIndex;
            txtEditor.SelectionLength = originalLength;
            txtEditor.SelectionColor = originalColor;

            txtEditor.Focus();

            btnSave.Enabled = !hasErrors;
        }

        public frmEdit()
        {
            InitializeComponent();

            this.Icon = Resources.ico;

            txtProfileName.SetCueBanner(Resources.EditProfileCue);
        }

        public frmEdit(string config): this()
        {
            if (String.IsNullOrEmpty(config))
            {
                Text = Resources.EditProfileTitleNew;
                txtEditor.Text = Resources.template_conf;                
            }
            else
            {
                Text = String.Format(Resources.EditProfileTitle, config);

                txtProfileName.Text = config.ToLowerInvariant();
                txtEditor.Text = File.ReadAllText(Path.Combine(Global.ConfigsFolder, config + ".conf"));
            }

            applySyntaxHighlighting();
        }

        private void SaveProfile(object sender, EventArgs e)
        {
            String tmpProfile = Path.GetTempFileName();
            File.WriteAllText(tmpProfile, txtEditor.Text);

            try
            {
                Profile profile = new Profile(tmpProfile);
            }
            catch (Exception ex)
            {
                MessageBox.Show(ex.Message, Resources.EditProfileError, MessageBoxButtons.OK, MessageBoxIcon.Error);
                File.Delete(tmpProfile);

                this.DialogResult = DialogResult.None;
                return;
            }

            if (String.IsNullOrWhiteSpace(txtProfileName.Text) || txtProfileName.Text.IndexOfAny(Path.GetInvalidFileNameChars()) > 0)
            {
                MessageBox.Show(Resources.EditProfileNameError, Resources.EditProfileError, MessageBoxButtons.OK, MessageBoxIcon.Error);
                File.Delete(tmpProfile);

                this.DialogResult = DialogResult.None;
                return;
            }

            String profilePath = Path.Combine(Global.ConfigsFolder, txtProfileName.Text + ".conf");

            File.Delete(profilePath);
            File.Move(tmpProfile, profilePath);

            this.ReturnValue = txtProfileName.Text;
            
            Close();
        }
       
        private void FindProcess(object sender, EventArgs e)
        {
            using (TaskManager taskManager = new TaskManager())
            {
                if (taskManager.ShowDialog() == DialogResult.OK)
                {
                    txtEditor.SelectionLength = 0;
                    txtEditor.SelectedText = taskManager.ReturnValue;
                }
            }
        }

        private void ProfileChanged(object sender, EventArgs e)
        {
            applySyntaxHighlighting();
        }
    }
}
