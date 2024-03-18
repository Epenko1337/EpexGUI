﻿namespace WireSockUI.Forms
{
    sealed partial class FrmEdit
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
            this.pnlTop = new System.Windows.Forms.Panel();
            this.tableLayoutPanel1 = new System.Windows.Forms.TableLayoutPanel();
            this.lblPublicKey = new System.Windows.Forms.Label();
            this.txtPublicKey = new System.Windows.Forms.TextBox();
            this.txtProfileName = new System.Windows.Forms.TextBox();
            this.lblName = new System.Windows.Forms.Label();
            this.pnlBottom = new System.Windows.Forms.Panel();
            this.btnProcessList = new System.Windows.Forms.Button();
            this.btnSave = new System.Windows.Forms.Button();
            this.btnCancel = new System.Windows.Forms.Button();
            this.txtEditor = new System.Windows.Forms.RichTextBox();
            this.resControls = new WireSockUI.Extensions.ControlTextExtender();
            this.pnlTop.SuspendLayout();
            this.tableLayoutPanel1.SuspendLayout();
            this.pnlBottom.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.resControls)).BeginInit();
            this.SuspendLayout();
            // 
            // pnlTop
            // 
            this.pnlTop.Controls.Add(this.tableLayoutPanel1);
            this.pnlTop.Dock = System.Windows.Forms.DockStyle.Top;
            this.pnlTop.Location = new System.Drawing.Point(0, 0);
            this.pnlTop.Name = "pnlTop";
            this.resControls.SetResourceKey(this.pnlTop, null);
            this.pnlTop.Size = new System.Drawing.Size(664, 40);
            this.pnlTop.TabIndex = 43;
            // 
            // tableLayoutPanel1
            // 
            this.tableLayoutPanel1.ColumnCount = 2;
            this.tableLayoutPanel1.ColumnStyles.Add(new System.Windows.Forms.ColumnStyle(System.Windows.Forms.SizeType.Absolute, 130F));
            this.tableLayoutPanel1.ColumnStyles.Add(new System.Windows.Forms.ColumnStyle());
            this.tableLayoutPanel1.Controls.Add(this.lblPublicKey, 0, 1);
            this.tableLayoutPanel1.Controls.Add(this.txtPublicKey, 1, 1);
            this.tableLayoutPanel1.Controls.Add(this.txtProfileName, 1, 0);
            this.tableLayoutPanel1.Controls.Add(this.lblName, 0, 0);
            this.tableLayoutPanel1.Dock = System.Windows.Forms.DockStyle.Fill;
            this.tableLayoutPanel1.Location = new System.Drawing.Point(0, 0);
            this.tableLayoutPanel1.Name = "tableLayoutPanel1";
            this.resControls.SetResourceKey(this.tableLayoutPanel1, null);
            this.tableLayoutPanel1.RowCount = 2;
            this.tableLayoutPanel1.RowStyles.Add(new System.Windows.Forms.RowStyle(System.Windows.Forms.SizeType.Absolute, 20F));
            this.tableLayoutPanel1.RowStyles.Add(new System.Windows.Forms.RowStyle(System.Windows.Forms.SizeType.Absolute, 20F));
            this.tableLayoutPanel1.Size = new System.Drawing.Size(664, 40);
            this.tableLayoutPanel1.TabIndex = 0;
            // 
            // lblPublicKey
            // 
            this.lblPublicKey.Anchor = ((System.Windows.Forms.AnchorStyles)((((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Bottom) 
            | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.lblPublicKey.AutoSize = true;
            this.lblPublicKey.Location = new System.Drawing.Point(3, 20);
            this.lblPublicKey.Name = "lblPublicKey";
            this.lblPublicKey.Padding = new System.Windows.Forms.Padding(0, 3, 0, 0);
            this.resControls.SetResourceKey(this.lblPublicKey, "EditPublicKey");
            this.lblPublicKey.Size = new System.Drawing.Size(124, 20);
            this.lblPublicKey.TabIndex = 27;
            this.lblPublicKey.Text = "Public key:";
            this.lblPublicKey.TextAlign = System.Drawing.ContentAlignment.TopRight;
            // 
            // txtPublicKey
            // 
            this.txtPublicKey.BackColor = System.Drawing.SystemColors.Control;
            this.txtPublicKey.BorderStyle = System.Windows.Forms.BorderStyle.None;
            this.txtPublicKey.Dock = System.Windows.Forms.DockStyle.Fill;
            this.txtPublicKey.Location = new System.Drawing.Point(133, 24);
            this.txtPublicKey.Margin = new System.Windows.Forms.Padding(3, 4, 10, 4);
            this.txtPublicKey.Multiline = true;
            this.txtPublicKey.Name = "txtPublicKey";
            this.txtPublicKey.ReadOnly = true;
            this.resControls.SetResourceKey(this.txtPublicKey, null);
            this.txtPublicKey.Size = new System.Drawing.Size(521, 12);
            this.txtPublicKey.TabIndex = 26;
            // 
            // txtProfileName
            // 
            this.txtProfileName.BorderStyle = System.Windows.Forms.BorderStyle.None;
            this.txtProfileName.Dock = System.Windows.Forms.DockStyle.Fill;
            this.txtProfileName.Location = new System.Drawing.Point(133, 4);
            this.txtProfileName.Margin = new System.Windows.Forms.Padding(3, 4, 10, 4);
            this.txtProfileName.Name = "txtProfileName";
            this.resControls.SetResourceKey(this.txtProfileName, null);
            this.txtProfileName.Size = new System.Drawing.Size(521, 13);
            this.txtProfileName.TabIndex = 25;
            // 
            // lblName
            // 
            this.lblName.Anchor = ((System.Windows.Forms.AnchorStyles)((((System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Bottom) 
            | System.Windows.Forms.AnchorStyles.Left) 
            | System.Windows.Forms.AnchorStyles.Right)));
            this.lblName.AutoSize = true;
            this.lblName.Location = new System.Drawing.Point(3, 0);
            this.lblName.Name = "lblName";
            this.resControls.SetResourceKey(this.lblName, "EditName");
            this.lblName.Size = new System.Drawing.Size(124, 20);
            this.lblName.TabIndex = 19;
            this.lblName.Text = "Name:";
            this.lblName.TextAlign = System.Drawing.ContentAlignment.MiddleRight;
            // 
            // pnlBottom
            // 
            this.pnlBottom.Controls.Add(this.btnProcessList);
            this.pnlBottom.Controls.Add(this.btnSave);
            this.pnlBottom.Controls.Add(this.btnCancel);
            this.pnlBottom.Dock = System.Windows.Forms.DockStyle.Bottom;
            this.pnlBottom.Location = new System.Drawing.Point(0, 392);
            this.pnlBottom.Name = "pnlBottom";
            this.resControls.SetResourceKey(this.pnlBottom, null);
            this.pnlBottom.Size = new System.Drawing.Size(664, 35);
            this.pnlBottom.TabIndex = 45;
            // 
            // btnProcessList
            // 
            this.btnProcessList.ImageAlign = System.Drawing.ContentAlignment.MiddleLeft;
            this.btnProcessList.Location = new System.Drawing.Point(6, 6);
            this.btnProcessList.Name = "btnProcessList";
            this.resControls.SetResourceKey(this.btnProcessList, "EditProcesses");
            this.btnProcessList.Size = new System.Drawing.Size(75, 23);
            this.btnProcessList.TabIndex = 2;
            this.btnProcessList.Text = "Processes...";
            this.btnProcessList.TextImageRelation = System.Windows.Forms.TextImageRelation.ImageBeforeText;
            this.btnProcessList.UseVisualStyleBackColor = true;
            this.btnProcessList.Click += new System.EventHandler(this.OnProcessClick);
            // 
            // btnSave
            // 
            this.btnSave.DialogResult = System.Windows.Forms.DialogResult.OK;
            this.btnSave.Location = new System.Drawing.Point(497, 6);
            this.btnSave.Name = "btnSave";
            this.resControls.SetResourceKey(this.btnSave, "EditSave");
            this.btnSave.Size = new System.Drawing.Size(75, 23);
            this.btnSave.TabIndex = 1;
            this.btnSave.Text = "Save";
            this.btnSave.UseVisualStyleBackColor = true;
            this.btnSave.Click += new System.EventHandler(this.OnSaveClick);
            // 
            // btnCancel
            // 
            this.btnCancel.DialogResult = System.Windows.Forms.DialogResult.Cancel;
            this.btnCancel.Location = new System.Drawing.Point(580, 6);
            this.btnCancel.Name = "btnCancel";
            this.resControls.SetResourceKey(this.btnCancel, "EditCancel");
            this.btnCancel.Size = new System.Drawing.Size(75, 23);
            this.btnCancel.TabIndex = 0;
            this.btnCancel.Text = "Cancel";
            this.btnCancel.UseVisualStyleBackColor = true;
            // 
            // txtEditor
            // 
            this.txtEditor.BorderStyle = System.Windows.Forms.BorderStyle.FixedSingle;
            this.txtEditor.DetectUrls = false;
            this.txtEditor.Dock = System.Windows.Forms.DockStyle.Fill;
            this.txtEditor.Font = new System.Drawing.Font("Courier New", 9.75F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.txtEditor.Location = new System.Drawing.Point(0, 40);
            this.txtEditor.Name = "txtEditor";
            this.resControls.SetResourceKey(this.txtEditor, null);
            this.txtEditor.Size = new System.Drawing.Size(664, 352);
            this.txtEditor.TabIndex = 46;
            this.txtEditor.Text = "";
            this.txtEditor.TextChanged += new System.EventHandler(this.OnProfileChanged);
            // 
            // resControls
            // 
            this.resControls.ResourceClassName = "WireSockUI.Properties.Resources";
            // 
            // FrmEdit
            // 
            this.AutoScaleDimensions = new System.Drawing.SizeF(6F, 13F);
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            this.CancelButton = this.btnCancel;
            this.ClientSize = new System.Drawing.Size(664, 427);
            this.Controls.Add(this.txtEditor);
            this.Controls.Add(this.pnlTop);
            this.Controls.Add(this.pnlBottom);
            this.FormBorderStyle = System.Windows.Forms.FormBorderStyle.FixedSingle;
            this.MaximizeBox = false;
            this.MinimizeBox = false;
            this.Name = "FrmEdit";
            this.resControls.SetResourceKey(this, null);
            this.StartPosition = System.Windows.Forms.FormStartPosition.CenterParent;
            this.Text = "Edit";
            this.pnlTop.ResumeLayout(false);
            this.tableLayoutPanel1.ResumeLayout(false);
            this.tableLayoutPanel1.PerformLayout();
            this.pnlBottom.ResumeLayout(false);
            ((System.ComponentModel.ISupportInitialize)(this.resControls)).EndInit();
            this.ResumeLayout(false);

        }

        #endregion
        private System.Windows.Forms.Panel pnlTop;
        private System.Windows.Forms.TableLayoutPanel tableLayoutPanel1;
        private System.Windows.Forms.Label lblName;
        private System.Windows.Forms.TextBox txtProfileName;
        private System.Windows.Forms.TextBox txtPublicKey;
        private System.Windows.Forms.Label lblPublicKey;
        private System.Windows.Forms.Panel pnlBottom;
        private System.Windows.Forms.Button btnSave;
        private System.Windows.Forms.Button btnCancel;
        private System.Windows.Forms.RichTextBox txtEditor;
        private System.Windows.Forms.Button btnProcessList;
        private Extensions.ControlTextExtender resControls;
    }
}