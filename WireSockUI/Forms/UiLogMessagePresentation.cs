using System;
using System.Globalization;
using System.Text;
using WireSockUI.Native;

namespace WireSockUI.Forms
{
    internal static class UiLogMessagePresentation
    {
        internal static bool ShouldDisplay(string message, WireguardBoosterExports.WgbLogLevel configuredLevel)
        {
            if (configuredLevel == WireguardBoosterExports.WgbLogLevel.All ||
                configuredLevel == WireguardBoosterExports.WgbLogLevel.Debug)
                return true;

            WireguardBoosterExports.WgbLogLevel messageLevel;
            if ((!TryExtractTopLevelJsonStringProperty(message, "level", out var structuredLevel) ||
                 !TryMapLevel(structuredLevel, out messageLevel)) &&
                !TryClassify(FormatForDisplay(message), out messageLevel))
                return true;

            return Severity(messageLevel) <= Severity(configuredLevel);
        }

        internal static string FormatForDisplay(string message)
        {
            if (string.IsNullOrEmpty(message))
                return message ?? string.Empty;

            return TryExtractTopLevelJsonStringProperty(message, "message", out var extractedMessage)
                ? extractedMessage
                : message;
        }

        private static bool TryClassify(string message, out WireguardBoosterExports.WgbLogLevel level)
        {
            var normalizedMessage = message?.TrimStart();

            if (StartsWith(normalizedMessage, "[ERROR]") || StartsWith(normalizedMessage, "ERROR:"))
            {
                level = WireguardBoosterExports.WgbLogLevel.Error;
                return true;
            }

            if (StartsWith(normalizedMessage, "[WARNING]") || StartsWith(normalizedMessage, "[WARN]") ||
                StartsWith(normalizedMessage, "WARNING:") || StartsWith(normalizedMessage, "WARN:"))
            {
                level = WireguardBoosterExports.WgbLogLevel.Warning;
                return true;
            }

            if (StartsWith(normalizedMessage, "[INFO]"))
            {
                level = WireguardBoosterExports.WgbLogLevel.Info;
                return true;
            }

            if (StartsWith(normalizedMessage, "[TRACE]") || StartsWith(normalizedMessage, "[DEBUG]") ||
                IsFilterTrafficTrace(normalizedMessage))
            {
                level = WireguardBoosterExports.WgbLogLevel.Debug;
                return true;
            }

            level = WireguardBoosterExports.WgbLogLevel.Error;
            return false;
        }

        private static int Severity(WireguardBoosterExports.WgbLogLevel level)
        {
            switch (level)
            {
                case WireguardBoosterExports.WgbLogLevel.Warning:
                    return 1;
                case WireguardBoosterExports.WgbLogLevel.Info:
                    return 2;
                case WireguardBoosterExports.WgbLogLevel.Debug:
                    return 3;
                case WireguardBoosterExports.WgbLogLevel.All:
                    return 4;
                default:
                    return 0;
            }
        }

        private static bool IsFilterTrafficTrace(string message)
        {
            const string filterPrefix = "[FILTER]:";
            if (!StartsWith(message, filterPrefix))
                return false;

            var trace = message.Substring(filterPrefix.Length).TrimStart();
            var hasPacketProtocol = StartsWith(trace, "UDP :") || StartsWith(trace, "TCP :") ||
                                    StartsWith(trace, "ICMP :") || StartsWith(trace, "ICMPV6 :");
            return hasPacketProtocol && trace.IndexOf(" -> ", StringComparison.Ordinal) > 0;
        }

        private static bool StartsWith(string message, string value)
        {
            return message?.StartsWith(value, StringComparison.OrdinalIgnoreCase) == true;
        }

        private static bool TryMapLevel(string value, out WireguardBoosterExports.WgbLogLevel level)
        {
            if (string.Equals(value, "error", StringComparison.OrdinalIgnoreCase))
                level = WireguardBoosterExports.WgbLogLevel.Error;
            else if (string.Equals(value, "warning", StringComparison.OrdinalIgnoreCase) ||
                     string.Equals(value, "warn", StringComparison.OrdinalIgnoreCase))
                level = WireguardBoosterExports.WgbLogLevel.Warning;
            else if (string.Equals(value, "info", StringComparison.OrdinalIgnoreCase))
                level = WireguardBoosterExports.WgbLogLevel.Info;
            else if (string.Equals(value, "debug", StringComparison.OrdinalIgnoreCase) ||
                     string.Equals(value, "trace", StringComparison.OrdinalIgnoreCase))
                level = WireguardBoosterExports.WgbLogLevel.Debug;
            else
            {
                level = WireguardBoosterExports.WgbLogLevel.Error;
                return false;
            }

            return true;
        }

        private static bool TryExtractTopLevelJsonStringProperty(
            string value,
            string propertyName,
            out string propertyValue)
        {
            propertyValue = null;
            if (string.IsNullOrEmpty(value) || string.IsNullOrEmpty(propertyName))
                return false;

            var index = 0;
            SkipWhitespace(value, ref index);
            if (index >= value.Length || value[index++] != '{')
                return false;

            SkipWhitespace(value, ref index);
            var propertySeen = false;
            var propertyFound = false;
            string candidateValue = null;
            if (index < value.Length && value[index] == '}')
                index++;
            else
                while (true)
                {
                    if (!TryReadJsonString(value, ref index, out var currentPropertyName))
                        return false;

                    SkipWhitespace(value, ref index);
                    if (index >= value.Length || value[index++] != ':')
                        return false;

                    SkipWhitespace(value, ref index);
                    if (string.Equals(currentPropertyName, propertyName, StringComparison.OrdinalIgnoreCase))
                    {
                        if (propertySeen)
                            return false;
                        propertySeen = true;
                        if (index < value.Length && value[index] == '"')
                        {
                            if (!TryReadJsonString(value, ref index, out candidateValue))
                                return false;
                            propertyFound = true;
                        }
                        else if (!TrySkipJsonValue(value, ref index, 0))
                            return false;
                    }
                    else if (!TrySkipJsonValue(value, ref index, 0))
                        return false;

                    SkipWhitespace(value, ref index);
                    if (index >= value.Length)
                        return false;
                    if (value[index] == '}')
                    {
                        index++;
                        break;
                    }
                    if (value[index++] != ',')
                        return false;
                    SkipWhitespace(value, ref index);
                }

            SkipWhitespace(value, ref index);
            if (index != value.Length || !propertyFound)
                return false;

            propertyValue = candidateValue;
            return true;
        }

        private static bool TryReadJsonString(string value, ref int index, out string result)
        {
            result = null;
            if (index >= value.Length || value[index++] != '"')
                return false;

            var builder = new StringBuilder();
            while (index < value.Length)
            {
                var character = value[index++];
                if (character == '"')
                {
                    result = builder.ToString();
                    return true;
                }

                if (character != '\\')
                {
                    if (character < 0x20)
                        return false;
                    builder.Append(character);
                    continue;
                }

                if (index >= value.Length)
                    return false;

                var escaped = value[index++];
                switch (escaped)
                {
                    case '"':
                    case '\\':
                    case '/':
                        builder.Append(escaped);
                        break;
                    case 'b':
                        builder.Append('\b');
                        break;
                    case 'f':
                        builder.Append('\f');
                        break;
                    case 'n':
                        builder.Append('\n');
                        break;
                    case 'r':
                        builder.Append('\r');
                        break;
                    case 't':
                        builder.Append('\t');
                        break;
                    case 'u':
                        if (!TryReadUnicodeEscape(value, ref index, out var unicodeCharacter))
                            return false;
                        builder.Append(unicodeCharacter);
                        break;
                    default:
                        return false;
                }
            }

            return false;
        }

        private static bool TrySkipJsonValue(string value, ref int index, int depth)
        {
            const int maxDepth = 32;
            if (depth > maxDepth || index >= value.Length)
                return false;

            switch (value[index])
            {
                case '"':
                    return TryReadJsonString(value, ref index, out _);
                case '{':
                    return TrySkipJsonObject(value, ref index, depth + 1);
                case '[':
                    return TrySkipJsonArray(value, ref index, depth + 1);
                case 't':
                    return TryConsumeJsonLiteral(value, ref index, "true");
                case 'f':
                    return TryConsumeJsonLiteral(value, ref index, "false");
                case 'n':
                    return TryConsumeJsonLiteral(value, ref index, "null");
                default:
                    return TrySkipJsonNumber(value, ref index);
            }
        }

        private static bool TrySkipJsonObject(string value, ref int index, int depth)
        {
            index++;
            SkipWhitespace(value, ref index);
            if (index < value.Length && value[index] == '}')
            {
                index++;
                return true;
            }

            while (index < value.Length)
            {
                if (!TryReadJsonString(value, ref index, out _))
                    return false;
                SkipWhitespace(value, ref index);
                if (index >= value.Length || value[index++] != ':')
                    return false;
                SkipWhitespace(value, ref index);
                if (!TrySkipJsonValue(value, ref index, depth))
                    return false;
                SkipWhitespace(value, ref index);
                if (index >= value.Length)
                    return false;
                if (value[index] == '}')
                {
                    index++;
                    return true;
                }
                if (value[index++] != ',')
                    return false;
                SkipWhitespace(value, ref index);
            }

            return false;
        }

        private static bool TrySkipJsonArray(string value, ref int index, int depth)
        {
            index++;
            SkipWhitespace(value, ref index);
            if (index < value.Length && value[index] == ']')
            {
                index++;
                return true;
            }

            while (index < value.Length)
            {
                if (!TrySkipJsonValue(value, ref index, depth))
                    return false;
                SkipWhitespace(value, ref index);
                if (index >= value.Length)
                    return false;
                if (value[index] == ']')
                {
                    index++;
                    return true;
                }
                if (value[index++] != ',')
                    return false;
                SkipWhitespace(value, ref index);
            }

            return false;
        }

        private static bool TryConsumeJsonLiteral(string value, ref int index, string literal)
        {
            if (index + literal.Length > value.Length ||
                string.Compare(value, index, literal, 0, literal.Length, StringComparison.Ordinal) != 0)
                return false;

            index += literal.Length;
            return true;
        }

        private static bool TrySkipJsonNumber(string value, ref int index)
        {
            var start = index;
            if (index < value.Length && value[index] == '-')
                index++;

            if (index >= value.Length)
                return false;
            if (value[index] == '0')
            {
                index++;
                if (index < value.Length && IsJsonDigit(value[index]))
                    return false;
            }
            else
            {
                if (value[index] < '1' || value[index] > '9')
                    return false;
                while (index < value.Length && IsJsonDigit(value[index]))
                    index++;
            }

            if (index < value.Length && value[index] == '.')
            {
                index++;
                var fractionStart = index;
                while (index < value.Length && IsJsonDigit(value[index]))
                    index++;
                if (index == fractionStart)
                    return false;
            }

            if (index < value.Length && (value[index] == 'e' || value[index] == 'E'))
            {
                index++;
                if (index < value.Length && (value[index] == '+' || value[index] == '-'))
                    index++;
                var exponentStart = index;
                while (index < value.Length && IsJsonDigit(value[index]))
                    index++;
                if (index == exponentStart)
                    return false;
            }

            return index > start;
        }

        private static bool IsJsonDigit(char character)
        {
            return character >= '0' && character <= '9';
        }

        private static bool TryReadUnicodeEscape(string value, ref int index, out char character)
        {
            character = default;
            if (index + 4 > value.Length ||
                !ushort.TryParse(value.Substring(index, 4), NumberStyles.HexNumber,
                    CultureInfo.InvariantCulture, out var codePoint))
                return false;

            index += 4;
            character = (char)codePoint;
            return true;
        }

        private static void SkipWhitespace(string value, ref int index)
        {
            while (index < value.Length &&
                   (value[index] == ' ' || value[index] == '\t' ||
                    value[index] == '\r' || value[index] == '\n'))
                index++;
        }
    }
}
