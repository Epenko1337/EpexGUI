using Microsoft.Win32;
using System;
using System.Diagnostics;
using System.Reflection;
using System.Windows.Forms;
using WireSockUI.Properties;
using Microsoft.Win32.TaskScheduler;

namespace WireSockUI.Forms
{
    public partial class FrmSettings : Form
    {
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
            chkAutorun.Checked = IsAutoRunEnabled();
        }

        private void OnProfilesFolderClick(object sender, EventArgs e)
        {
            Process.Start("explorer.exe", Global.MainFolder);
        }

        private static string GetAppName()
        {
            return Assembly.GetExecutingAssembly().GetName().Name;
        }

        private static bool IsAutoRunEnabled()
        {
            using (var ts = new TaskService())
            {
                return ts.FindTask(GetAppName()) != null;
            }
        }

        private static void EnableAutoRun()
        {
            try
            {
                using (var ts = new TaskService())
                {
                    var td = ts.NewTask();
                    td.RegistrationInfo.Description = "Auto start for " + GetAppName();
                    td.Principal.RunLevel = TaskRunLevel.Highest; // Run with the highest privileges

                    td.Triggers.Add(new LogonTrigger()); // Trigger on logon

                    var appPath = Assembly.GetExecutingAssembly().Location;
                    td.Actions.Add(new ExecAction(appPath, null, null)); // Path to the executable

                    ts.RootFolder.RegisterTaskDefinition(GetAppName(), td);
                }
            }
            catch (Exception ex)
            {
                MessageBox.Show("Error enabling autorun: " + ex.Message, "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private static void DisableAutoRun()
        {
            try
            {
                using (var ts = new TaskService())
                {
                    ts.RootFolder.DeleteTask(GetAppName(), false);
                }
            }
            catch (Exception ex)
            {
                MessageBox.Show("Error disabling autorun: " + ex.Message, "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private void OnSaveClick(object sender, EventArgs e)
        {
            if (Settings.Default.AutoRun != chkAutorun.Checked)
            {
                if (!chkAutorun.Checked)
                    DisableAutoRun();
                else
                    EnableAutoRun();

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