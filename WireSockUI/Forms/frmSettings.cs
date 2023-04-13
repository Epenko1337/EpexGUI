using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Windows.Forms;
using WireSockUI.Native;
using WireSockUI.Properties;

namespace WireSockUI.Forms
{
    public partial class FrmSettings : Form
    {
        private static readonly string LinkFile =
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Startup), "WireSockUI.lnk");

        public FrmSettings()
        {
            InitializeComponent();

            Icon = Resources.ico;

            chkAutorun.Checked = Settings.Default.AutoRun;
            chkAutoMinimize.Checked = Settings.Default.AutoMinimize;
            chkAutoConnect.Checked = Settings.Default.AutoConnect;
            chkAutoUpdate.Checked = Settings.Default.AutoUpdate;
            chkUseAdapter.Checked = Settings.Default.UseAdapter;
            ddlLogLevel.SelectedItem = Settings.Default.LogLevel;

            // If the shortcut exists, and the setting does not match update it to reflect the actual status
            chkAutorun.Checked = File.Exists(LinkFile);
        }

        private void OnProfilesFolderClick(object sender, EventArgs e)
        {
            Process.Start("explorer.exe", Global.MainFolder);
        }

        private void OnSaveClick(object sender, EventArgs e)
        {
            if (Settings.Default.AutoRun != chkAutorun.Checked)
            {
                if (!chkAutorun.Checked && File.Exists(LinkFile))
                    File.Delete(LinkFile);
                else
                    using (var link = new ShellLink())
                    {
                        link.TargetPath = Assembly.GetExecutingAssembly().Location;
                        link.Save(LinkFile);
                    }

                Settings.Default.AutoRun = chkAutorun.Checked;
            }

            Settings.Default.AutoConnect = chkAutoConnect.Checked;
            Settings.Default.AutoMinimize = chkAutoMinimize.Checked;
            Settings.Default.AutoUpdate = chkAutoUpdate.Checked;
            Settings.Default.UseAdapter = chkUseAdapter.Checked;
            Settings.Default.LogLevel = ddlLogLevel.SelectedItem as string;

            Settings.Default.Save();

            DialogResult = DialogResult.OK;
            Close();
        }
    }
}