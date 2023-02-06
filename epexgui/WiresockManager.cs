using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace epexgui
{
    internal class WiresockManager
    {
        private TextBox OutBox;
        public bool Connected = false;
        private Process wiresock;
        Main main;
        bool ForceKill = false;
        public WiresockManager(TextBox output) 
        {
            OutBox = output;
        }

        public void Connect(string configPath, Main mainform)
        {
            main = mainform;
            wiresock = new Process();
            ProcessStartInfo startInfo = new ProcessStartInfo();
            startInfo.Arguments = $@"run -config ""{configPath}"" -log-level debug -lac";
            startInfo.FileName = Global.WireSock;
            startInfo.Verb = "runas";
            startInfo.UseShellExecute = false;
            startInfo.RedirectStandardOutput = true;
            startInfo.RedirectStandardError = true;
            startInfo.CreateNoWindow = true;
            wiresock.EnableRaisingEvents = true;
            AppDomain.CurrentDomain.DomainUnload += (s, e) => { Kill(); };
            AppDomain.CurrentDomain.ProcessExit += (s, e) => { Kill(); };
            AppDomain.CurrentDomain.UnhandledException += (s, e) => { Kill(); };
            wiresock.Exited += delegate (object sender, EventArgs args)
            {
                if (ForceKill)
                {
                    ForceKill = false;
                    return;
                }
                MessageBox.Show("Wiresock process exited!", "Warning", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                main.Invoke((MethodInvoker)delegate
                {
                    main.Disconnect();
                });
            };
            wiresock.StartInfo = startInfo;
            wiresock.OutputDataReceived += new DataReceivedEventHandler((sender, e) =>
            {
                if (!String.IsNullOrEmpty(e.Data))
                {
                    if (e.Data.Contains("Wireguard tunnel has been started"))
                    {
                        Connected = true;
                    }
                    if (e.Data.Contains("WireSock WireGuard VPN Client is running already"))
                    {
                        KillOther();
                        Kill();
                        Connect(configPath, mainform);
                    }
                    if (e.Data.Contains("Endpoint is either invalid of failed to resolve"))
                    {
                        MessageBox.Show("Endpoint is either invalid of failed to resolve", "Invalid configuration", MessageBoxButtons.OK, MessageBoxIcon.Error);
                        wiresock.CancelOutputRead();
                        main.Invoke((MethodInvoker)delegate
                        {
                            main.Disconnect();
                        });
                    }
                    if (e.Data.Contains("Tunnel has failed to start"))
                    {
                        MessageBox.Show("Tunnel has failed to start. Please check log", "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
                        wiresock.CancelOutputRead();
                        main.Invoke((MethodInvoker)delegate
                        {
                            main.Disconnect();
                        });
                    }
                    if (e.Data.Contains("Failed to initialize Wireguard tunnel"))
                    {
                        MessageBox.Show("Failed to initialize Wireguard tunnel. Please check log", "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
                        wiresock.CancelOutputRead();
                        main.Invoke((MethodInvoker)delegate
                        {
                            main.Disconnect();
                        });
                    }
                    OutBox.Invoke((MethodInvoker)delegate
                    {
                        if (OutBox.Text.Length + e.Data.Length >= OutBox.MaxLength) OutBox.Clear();
                        OutBox.AppendText(e.Data);
                        OutBox.AppendText(Environment.NewLine);
                    });
                }
            });
            wiresock.Start();
            wiresock.BeginOutputReadLine();
        }

        public void Kill()
        {
            Connected = false;
            try
            {
                ForceKill = true;
                wiresock.Kill();
            }
            catch { }
        }

        private void KillOther()
        {
            ForceKill = true;
            foreach (var process in Process.GetProcessesByName("wiresock-client"))
            {
                process.Kill();
            }
        }
    }
}
