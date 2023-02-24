using System.Windows.Forms;

namespace epexgui.Forms
{
    partial class Main
    {
        /// <summary>
        /// Required designer variable.
        /// </summary>
        private System.ComponentModel.IContainer components = null;
        private ContextMenu contextMenu1;
        private MenuItem menuItem1;

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
            this.components = new System.ComponentModel.Container();
            System.ComponentModel.ComponentResourceManager resources = new System.ComponentModel.ComponentResourceManager(typeof(Main));
            this.imageList1 = new System.Windows.Forms.ImageList(this.components);
            this.ConfigList = new System.Windows.Forms.ListBox();
            this.label1 = new System.Windows.Forms.Label();
            this.AddConfig = new System.Windows.Forms.Button();
            this.RemoveConfig = new System.Windows.Forms.Button();
            this.tray = new System.Windows.Forms.NotifyIcon(this.components);
            this.panel1 = new System.Windows.Forms.Panel();
            this.EditConfig = new System.Windows.Forms.Button();
            this.ConnectButton = new System.Windows.Forms.Button();
            this.SettingsBtn = new System.Windows.Forms.Button();
            this.LogBox = new System.Windows.Forms.TextBox();
            this.ConnectedToLabel = new System.Windows.Forms.Label();
            this.LabelUpdater = new System.Windows.Forms.Timer(this.components);
            this.panel1.SuspendLayout();
            this.SuspendLayout();
            // 
            // imageList1
            // 
            this.imageList1.ImageStream = ((System.Windows.Forms.ImageListStreamer)(resources.GetObject("imageList1.ImageStream")));
            this.imageList1.TransparentColor = System.Drawing.Color.Transparent;
            this.imageList1.Images.SetKeyName(0, "icons8-filled-circle-20.png");
            // 
            // ConfigList
            // 
            this.ConfigList.BackColor = System.Drawing.Color.FromArgb(((int)(((byte)(35)))), ((int)(((byte)(35)))), ((int)(((byte)(35)))));
            this.ConfigList.BorderStyle = System.Windows.Forms.BorderStyle.None;
            this.ConfigList.Font = new System.Drawing.Font("Segoe UI", 12F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.ConfigList.ForeColor = System.Drawing.Color.White;
            this.ConfigList.FormattingEnabled = true;
            this.ConfigList.ItemHeight = 21;
            this.ConfigList.Items.AddRange(new object[] {
            "⚫ Vpnconf1",
            "⚪ Vpnconf2"});
            this.ConfigList.Location = new System.Drawing.Point(12, 35);
            this.ConfigList.Name = "ConfigList";
            this.ConfigList.Size = new System.Drawing.Size(200, 336);
            this.ConfigList.TabIndex = 3;
            this.ConfigList.TabStop = false;
            this.ConfigList.SelectedIndexChanged += new System.EventHandler(this.ConfigList_SelectedIndexChanged);
            // 
            // label1
            // 
            this.label1.Font = new System.Drawing.Font("Segoe UI", 12F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.label1.ForeColor = System.Drawing.Color.White;
            this.label1.Location = new System.Drawing.Point(12, 9);
            this.label1.Name = "label1";
            this.label1.Size = new System.Drawing.Size(200, 23);
            this.label1.TabIndex = 4;
            this.label1.Text = "Configurations";
            this.label1.TextAlign = System.Drawing.ContentAlignment.MiddleCenter;
            // 
            // AddConfig
            // 
            this.AddConfig.BackColor = System.Drawing.Color.FromArgb(((int)(((byte)(35)))), ((int)(((byte)(35)))), ((int)(((byte)(35)))));
            this.AddConfig.Dock = System.Windows.Forms.DockStyle.Left;
            this.AddConfig.FlatAppearance.BorderColor = System.Drawing.Color.FromArgb(((int)(((byte)(35)))), ((int)(((byte)(35)))), ((int)(((byte)(35)))));
            this.AddConfig.FlatAppearance.BorderSize = 0;
            this.AddConfig.FlatStyle = System.Windows.Forms.FlatStyle.Flat;
            this.AddConfig.Image = ((System.Drawing.Image)(resources.GetObject("AddConfig.Image")));
            this.AddConfig.Location = new System.Drawing.Point(0, 0);
            this.AddConfig.Name = "AddConfig";
            this.AddConfig.Size = new System.Drawing.Size(66, 35);
            this.AddConfig.TabIndex = 5;
            this.AddConfig.UseVisualStyleBackColor = false;
            this.AddConfig.Click += new System.EventHandler(this.AddConfig_Click);
            // 
            // RemoveConfig
            // 
            this.RemoveConfig.BackColor = System.Drawing.Color.FromArgb(((int)(((byte)(35)))), ((int)(((byte)(35)))), ((int)(((byte)(35)))));
            this.RemoveConfig.Dock = System.Windows.Forms.DockStyle.Right;
            this.RemoveConfig.FlatAppearance.BorderColor = System.Drawing.Color.FromArgb(((int)(((byte)(35)))), ((int)(((byte)(35)))), ((int)(((byte)(35)))));
            this.RemoveConfig.FlatAppearance.BorderSize = 0;
            this.RemoveConfig.FlatStyle = System.Windows.Forms.FlatStyle.Flat;
            this.RemoveConfig.Image = ((System.Drawing.Image)(resources.GetObject("RemoveConfig.Image")));
            this.RemoveConfig.Location = new System.Drawing.Point(134, 0);
            this.RemoveConfig.Name = "RemoveConfig";
            this.RemoveConfig.Size = new System.Drawing.Size(66, 35);
            this.RemoveConfig.TabIndex = 6;
            this.RemoveConfig.UseVisualStyleBackColor = false;
            this.RemoveConfig.Click += new System.EventHandler(this.RemoveConfig_Click);
            // 
            // tray
            // 
            this.tray.Icon = ((System.Drawing.Icon)(resources.GetObject("tray.Icon")));
            this.tray.Text = "EpexGUI\r\nNot Connected";
            this.tray.Visible = true;
            this.tray.Click += new System.EventHandler(this.EpexGUI_Click);
            // 
            // panel1
            // 
            this.panel1.Controls.Add(this.EditConfig);
            this.panel1.Controls.Add(this.RemoveConfig);
            this.panel1.Controls.Add(this.AddConfig);
            this.panel1.Location = new System.Drawing.Point(12, 377);
            this.panel1.Name = "panel1";
            this.panel1.Size = new System.Drawing.Size(200, 35);
            this.panel1.TabIndex = 7;
            // 
            // EditConfig
            // 
            this.EditConfig.BackColor = System.Drawing.Color.FromArgb(((int)(((byte)(35)))), ((int)(((byte)(35)))), ((int)(((byte)(35)))));
            this.EditConfig.Dock = System.Windows.Forms.DockStyle.Fill;
            this.EditConfig.FlatAppearance.BorderColor = System.Drawing.Color.FromArgb(((int)(((byte)(35)))), ((int)(((byte)(35)))), ((int)(((byte)(35)))));
            this.EditConfig.FlatAppearance.BorderSize = 0;
            this.EditConfig.FlatStyle = System.Windows.Forms.FlatStyle.Flat;
            this.EditConfig.Image = ((System.Drawing.Image)(resources.GetObject("EditConfig.Image")));
            this.EditConfig.Location = new System.Drawing.Point(66, 0);
            this.EditConfig.Name = "EditConfig";
            this.EditConfig.Size = new System.Drawing.Size(68, 35);
            this.EditConfig.TabIndex = 8;
            this.EditConfig.Text = " ";
            this.EditConfig.UseVisualStyleBackColor = false;
            this.EditConfig.Click += new System.EventHandler(this.EditConfig_Click);
            // 
            // ConnectButton
            // 
            this.ConnectButton.BackColor = System.Drawing.Color.FromArgb(((int)(((byte)(35)))), ((int)(((byte)(35)))), ((int)(((byte)(35)))));
            this.ConnectButton.FlatAppearance.BorderColor = System.Drawing.Color.FromArgb(((int)(((byte)(35)))), ((int)(((byte)(35)))), ((int)(((byte)(35)))));
            this.ConnectButton.FlatAppearance.BorderSize = 0;
            this.ConnectButton.FlatStyle = System.Windows.Forms.FlatStyle.Flat;
            this.ConnectButton.Font = new System.Drawing.Font("Segoe UI", 12F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.ConnectButton.ForeColor = System.Drawing.Color.White;
            this.ConnectButton.Location = new System.Drawing.Point(12, 418);
            this.ConnectButton.Name = "ConnectButton";
            this.ConnectButton.Size = new System.Drawing.Size(200, 35);
            this.ConnectButton.TabIndex = 8;
            this.ConnectButton.Text = "Connect";
            this.ConnectButton.UseVisualStyleBackColor = false;
            this.ConnectButton.Click += new System.EventHandler(this.ConnectButton_Click);
            // 
            // SettingsBtn
            // 
            this.SettingsBtn.BackColor = System.Drawing.Color.FromArgb(((int)(((byte)(35)))), ((int)(((byte)(35)))), ((int)(((byte)(35)))));
            this.SettingsBtn.FlatAppearance.BorderColor = System.Drawing.Color.FromArgb(((int)(((byte)(35)))), ((int)(((byte)(35)))), ((int)(((byte)(35)))));
            this.SettingsBtn.FlatAppearance.BorderSize = 0;
            this.SettingsBtn.FlatStyle = System.Windows.Forms.FlatStyle.Flat;
            this.SettingsBtn.Font = new System.Drawing.Font("Segoe UI", 12F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.SettingsBtn.ForeColor = System.Drawing.Color.White;
            this.SettingsBtn.Image = ((System.Drawing.Image)(resources.GetObject("SettingsBtn.Image")));
            this.SettingsBtn.Location = new System.Drawing.Point(218, 418);
            this.SettingsBtn.Name = "SettingsBtn";
            this.SettingsBtn.Size = new System.Drawing.Size(35, 35);
            this.SettingsBtn.TabIndex = 9;
            this.SettingsBtn.TabStop = false;
            this.SettingsBtn.UseVisualStyleBackColor = false;
            this.SettingsBtn.Click += new System.EventHandler(this.SettingsBtn_Click);
            // 
            // LogBox
            // 
            this.LogBox.AcceptsReturn = true;
            this.LogBox.AcceptsTab = true;
            this.LogBox.BackColor = System.Drawing.Color.FromArgb(((int)(((byte)(35)))), ((int)(((byte)(35)))), ((int)(((byte)(35)))));
            this.LogBox.BorderStyle = System.Windows.Forms.BorderStyle.None;
            this.LogBox.Font = new System.Drawing.Font("Segoe UI", 9.75F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.LogBox.ForeColor = System.Drawing.Color.Gainsboro;
            this.LogBox.Location = new System.Drawing.Point(218, 35);
            this.LogBox.Multiline = true;
            this.LogBox.Name = "LogBox";
            this.LogBox.ReadOnly = true;
            this.LogBox.ScrollBars = System.Windows.Forms.ScrollBars.Vertical;
            this.LogBox.Size = new System.Drawing.Size(499, 377);
            this.LogBox.TabIndex = 10;
            this.LogBox.TabStop = false;
            // 
            // ConnectedToLabel
            // 
            this.ConnectedToLabel.Font = new System.Drawing.Font("Segoe UI", 12F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.ConnectedToLabel.ForeColor = System.Drawing.Color.White;
            this.ConnectedToLabel.Location = new System.Drawing.Point(218, 9);
            this.ConnectedToLabel.Name = "ConnectedToLabel";
            this.ConnectedToLabel.Size = new System.Drawing.Size(499, 23);
            this.ConnectedToLabel.TabIndex = 11;
            this.ConnectedToLabel.Text = "Not connected";
            this.ConnectedToLabel.TextAlign = System.Drawing.ContentAlignment.MiddleCenter;
            // 
            // LabelUpdater
            // 
            this.LabelUpdater.Interval = 10;
            this.LabelUpdater.Tick += new System.EventHandler(this.LabelUpdater_Tick);
            // 
            // Main
            // 
            this.AutoScaleDimensions = new System.Drawing.SizeF(6F, 13F);
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            this.BackColor = System.Drawing.Color.FromArgb(((int)(((byte)(26)))), ((int)(((byte)(26)))), ((int)(((byte)(26)))));
            this.ClientSize = new System.Drawing.Size(723, 463);
            this.Controls.Add(this.ConnectedToLabel);
            this.Controls.Add(this.LogBox);
            this.Controls.Add(this.SettingsBtn);
            this.Controls.Add(this.ConnectButton);
            this.Controls.Add(this.panel1);
            this.Controls.Add(this.label1);
            this.Controls.Add(this.ConfigList);
            this.FormBorderStyle = System.Windows.Forms.FormBorderStyle.FixedSingle;
            this.Icon = ((System.Drawing.Icon)(resources.GetObject("$this.Icon")));
            this.MaximizeBox = false;
            this.Name = "Main";
            this.StartPosition = System.Windows.Forms.FormStartPosition.CenterScreen;
            this.Text = "EpexGUI";
            this.FormClosing += new System.Windows.Forms.FormClosingEventHandler(this.Main_FormClosing);
            this.panel1.ResumeLayout(false);
            this.ResumeLayout(false);
            this.PerformLayout();

        }

        #endregion
        private System.Windows.Forms.ImageList imageList1;
        private System.Windows.Forms.ListBox ConfigList;
        private System.Windows.Forms.Label label1;
        private System.Windows.Forms.Button AddConfig;
        private System.Windows.Forms.Button RemoveConfig;
        private System.Windows.Forms.NotifyIcon tray;
        private Panel panel1;
        private Button EditConfig;
        private Button ConnectButton;
        private Button SettingsBtn;
        private TextBox LogBox;
        private Label ConnectedToLabel;
        private Timer LabelUpdater;
    }
}

