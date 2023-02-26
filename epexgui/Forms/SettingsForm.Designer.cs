namespace epexgui.Forms
{
    partial class SettingsForm
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
            System.ComponentModel.ComponentResourceManager resources = new System.ComponentModel.ComponentResourceManager(typeof(SettingsForm));
            this.autorun = new System.Windows.Forms.CheckBox();
            this.MinimizeOnStart = new System.Windows.Forms.CheckBox();
            this.ConnectOnStart = new System.Windows.Forms.CheckBox();
            this.SaveBtn = new System.Windows.Forms.Button();
            this.OpenFolder = new System.Windows.Forms.Button();
            this.EnableDebugLog = new System.Windows.Forms.CheckBox();
            this.VirtualAdapterMode = new System.Windows.Forms.CheckBox();
            this.SuspendLayout();
            // 
            // autorun
            // 
            this.autorun.AutoSize = true;
            this.autorun.Font = new System.Drawing.Font("Segoe UI", 12F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.autorun.ForeColor = System.Drawing.Color.White;
            this.autorun.Location = new System.Drawing.Point(16, 15);
            this.autorun.Margin = new System.Windows.Forms.Padding(4);
            this.autorun.Name = "autorun";
            this.autorun.Size = new System.Drawing.Size(336, 32);
            this.autorun.TabIndex = 0;
            this.autorun.Text = "Run EpexGUI when Windows starts";
            this.autorun.UseVisualStyleBackColor = true;
            // 
            // MinimizeOnStart
            // 
            this.MinimizeOnStart.AutoSize = true;
            this.MinimizeOnStart.Font = new System.Drawing.Font("Segoe UI", 12F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.MinimizeOnStart.ForeColor = System.Drawing.Color.White;
            this.MinimizeOnStart.Location = new System.Drawing.Point(16, 53);
            this.MinimizeOnStart.Margin = new System.Windows.Forms.Padding(4);
            this.MinimizeOnStart.Name = "MinimizeOnStart";
            this.MinimizeOnStart.Size = new System.Drawing.Size(252, 32);
            this.MinimizeOnStart.TabIndex = 1;
            this.MinimizeOnStart.Text = "Minimize to Tray on Start";
            this.MinimizeOnStart.UseVisualStyleBackColor = true;
            // 
            // ConnectOnStart
            // 
            this.ConnectOnStart.AutoSize = true;
            this.ConnectOnStart.Font = new System.Drawing.Font("Segoe UI", 12F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.ConnectOnStart.ForeColor = System.Drawing.Color.White;
            this.ConnectOnStart.Location = new System.Drawing.Point(16, 91);
            this.ConnectOnStart.Margin = new System.Windows.Forms.Padding(4);
            this.ConnectOnStart.Name = "ConnectOnStart";
            this.ConnectOnStart.Size = new System.Drawing.Size(180, 32);
            this.ConnectOnStart.TabIndex = 2;
            this.ConnectOnStart.Text = "Connect on Start";
            this.ConnectOnStart.UseVisualStyleBackColor = true;
            // 
            // SaveBtn
            // 
            this.SaveBtn.BackColor = System.Drawing.Color.FromArgb(((int)(((byte)(35)))), ((int)(((byte)(35)))), ((int)(((byte)(35)))));
            this.SaveBtn.FlatAppearance.BorderColor = System.Drawing.Color.FromArgb(((int)(((byte)(35)))), ((int)(((byte)(35)))), ((int)(((byte)(35)))));
            this.SaveBtn.FlatAppearance.BorderSize = 0;
            this.SaveBtn.FlatStyle = System.Windows.Forms.FlatStyle.Flat;
            this.SaveBtn.Font = new System.Drawing.Font("Segoe UI", 12F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.SaveBtn.ForeColor = System.Drawing.Color.White;
            this.SaveBtn.Location = new System.Drawing.Point(16, 225);
            this.SaveBtn.Margin = new System.Windows.Forms.Padding(4);
            this.SaveBtn.Name = "SaveBtn";
            this.SaveBtn.Size = new System.Drawing.Size(100, 43);
            this.SaveBtn.TabIndex = 3;
            this.SaveBtn.TabStop = false;
            this.SaveBtn.Text = "Save";
            this.SaveBtn.UseVisualStyleBackColor = false;
            this.SaveBtn.Click += new System.EventHandler(this.SaveBtn_Click);
            // 
            // OpenFolder
            // 
            this.OpenFolder.BackColor = System.Drawing.Color.FromArgb(((int)(((byte)(35)))), ((int)(((byte)(35)))), ((int)(((byte)(35)))));
            this.OpenFolder.FlatAppearance.BorderColor = System.Drawing.Color.FromArgb(((int)(((byte)(35)))), ((int)(((byte)(35)))), ((int)(((byte)(35)))));
            this.OpenFolder.FlatAppearance.BorderSize = 0;
            this.OpenFolder.FlatStyle = System.Windows.Forms.FlatStyle.Flat;
            this.OpenFolder.Font = new System.Drawing.Font("Segoe UI", 12F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.OpenFolder.ForeColor = System.Drawing.Color.White;
            this.OpenFolder.Location = new System.Drawing.Point(124, 225);
            this.OpenFolder.Margin = new System.Windows.Forms.Padding(4);
            this.OpenFolder.Name = "OpenFolder";
            this.OpenFolder.Size = new System.Drawing.Size(239, 43);
            this.OpenFolder.TabIndex = 4;
            this.OpenFolder.TabStop = false;
            this.OpenFolder.Text = "Open EpexGUI folder";
            this.OpenFolder.UseVisualStyleBackColor = false;
            this.OpenFolder.Click += new System.EventHandler(this.OpenFolder_Click);
            // 
            // EnableDebugLog
            // 
            this.EnableDebugLog.AutoSize = true;
            this.EnableDebugLog.Font = new System.Drawing.Font("Segoe UI", 12F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.EnableDebugLog.ForeColor = System.Drawing.Color.White;
            this.EnableDebugLog.Location = new System.Drawing.Point(16, 131);
            this.EnableDebugLog.Margin = new System.Windows.Forms.Padding(4);
            this.EnableDebugLog.Name = "EnableDebugLog";
            this.EnableDebugLog.Size = new System.Drawing.Size(194, 32);
            this.EnableDebugLog.TabIndex = 5;
            this.EnableDebugLog.Text = "Enable Debug Log";
            this.EnableDebugLog.UseVisualStyleBackColor = true;
            // 
            // VirtualAdapterMode
            // 
            this.VirtualAdapterMode.AutoSize = true;
            this.VirtualAdapterMode.Font = new System.Drawing.Font("Segoe UI", 12F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.VirtualAdapterMode.ForeColor = System.Drawing.Color.White;
            this.VirtualAdapterMode.Location = new System.Drawing.Point(16, 171);
            this.VirtualAdapterMode.Margin = new System.Windows.Forms.Padding(4);
            this.VirtualAdapterMode.Name = "VirtualAdapterMode";
            this.VirtualAdapterMode.Size = new System.Drawing.Size(304, 32);
            this.VirtualAdapterMode.TabIndex = 6;
            this.VirtualAdapterMode.Text = "Virtual Network Adapter Mode";
            this.VirtualAdapterMode.UseVisualStyleBackColor = true;
            // 
            // SettingsForm
            // 
            this.AutoScaleDimensions = new System.Drawing.SizeF(8F, 16F);
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            this.BackColor = System.Drawing.Color.FromArgb(((int)(((byte)(26)))), ((int)(((byte)(26)))), ((int)(((byte)(26)))));
            this.ClientSize = new System.Drawing.Size(379, 279);
            this.Controls.Add(this.VirtualAdapterMode);
            this.Controls.Add(this.EnableDebugLog);
            this.Controls.Add(this.OpenFolder);
            this.Controls.Add(this.SaveBtn);
            this.Controls.Add(this.ConnectOnStart);
            this.Controls.Add(this.MinimizeOnStart);
            this.Controls.Add(this.autorun);
            this.FormBorderStyle = System.Windows.Forms.FormBorderStyle.FixedSingle;
            this.Icon = ((System.Drawing.Icon)(resources.GetObject("$this.Icon")));
            this.Margin = new System.Windows.Forms.Padding(4);
            this.MaximizeBox = false;
            this.MinimizeBox = false;
            this.Name = "SettingsForm";
            this.StartPosition = System.Windows.Forms.FormStartPosition.CenterParent;
            this.Text = "Settings";
            this.ResumeLayout(false);
            this.PerformLayout();

        }

        #endregion

        private System.Windows.Forms.CheckBox autorun;
        private System.Windows.Forms.CheckBox MinimizeOnStart;
        private System.Windows.Forms.CheckBox ConnectOnStart;
        private System.Windows.Forms.CheckBox EnableDebugLog;
        private System.Windows.Forms.Button SaveBtn;
        private System.Windows.Forms.Button OpenFolder;
        private System.Windows.Forms.CheckBox VirtualAdapterMode;
    }
}