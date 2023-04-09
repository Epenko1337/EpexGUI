using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;
using System.Xml.Linq;
using Windows.UI.Notifications;
using WireSockUI.Properties;

namespace WireSockUI.Native
{
    internal static class Notifications
    {
        private static readonly string icon;
        private static Windows.Data.Xml.Dom.XmlDocument GetXml(string title, string body)
        {
            XElement toast =
                new XElement("toast",
                    new XElement("visual",
                        new XElement("binding",
                            new XAttribute("template", "ToastGeneric"),
                            new XElement("text", title),
                            new XElement("text", body),
                            new XElement("image",
                                new XAttribute("src", icon),
                                new XAttribute("placement", "appLogoOverride"),
                                new XAttribute("hint-crop", "circle")))));

            Windows.Data.Xml.Dom.XmlDocument xml = new Windows.Data.Xml.Dom.XmlDocument();
            xml.LoadXml(toast.ToString());

            return xml;
        }

        static Notifications()
        {
            // Write the icon to local appdata folder for toast notifications
            icon = $@"{Global.MainFolder}\WireSock.ico";

            if (!File.Exists(icon))
                using (FileStream stream = new FileStream(icon, FileMode.CreateNew))
                    Resources.ico.Save(stream);
        }

        public static void Notify(string title, string body)
        {
            WindowsApplicationContext context = WindowsApplicationContext.FromCurrentProcess();
            ToastNotifier notifier = ToastNotificationManager.CreateToastNotifier(context.AppUserModelId);

            ToastNotification notification = new ToastNotification(GetXml(title, body));

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
                    Debug.WriteLine($"Notification dismissed: Application hidden");
                    break;
                case ToastDismissalReason.UserCanceled:
                    Debug.WriteLine($"Notification dismissed: User cancelled");
                    break;
                case ToastDismissalReason.TimedOut:
                    Debug.WriteLine($"Notification dismissed: Timed out");
                    break;
            }
        }

        private static void Notification_Activated(ToastNotification sender, object args)
        {

            foreach (Form form in Application.OpenForms)
            {
                if (form.Name == "frmMain")
                {
                    form.BeginInvoke((Action)(() =>
                    {

                        form.Show();
                        form.WindowState = FormWindowState.Normal;
                    }));
                }
            }

        }
    }
}
