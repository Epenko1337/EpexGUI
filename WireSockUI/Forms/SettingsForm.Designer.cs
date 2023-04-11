namespace WireSockUI.Forms
{
    partial class frmSettings
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
            if (disposing && (components != null))
            {
                components.Dispose();
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
            this.chkAutorun = new System.Windows.Forms.CheckBox();
            this.chkAutoMinimize = new System.Windows.Forms.CheckBox();
            this.chkAutoConnect = new System.Windows.Forms.CheckBox();
            this.btnSave = new System.Windows.Forms.Button();
            this.btnOpenFolder = new System.Windows.Forms.Button();
            this.ddlLogLevel = new System.Windows.Forms.ComboBox();
            this.lblLogLevel = new System.Windows.Forms.Label();
            this.chkUseAdapter = new System.Windows.Forms.CheckBox();
            this.resControls = new WireSockUI.Extensions.ControlTextExtender();
            this.chkAutoUpdate = new System.Windows.Forms.CheckBox();
            ((System.ComponentModel.ISupportInitialize)(this.resControls)).BeginInit();
            this.SuspendLayout();
            // 
            // chkAutorun
            // 
            this.chkAutorun.AutoSize = true;
            this.chkAutorun.Location = new System.Drawing.Point(12, 12);
            this.chkAutorun.Name = "chkAutorun";
            this.resControls.SetResourceKey(this.chkAutorun, "SettingsAutoRun");
            this.chkAutorun.Size = new System.Drawing.Size(150, 17);
            this.chkAutorun.TabIndex = 0;
            this.chkAutorun.Text = "Run when Windows starts";
            this.chkAutorun.UseVisualStyleBackColor = true;
            // 
            // chkMinimizeTray
            // 
            this.chkAutoMinimize.AutoSize = true;
            this.chkAutoMinimize.Location = new System.Drawing.Point(12, 38);
            this.chkAutoMinimize.Name = "chkMinimizeTray";
            this.resControls.SetResourceKey(this.chkAutoMinimize, "SettingsAutoMinimize");
            this.chkAutoMinimize.Size = new System.Drawing.Size(136, 17);
            this.chkAutoMinimize.TabIndex = 1;
            this.chkAutoMinimize.Text = "Minimize to tray on start";
            this.chkAutoMinimize.UseVisualStyleBackColor = true;
            // 
            // chkAutoConnect
            // 
            this.chkAutoConnect.AutoSize = true;
            this.chkAutoConnect.Location = new System.Drawing.Point(12, 64);
            this.chkAutoConnect.Name = "chkAutoConnect";
            this.resControls.SetResourceKey(this.chkAutoConnect, "SettingsAutoConnect");
            this.chkAutoConnect.Size = new System.Drawing.Size(168, 17);
            this.chkAutoConnect.TabIndex = 2;
            this.chkAutoConnect.Text = "Automatically connect on start";
            this.chkAutoConnect.UseVisualStyleBackColor = true;
            // 
            // btnSave
            // 
            this.btnSave.Location = new System.Drawing.Point(12, 190);
            this.btnSave.Name = "btnSave";
            this.resControls.SetResourceKey(this.btnSave, "SettingsSave");
            this.btnSave.Size = new System.Drawing.Size(75, 25);
            this.btnSave.TabIndex = 3;
            this.btnSave.TabStop = false;
            this.btnSave.Text = "Save";
            this.btnSave.Click += new System.EventHandler(this.OnSaveClick);
            // 
            // btnOpenFolder
            // 
            this.btnOpenFolder.Location = new System.Drawing.Point(93, 190);
            this.btnOpenFolder.Name = "btnOpenFolder";
            this.resControls.SetResourceKey(this.btnOpenFolder, "SettingsProfiles");
            this.btnOpenFolder.Size = new System.Drawing.Size(121, 25);
            this.btnOpenFolder.TabIndex = 4;
            this.btnOpenFolder.TabStop = false;
            this.btnOpenFolder.Text = "Open profiles folder";
            this.btnOpenFolder.Click += new System.EventHandler(this.OnProfilesFolderClick);
            // 
            // ddlLogLevel
            // 
            this.ddlLogLevel.DropDownStyle = System.Windows.Forms.ComboBoxStyle.DropDownList;
            this.ddlLogLevel.FormattingEnabled = true;
            this.ddlLogLevel.Items.AddRange(new object[] {
            "None",
            "Info",
            "Error",
            "All"});
            this.ddlLogLevel.Location = new System.Drawing.Point(12, 157);
            this.ddlLogLevel.Name = "ddlLogLevel";
            this.resControls.SetResourceKey(this.ddlLogLevel, null);
            this.ddlLogLevel.Size = new System.Drawing.Size(121, 21);
            this.ddlLogLevel.TabIndex = 7;
            // 
            // lblLogLevel
            // 
            this.lblLogLevel.AutoSize = true;
            this.lblLogLevel.Location = new System.Drawing.Point(9, 141);
            this.lblLogLevel.Name = "lblLogLevel";
            this.resControls.SetResourceKey(this.lblLogLevel, "SettingsLogLevel");
            this.lblLogLevel.Size = new System.Drawing.Size(70, 13);
            this.lblLogLevel.TabIndex = 8;
            this.lblLogLevel.Text = "Logging level";
            // 
            // chkUseAdapter
            // 
            this.chkUseAdapter.AutoSize = true;
            this.chkUseAdapter.Location = new System.Drawing.Point(12, 116);
            this.chkUseAdapter.Name = "chkUseAdapter";
            this.resControls.SetResourceKey(this.chkUseAdapter, null);
            this.chkUseAdapter.Size = new System.Drawing.Size(167, 17);
            this.chkUseAdapter.TabIndex = 6;
            this.chkUseAdapter.Text = "Virtual Network Adapter mode";
            // 
            // resControls
            // 
            this.resControls.ResourceClassName = "WireSockUI.Properties.Resources";
            // 
            // chkAutoUpdate
            // 
            this.chkAutoUpdate.AutoSize = true;
            this.chkAutoUpdate.Location = new System.Drawing.Point(12, 90);
            this.chkAutoUpdate.Name = "chkAutoUpdate";
            this.resControls.SetResourceKey(this.chkAutoUpdate, "SettingsAutoUpdate");
            this.chkAutoUpdate.Size = new System.Drawing.Size(144, 17);
            this.chkAutoUpdate.TabIndex = 9;
            this.chkAutoUpdate.Text = "Check online for updates";
            this.chkAutoUpdate.UseVisualStyleBackColor = true;
            // 
            // frmSettings
            // 
            this.AutoScaleDimensions = new System.Drawing.SizeF(6F, 13F);
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            this.ClientSize = new System.Drawing.Size(222, 222);
            this.Controls.Add(this.chkAutoUpdate);
            this.Controls.Add(this.lblLogLevel);
            this.Controls.Add(this.ddlLogLevel);
            this.Controls.Add(this.chkUseAdapter);
            this.Controls.Add(this.btnOpenFolder);
            this.Controls.Add(this.btnSave);
            this.Controls.Add(this.chkAutoConnect);
            this.Controls.Add(this.chkAutoMinimize);
            this.Controls.Add(this.chkAutorun);
            this.FormBorderStyle = System.Windows.Forms.FormBorderStyle.FixedSingle;
            this.MaximizeBox = false;
            this.MinimizeBox = false;
            this.Name = "frmSettings";
            this.resControls.SetResourceKey(this, "FormSettings");
            this.StartPosition = System.Windows.Forms.FormStartPosition.CenterParent;
            this.Text = "Settings";
            ((System.ComponentModel.ISupportInitialize)(this.resControls)).EndInit();
            this.ResumeLayout(false);
            this.PerformLayout();

        }

        #endregion

        private System.Windows.Forms.CheckBox chkAutorun;
        private System.Windows.Forms.CheckBox chkAutoMinimize;
        private System.Windows.Forms.CheckBox chkAutoConnect;
        private System.Windows.Forms.Button btnSave;
        private System.Windows.Forms.Button btnOpenFolder;
        private System.Windows.Forms.ComboBox ddlLogLevel;
        private System.Windows.Forms.Label lblLogLevel;
        private System.Windows.Forms.CheckBox chkUseAdapter;
        private Extensions.ControlTextExtender resControls;
        private System.Windows.Forms.CheckBox chkAutoUpdate;
    }
}