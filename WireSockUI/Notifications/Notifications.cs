﻿using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;
using System.Xml.Linq;
using Windows.Data.Xml.Dom;
using Windows.UI.Notifications;
using WireSockUI.Native;
using WireSockUI.Properties;

namespace WireSockUI.Notifications
{
    internal static class Notifications
    {
        private static readonly string Icon;

        static Notifications()
        {
            // Write the icon to local appdata folder for toast notifications
            Icon = $@"{Global.MainFolder}\WireSock.ico";

            if (File.Exists(Icon)) return;

            using (var stream = new FileStream(Icon, FileMode.CreateNew))
            {
                Resources.ico.Save(stream);
            }
        }

        private static XmlDocument GetXml(string title, string body)
        {
            var toast =
                new XElement("toast",
                    new XElement("visual",
                        new XElement("binding",
                            new XAttribute("template", "ToastGeneric"),
                            new XElement("text", title),
                            new XElement("text", body),
                            new XElement("image",
                                new XAttribute("src", Icon),
                                new XAttribute("placement", "appLogoOverride"),
                                new XAttribute("hint-crop", "circle")))));

            var xml = new XmlDocument();
            xml.LoadXml(toast.ToString());

            return xml;
        }

        public static void Notify(string title, string body)
        {
            var context = WindowsApplicationContext.FromCurrentProcess();
            var notifier = ToastNotificationManager.CreateToastNotifier(context.AppUserModelId);

            var notification = new ToastNotification(GetXml(title, body));

            notification.Activated += Notification_Activated;
            notification.Dismissed += Notification_Dismissed;
            notification.Failed += Notification_Failed;

            notifier.Show(notification);
        }

        private static void Notification_Failed(ToastNotification sender, ToastFailedEventArgs args)
        {
            Debug.WriteLine($"Notification failed: {args.ErrorCode}");
        }

        private static void Notification_Dismissed(ToastNotification sender, ToastDismissedEventArgs args)
        {
            switch (args.Reason)
            {
                case ToastDismissalReason.ApplicationHidden:
                    Debug.WriteLine("Notification dismissed: Application hidden");
                    break;
                case ToastDismissalReason.UserCanceled:
                    Debug.WriteLine("Notification dismissed: User cancelled");
                    break;
                case ToastDismissalReason.TimedOut:
                    Debug.WriteLine("Notification dismissed: Timed out");
                    break;
            }
        }

        private static void Notification_Activated(ToastNotification sender, object args)
        {
            foreach (Form form in Application.OpenForms)
                if (form.Name == "frmMain")
                    form.BeginInvoke((Action)(() =>
                    {
                        form.Show();
                        form.WindowState = FormWindowState.Normal;
                    }));
        }
    }
}