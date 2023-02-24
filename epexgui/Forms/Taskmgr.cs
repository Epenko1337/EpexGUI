using System;
using System.Diagnostics;
using System.Drawing;
using System.Windows.Forms;

namespace epexgui.Forms
{
    public partial class Taskmgr : Form
    {
        public string ReturnName;
        public Taskmgr()
        {
            InitializeComponent();
            UpdateProcesses();
        }

        public void UpdateProcesses()
        {
            Process[] processCollection = Process.GetProcesses();
            ImageList imageList = new ImageList();
            foreach (Process p in processCollection)
            {
                if (!p.ProcessName.ToLower().Contains(FindBox.Text.ToLower())) continue;
                ListViewItem item = new ListViewItem();
                item.Text = p.ProcessName;
                try
                {
                    imageList.Images.Add(p.Id.ToString(), Icon.ExtractAssociatedIcon(p.MainModule.FileName));
                    listView1.SmallImageList = imageList;
                    item.ImageKey = p.Id.ToString();
                }
                catch {}
                listView1.Items.Add(item);
            }
        }

        private void Update_Click(object sender, EventArgs e)
        {
            listView1.Clear();
            UpdateProcesses();
        }

        private void FindBox_TextChanged(object sender, EventArgs e)
        {
            listView1.Clear();
            UpdateProcesses();
        }

        private void listView1_ItemActivate(object sender, EventArgs e)
        {
            ListView lw = sender as ListView;
            ReturnName = lw.SelectedItems[0].Text;
            Close();
        }
    }
}
