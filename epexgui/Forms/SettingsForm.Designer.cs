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
            this.SuspendLayout();
            // 
            // autorun
            // 
            this.autorun.AutoSize = true;
            this.autorun.Font = new System.Drawing.Font("Segoe UI", 12F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.autorun.ForeColor = System.Drawing.Color.White;
            this.autorun.Location = new System.Drawing.Point(12, 12);
            this.autorun.Name = "autorun";
            this.autorun.Size = new System.Drawing.Size(272, 25);
            this.autorun.TabIndex = 0;
            this.autorun.Text = "Run EpexGUI when Windows starts";
            this.autorun.UseVisualStyleBackColor = true;
            // 
            // MinimizeOnStart
            // 
            this.MinimizeOnStart.AutoSize = true;
            this.MinimizeOnStart.Font = new System.Drawing.Font("Segoe UI", 12F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.MinimizeOnStart.ForeColor = System.Drawing.Color.White;
            this.MinimizeOnStart.Location = new System.Drawing.Point(12, 43);
            this.MinimizeOnStart.Name = "MinimizeOnStart";
            this.MinimizeOnStart.Size = new System.Drawing.Size(199, 25);
            this.MinimizeOnStart.TabIndex = 1;
            this.MinimizeOnStart.Text = "Minimize to tray on start";
            this.MinimizeOnStart.UseVisualStyleBackColor = true;
            // 
            // ConnectOnStart
            // 
            this.ConnectOnStart.AutoSize = true;
            this.ConnectOnStart.Font = new System.Drawing.Font("Segoe UI", 12F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.ConnectOnStart.ForeColor = System.Drawing.Color.White;
            this.ConnectOnStart.Location = new System.Drawing.Point(12, 74);
            this.ConnectOnStart.Name = "ConnectOnStart";
            this.ConnectOnStart.Size = new System.Drawing.Size(143, 25);
            this.ConnectOnStart.TabIndex = 2;
            this.ConnectOnStart.Text = "Connect on start";
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
            this.SaveBtn.Location = new System.Drawing.Point(12, 114);
            this.SaveBtn.Name = "SaveBtn";
            this.SaveBtn.Size = new System.Drawing.Size(75, 35);
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
            this.OpenFolder.Location = new System.Drawing.Point(93, 114);
            this.OpenFolder.Name = "OpenFolder";
            this.OpenFolder.Size = new System.Drawing.Size(179, 35);
            this.OpenFolder.TabIndex = 4;
            this.OpenFolder.TabStop = false;
            this.OpenFolder.Text = "Open EpexGUI folder";
            this.OpenFolder.UseVisualStyleBackColor = false;
            this.OpenFolder.Click += new System.EventHandler(this.OpenFolder_Click);
            // 
            // SettingsForm
            // 
            this.AutoScaleDimensions = new System.Drawing.SizeF(6F, 13F);
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            this.BackColor = System.Drawing.Color.FromArgb(((int)(((byte)(26)))), ((int)(((byte)(26)))), ((int)(((byte)(26)))));
            this.ClientSize = new System.Drawing.Size(284, 161);
            this.Controls.Add(this.OpenFolder);
            this.Controls.Add(this.SaveBtn);
            this.Controls.Add(this.ConnectOnStart);
            this.Controls.Add(this.MinimizeOnStart);
            this.Controls.Add(this.autorun);
            this.FormBorderStyle = System.Windows.Forms.FormBorderStyle.FixedSingle;
            this.Icon = ((System.Drawing.Icon)(resources.GetObject("$this.Icon")));
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
        private System.Windows.Forms.Button SaveBtn;
        private System.Windows.Forms.Button OpenFolder;
    }
}