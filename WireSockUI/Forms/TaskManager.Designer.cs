namespace WireSockUI.Forms
{
    partial class TaskManager
    {
        /// <summary>
        /// Required designer variable.
        /// </summary>
        private System.ComponentModel.IContainer components = null;

        /// <summary>
        /// Clean up any resources being used.
        /// </summary>
        /// <param name="disposing">true if managed resources should be disposed; otherwise, false.</param>
        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                DisposeManagedResources();
                components?.Dispose();
            }
            base.Dispose(disposing);
        }

        #region Windows Form Designer generated code

        /// <summary>
        /// Required method for Designer support - do not modify
        /// the contents of this method with the code editor.
        /// </summary>
        private void InitializeComponent()
        {
            this.components = new System.ComponentModel.Container();
            this.lstProcesses = new System.Windows.Forms.ListView();
            this.colProcess = ((System.Windows.Forms.ColumnHeader)(new System.Windows.Forms.ColumnHeader()));
            this.imgProcesses = new System.Windows.Forms.ImageList(this.components);
            this.pnlFilters = new System.Windows.Forms.Panel();
            this.txtSearch = new System.Windows.Forms.TextBox();
            this.btnRefresh = new System.Windows.Forms.Button();
            this.checkBoxShowUserProcesses = new System.Windows.Forms.CheckBox();
            this.resControls = new WireSockUI.Extensions.ControlTextExtender();
            this.pnlFilters.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.resControls)).BeginInit();
            this.SuspendLayout();
            // 
            // lstProcesses
            // 
            this.lstProcesses.Activation = System.Windows.Forms.ItemActivation.TwoClick;
            this.lstProcesses.BorderStyle = System.Windows.Forms.BorderStyle.FixedSingle;
            this.lstProcesses.Columns.AddRange(new System.Windows.Forms.ColumnHeader[] {
            this.colProcess});
            this.lstProcesses.Dock = System.Windows.Forms.DockStyle.Fill;
            this.lstProcesses.FullRowSelect = true;
            this.lstProcesses.HeaderStyle = System.Windows.Forms.ColumnHeaderStyle.None;
            this.lstProcesses.HideSelection = false;
            this.lstProcesses.Location = new System.Drawing.Point(0, 0);
            this.lstProcesses.MultiSelect = false;
            this.lstProcesses.Name = "lstProcesses";
            this.resControls.SetResourceKey(this.lstProcesses, null);
            this.lstProcesses.ShowGroups = false;
            this.lstProcesses.Size = new System.Drawing.Size(480, 420);
            this.lstProcesses.SmallImageList = this.imgProcesses;
            this.lstProcesses.Sorting = System.Windows.Forms.SortOrder.Ascending;
            this.lstProcesses.TabIndex = 0;
            this.lstProcesses.UseCompatibleStateImageBehavior = false;
            this.lstProcesses.View = System.Windows.Forms.View.Details;
            this.lstProcesses.ItemActivate += new System.EventHandler(this.OnProcessSelected);
            this.lstProcesses.KeyPress += new System.Windows.Forms.KeyPressEventHandler(this.OnProcessKeyPress);
            // 
            // colProcess
            // 
            this.colProcess.Text = "Name";
            this.colProcess.Width = 474;
            // 
            // imgProcesses
            // 
            this.imgProcesses.ColorDepth = System.Windows.Forms.ColorDepth.Depth32Bit;
            this.imgProcesses.ImageSize = new System.Drawing.Size(16, 16);
            this.imgProcesses.TransparentColor = System.Drawing.Color.Transparent;
            //
            // pnlFilters
            //
            this.pnlFilters.Controls.Add(this.checkBoxShowUserProcesses);
            this.pnlFilters.Controls.Add(this.btnRefresh);
            this.pnlFilters.Controls.Add(this.txtSearch);
            this.pnlFilters.Dock = System.Windows.Forms.DockStyle.Bottom;
            this.pnlFilters.Location = new System.Drawing.Point(0, 420);
            this.pnlFilters.Name = "pnlFilters";
            this.pnlFilters.Padding = new System.Windows.Forms.Padding(12, 10, 12, 10);
            this.resControls.SetResourceKey(this.pnlFilters, null);
            this.pnlFilters.Size = new System.Drawing.Size(480, 80);
            this.pnlFilters.TabIndex = 1;
            // 
            // txtSearch
            // 
            this.txtSearch.Anchor = ((System.Windows.Forms.AnchorStyles)(((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left)
            | System.Windows.Forms.AnchorStyles.Right)));
            this.txtSearch.BorderStyle = System.Windows.Forms.BorderStyle.FixedSingle;
            this.txtSearch.Location = new System.Drawing.Point(12, 10);
            this.txtSearch.MaxLength = 260;
            this.txtSearch.Name = "txtSearch";
            this.resControls.SetResourceKey(this.txtSearch, null);
            this.txtSearch.Size = new System.Drawing.Size(416, 20);
            this.txtSearch.TabIndex = 0;
            this.txtSearch.TextChanged += new System.EventHandler(this.OnFindProcessChanged);
            // 
            // btnRefresh
            // 
            this.btnRefresh.Anchor = ((System.Windows.Forms.AnchorStyles)((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right)));
            this.btnRefresh.Location = new System.Drawing.Point(436, 8);
            this.btnRefresh.Name = "btnRefresh";
            this.btnRefresh.Padding = new System.Windows.Forms.Padding(1);
            this.resControls.SetResourceKey(this.btnRefresh, null);
            this.btnRefresh.Size = new System.Drawing.Size(32, 26);
            this.btnRefresh.TabIndex = 1;
            this.btnRefresh.UseVisualStyleBackColor = true;
            this.btnRefresh.Click += new System.EventHandler(this.OnRefreshClick);
            // 
            // checkBoxShowUserProcesses
            // 
            this.checkBoxShowUserProcesses.AutoSize = true;
            this.checkBoxShowUserProcesses.Checked = true;
            this.checkBoxShowUserProcesses.CheckState = System.Windows.Forms.CheckState.Checked;
            this.checkBoxShowUserProcesses.Location = new System.Drawing.Point(12, 46);
            this.checkBoxShowUserProcesses.Name = "checkBoxShowUserProcesses";
            this.resControls.SetResourceKey(this.checkBoxShowUserProcesses, null);
            this.checkBoxShowUserProcesses.Size = new System.Drawing.Size(177, 17);
            this.checkBoxShowUserProcesses.TabIndex = 2;
            this.checkBoxShowUserProcesses.Text = "Hide processes from other users";
            this.checkBoxShowUserProcesses.UseVisualStyleBackColor = true;
            this.checkBoxShowUserProcesses.CheckedChanged += new System.EventHandler(this.OnChangeUserProcessVisibilityCheckBox);
            // 
            // resControls
            // 
            this.resControls.ResourceClassName = "WireSockUI.Properties.Resources";
            // 
            // TaskManager
            // 
            this.AutoScaleDimensions = new System.Drawing.SizeF(6F, 13F);
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            this.ClientSize = new System.Drawing.Size(480, 500);
            this.Controls.Add(this.lstProcesses);
            this.Controls.Add(this.pnlFilters);
            this.FormBorderStyle = System.Windows.Forms.FormBorderStyle.Sizable;
            this.MaximizeBox = true;
            this.MinimizeBox = false;
            this.MinimumSize = new System.Drawing.Size(420, 400);
            this.Name = "TaskManager";
            this.resControls.SetResourceKey(this, "FormTaskManager");
            this.StartPosition = System.Windows.Forms.FormStartPosition.CenterParent;
            this.Text = "Select process";
            this.pnlFilters.ResumeLayout(false);
            this.pnlFilters.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)(this.resControls)).EndInit();
            this.ResumeLayout(false);
            this.PerformLayout();

        }

        #endregion

        private System.Windows.Forms.ListView lstProcesses;
        private System.Windows.Forms.TextBox txtSearch;
        private System.Windows.Forms.Panel pnlFilters;
        private System.Windows.Forms.ImageList imgProcesses;
        private System.Windows.Forms.ColumnHeader colProcess;
        private System.Windows.Forms.Button btnRefresh;
        private Extensions.ControlTextExtender resControls;
        private System.Windows.Forms.CheckBox checkBoxShowUserProcesses;
    }
}
