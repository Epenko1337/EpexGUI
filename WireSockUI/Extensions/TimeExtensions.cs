﻿using System;
using WireSockUI.Properties;

namespace WireSockUI.Extensions
{
    internal static class TimeExtensions
    {
        public static string AsTimeAgo(this long seconds)
        {
            return new TimeSpan(0, 0, (int)seconds).AsTimeAgo();
        }

        public static string AsTimeAgo(this TimeSpan value)
        {
            const int second = 1;
            const int minute = 60 * second;
            const int hour = 60 * minute;
            const int day = 24 * hour;
            const int month = 30 * day;

            var delta = Math.Abs(value.TotalSeconds);

            if (delta < 1 * minute)
                return value.Seconds == 1 ? Resources.TimeLapseSecond : value.Seconds + Resources.TimeLapseSeconds;

            if (delta < 2 * minute)
                return Resources.TimeLapseMinute;

            if (delta < 45 * minute)
                return value.Minutes + Resources.TimeLapseMinutes;

            if (delta < 90 * minute)
                return Resources.TimeLapseHour;

            if (delta < 24 * hour)
                return value.Hours + Resources.TimeLapseHour;

            if (delta < 48 * hour)
                return "yesterday";

            if (delta < 30 * day)
                return value.Days + Resources.TimeLapseDays;

            if (delta < 12 * month)
            {
                var months = Convert.ToInt32(Math.Floor((double)value.Days / 30));
                return months <= 1 ? Resources.TimeLapseMonth : months + Resources.TimeLapseMonths;
            }

            var years = Convert.ToInt32(Math.Floor((double)value.Days / 365));
            return years <= 1 ? Resources.TimeLapseYear : years + Resources.TimeLapseYears;
        }
    }
}