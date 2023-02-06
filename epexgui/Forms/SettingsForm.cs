using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Data;
using System.Diagnostics;
using System.Drawing;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace epexgui.Forms
{
    public partial class SettingsForm : Form
    {
        public SettingsForm()
        {
            InitializeComponent();
            autorun.Checked = Global.setMan.settings.Autorun;
            MinimizeOnStart.Checked = Global.setMan.settings.MinimizeOnStart;
            ConnectOnStart.Checked = Global.setMan.settings.ConnectOnStart;
        }

        private void OpenFolder_Click(object sender, EventArgs e)
        {
            Process.Start("explorer.exe", Global.MainFolder);
        }

        private void SaveBtn_Click(object sender, EventArgs e)
        {
            Global.setMan.settings.Autorun = autorun.Checked;
            Global.setMan.settings.MinimizeOnStart = MinimizeOnStart.Checked;
            Global.setMan.settings.ConnectOnStart = ConnectOnStart.Checked;
            Global.setMan.Write();
            Close();
        }
    }
}
