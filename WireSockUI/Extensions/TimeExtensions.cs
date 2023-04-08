using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using WireSockUI.Properties;

namespace WireSockUI.Extensions
{
    internal static class TimeExtensions
    {
        public static string AsTimeAgo(this long ticks)
        {
            return new TimeSpan(ticks).AsTimeAgo();
        }

        public static string AsTimeAgo(this TimeSpan value)
        {
            const int SECOND = 1;
            const int MINUTE = 60 * SECOND;
            const int HOUR = 60 * MINUTE;
            const int DAY = 24 * HOUR;
            const int MONTH = 30 * DAY;

            double delta = Math.Abs(value.TotalSeconds);

            if (delta < 1 * MINUTE)
                return value.Seconds == 1 ? Resources.TimeLapseSecond : value.Seconds + Resources.TimeLapseSeconds;

            if (delta < 2 * MINUTE)
                return Resources.TimeLapseMinute;

            if (delta < 45 * MINUTE)
                return value.Minutes + Resources.TimeLapseMinutes;

            if (delta < 90 * MINUTE)
                return Resources.TimeLapseHour;

            if (delta < 24 * HOUR)
                return value.Hours + Resources.TimeLapseHour;

            if (delta < 48 * HOUR)
                return "yesterday";

            if (delta < 30 * DAY)
                return value.Days + Resources.TimeLapseDays;

            if (delta < 12 * MONTH)
            {
                int months = Convert.ToInt32(Math.Floor((double)value.Days / 30));
                return months <= 1 ? Resources.TimeLapseMonth : months + Resources.TimeLapseMonths;
            }
            else
            {
                int years = Convert.ToInt32(Math.Floor((double)value.Days / 365));
                return years <= 1 ? Resources.TimeLapseYear : years + Resources.TimeLapseYears;
            }
        }
    }
}
