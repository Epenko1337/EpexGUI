using System;
using System.Diagnostics;
using System.Windows.Forms;

namespace epexgui.Forms
{
    public partial class SettingsForm : Form
    {
        public SettingsForm()
        {
            InitializeComponent();
            autorun.Checked = Global.SetMan.AppSettings.AutoRun;
            MinimizeOnStart.Checked = Global.SetMan.AppSettings.MinimizeOnStart;
            ConnectOnStart.Checked = Global.SetMan.AppSettings.ConnectOnStart;
            EnableDebugLog.Checked = Global.SetMan.AppSettings.EnableDebugLog;
            VirtualAdapterMode.Checked = Global.SetMan.AppSettings.VirtualAdapterMode;
        }

        private void OpenFolder_Click(object sender, EventArgs e)
        {
            Process.Start("explorer.exe", Global.MainFolder);
        }

        private void SaveBtn_Click(object sender, EventArgs e)
        {
            Global.SetMan.AppSettings.AutoRun = autorun.Checked;
            Global.SetMan.AppSettings.MinimizeOnStart = MinimizeOnStart.Checked;
            Global.SetMan.AppSettings.ConnectOnStart = ConnectOnStart.Checked;
            Global.SetMan.AppSettings.EnableDebugLog = EnableDebugLog.Checked;
            Global.SetMan.AppSettings.VirtualAdapterMode = VirtualAdapterMode.Checked;

            // call methods in the main form
            ((Main)Owner).EnableDebugLog(EnableDebugLog.Checked);
            ((Main)Owner).SetAdapterMode(VirtualAdapterMode.Checked);

            Global.SetMan.Write();
            Close();
        }
    }
}
