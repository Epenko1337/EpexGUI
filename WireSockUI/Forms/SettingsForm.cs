using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Windows.Forms;
using WireSockUI.Native;
using WireSockUI.Properties;

namespace WireSockUI.Forms
{
    public partial class frmSettings : Form
    {
        private static readonly string linkFile = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Startup), "WireSockUI.lnk");

        public frmSettings()
        {
            InitializeComponent();

            this.Icon = Resources.ico;

            chkAutorun.Checked = Settings.Default.AutoRun;
            chkMinimizeTray.Checked = Settings.Default.AutoMinimize;
            chkAutoConnect.Checked = Settings.Default.AutoConnect;
            chkUseAdapter.Checked = Settings.Default.UseAdapter;
            ddlLogLevel.SelectedItem = Settings.Default.LogLevel;

            // If the shortcut exists, and the setting does not match update it to reflect the actual status
            chkAutoConnect.Checked = File.Exists(linkFile);
        }

        private void OnProfilesFolderClick(object sender, EventArgs e)
        {
            Process.Start("explorer.exe", Global.MainFolder);
        }

        private void OnSaveClick(object sender, EventArgs e)
        {
            if (Settings.Default.AutoRun != chkAutorun.Checked)
            {
                if (!chkAutorun.Checked && File.Exists(linkFile))
                {
                    File.Delete(linkFile);
                }
                else
                {
                    using (ShellLink link = new ShellLink())
                    {
                        link.TargetPath = Assembly.GetExecutingAssembly().Location;
                        link.Save(linkFile);
                    }
                }

                Settings.Default.AutoRun = chkAutorun.Checked;
            }

            Settings.Default.AutoConnect = chkAutoConnect.Checked;
            Settings.Default.AutoMinimize = chkMinimizeTray.Checked;
            Settings.Default.UseAdapter = chkUseAdapter.Checked;
            Settings.Default.LogLevel = ddlLogLevel.SelectedItem as string;

            Settings.Default.Save();

            DialogResult = DialogResult.OK;
            Close();
        }
    }
}
