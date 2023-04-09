using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Security.Principal;
using System.Windows.Forms;
using WireSockUI.Native;
using WireSockUI.Properties;

namespace WireSockUI.Forms
{
    public partial class TaskManager : Form
    {
        public string ReturnValue
        {
            get; private set;
        }

        public TaskManager()
        {
            InitializeComponent();

            this.Icon = Resources.ico;

            btnRefresh.Image = WindowsIcons.GetWindowsIcon(WindowsIcons.Icons.Refresh, 16).ToBitmap();

            // Ensure the process list rows fill the entire width, but no scrollbar appears
            lstProcesses.Columns[0].Width = lstProcesses.Size.Width - 18;
            txtSearch.SetCueBanner(Resources.ProcessesSearchCue);

            UpdateProcesses();
        }

        public void UpdateProcesses()
        {
            lstProcesses.Items.Clear();
            lstProcesses.SmallImageList.Images.Clear();

            String currentUser = WindowsIdentity.GetCurrent().Name;

            // Unique current user processes
            IEnumerable<ProcessEntry> processes =
                ProcessList.GetProcessList()
                .Where(p => p.User == currentUser)
                .Distinct(ProcessEntry.Comparer);

            lstProcesses.Items.AddRange(
                processes
                .Select(p =>
                {
                    if (File.Exists(p.ImageName))
                        lstProcesses.SmallImageList.Images.Add(p.ProcessId.ToString(), Icon.ExtractAssociatedIcon(p.ImageName));

                    return new ListViewItem(Path.GetFileNameWithoutExtension(p.ImageName), p.ProcessId.ToString());
                }).ToArray());

        }

        private void OnRefreshClick(object sender, EventArgs e)
        {
            UpdateProcesses();
            txtSearch.Text = String.Empty;
        }

        private void OnFindProcessChanged(object sender, EventArgs e)
        {
            if (!String.IsNullOrWhiteSpace(txtSearch.Text))
            {
                foreach (ListViewItem item in lstProcesses.Items)
                {
                    if (item.Text.StartsWith(txtSearch.Text, StringComparison.OrdinalIgnoreCase))
                    {
                        item.EnsureVisible();
                        item.Selected = true;
                        return;
                    }
                }
            }
            else
            {
                foreach (ListViewItem item in lstProcesses.SelectedItems)
                {
                    item.Selected = false;
                }
            }
        }

        private void OnProcessSelected(object sender, EventArgs e)
        {
            DialogResult = DialogResult.OK;
            this.ReturnValue = lstProcesses.SelectedItems[0].Text;
            Close();
        }
    }
}
