using System;
using System.Text;

namespace WireSockUI.Forms
{
    internal static class ProfileDisplayFormatter
    {
        internal const int MaximumApplicationValues = 50;
        internal const int MaximumDisplayCharacters = 4096;
        internal const int MaximumIpValues = 20;
        private const string TruncationSuffix = "...";

        internal static string FormatApplications(string input)
        {
            return FormatCommaSeparated(
                input, MaximumApplicationValues, 2, MaximumDisplayCharacters);
        }

        internal static string FormatIpAddresses(string input)
        {
            return FormatCommaSeparated(
                input, MaximumIpValues, 2, MaximumDisplayCharacters);
        }

        internal static string FormatText(string input)
        {
            return FormatText(input, MaximumDisplayCharacters);
        }

        internal static string FormatText(string input, int maximumCharacters)
        {
            if (input == null)
                return null;
            if (maximumCharacters < TruncationSuffix.Length + 1)
                throw new ArgumentOutOfRangeException(nameof(maximumCharacters));
            if (input.Length <= maximumCharacters)
                return input;

            var retainedLength = maximumCharacters - TruncationSuffix.Length;
            retainedLength = AvoidSplittingSurrogatePair(input, 0, retainedLength, input.Length);
            return input.Substring(0, retainedLength) + TruncationSuffix;
        }

        internal static string FormatCommaSeparated(
            string input,
            int maximumValues,
            int valuesPerLine,
            int maximumCharacters)
        {
            if (input == null)
                return null;
            if (maximumValues <= 0)
                throw new ArgumentOutOfRangeException(nameof(maximumValues));
            if (valuesPerLine <= 0)
                throw new ArgumentOutOfRangeException(nameof(valuesPerLine));
            if (maximumCharacters < TruncationSuffix.Length + 1)
                throw new ArgumentOutOfRangeException(nameof(maximumCharacters));
            if (input.Length == 0)
                return string.Empty;

            var builder = new StringBuilder(Math.Min(input.Length, maximumCharacters));
            var cursor = 0;
            var valueCount = 0;
            var truncated = false;

            while (cursor < input.Length)
            {
                if (valueCount == maximumValues)
                {
                    truncated = cursor < input.Length;
                    break;
                }

                var comma = input.IndexOf(',', cursor);
                var end = comma < 0 ? input.Length : comma;
                var separator = valueCount == 0
                    ? string.Empty
                    : valueCount % valuesPerLine == 0 ? Environment.NewLine : ",";
                var valueLength = end - cursor;
                // Reserve room for an explicit truncation marker while streaming untrusted
                // list values, so the formatter never has to append then rescan a huge token.
                if (builder.Length + separator.Length + valueLength >
                    maximumCharacters - TruncationSuffix.Length)
                {
                    AppendBoundedSegment(
                        builder,
                        separator,
                        input,
                        cursor,
                        valueLength,
                        maximumCharacters - TruncationSuffix.Length);
                    truncated = true;
                    break;
                }

                builder.Append(separator);
                builder.Append(input, cursor, valueLength);
                valueCount++;

                if (comma < 0)
                    break;
                cursor = comma + 1;
            }

            if (truncated)
            {
                TrimForSuffix(builder, maximumCharacters - TruncationSuffix.Length);
                builder.Append(TruncationSuffix);
            }
            return builder.ToString();
        }

        private static void AppendBoundedSegment(
            StringBuilder builder,
            string separator,
            string input,
            int valueStart,
            int valueLength,
            int maximumRetainedCharacters)
        {
            var separatorCharactersAvailable =
                Math.Max(0, maximumRetainedCharacters - builder.Length);
            if (separator.Length > separatorCharactersAvailable)
                return;
            if (separator.Length > 0)
                builder.Append(separator);

            var available = maximumRetainedCharacters - builder.Length;
            if (available <= 0 || valueLength <= 0)
                return;

            var appendLength = Math.Min(valueLength, available);
            appendLength = AvoidSplittingSurrogatePair(
                input,
                valueStart,
                appendLength,
                valueStart + valueLength);
            if (appendLength > 0)
                builder.Append(input, valueStart, appendLength);
        }

        private static void TrimForSuffix(StringBuilder builder, int maximumRetainedCharacters)
        {
            if (builder.Length <= maximumRetainedCharacters)
                return;

            var retainedLength = maximumRetainedCharacters;
            if (retainedLength > 0 &&
                retainedLength < builder.Length &&
                char.IsHighSurrogate(builder[retainedLength - 1]) &&
                char.IsLowSurrogate(builder[retainedLength]))
                retainedLength--;
            builder.Length = retainedLength;
        }

        private static int AvoidSplittingSurrogatePair(
            string value,
            int start,
            int length,
            int end)
        {
            if (length > 0 &&
                start + length < end &&
                char.IsHighSurrogate(value[start + length - 1]) &&
                char.IsLowSurrogate(value[start + length]))
                return length - 1;
            return length;
        }
    }
}
