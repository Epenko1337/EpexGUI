using System;
using System.Runtime.InteropServices;

namespace WireSockUI.Native
{
    /// <summary>
    /// Native class to validate IPv4, IPv6 and DNS domain addresses & CIDR notations
    /// </summary>
    internal class IPHelper
    {
        [Flags]
        private enum NET_STRING
        {
            /// <summary>
            /// The NetworkString parameter points to an IPv4 address using Internet standard dotted-decimal notation. A network port or
            /// prefix must not be present in the network string.
            /// <para>An example network string is the following:</para>
            /// <para>192.168.100.10</para>
            /// </summary>
            NET_STRING_IPV4_ADDRESS = 0x00000001,

            /// <summary>
            /// The NetworkString parameter points to an IPv4 service using Internet standard dotted-decimal notation. A network port is
            /// required as part of the network string. A prefix must not be present in the network string.
            /// <para>An example network string is the following:</para>
            /// <para>192.168.100.10:80</para>
            /// </summary>
            NET_STRING_IPV4_SERVICE = 0x00000002,

            /// <summary>
            /// The NetworkString parameter points to an IPv4 network using Internet standard dotted-decimal notation. A network prefix that
            /// uses the Classless Inter-Domain Routing (CIDR) notation is required as part of the network string. A network port must not be
            /// present in the network string.
            /// <para>An example network string is the following:</para>
            /// <para>192.168.100/24</para>
            /// </summary>
            NET_STRING_IPV4_NETWORK = 0x00000004,

            /// <summary>
            /// The NetworkString parameter points to an IPv6 address using Internet standard hexadecimal encoding. An IPv6 scope ID may be
            /// present in the network string. A network port or prefix must not be present in the network string.
            /// <para>An example network string is the following:</para>
            /// <para>21DA:00D3:0000:2F3B:02AA:00FF:FE28:9C5A%2</para>
            /// </summary>
            NET_STRING_IPV6_ADDRESS = 0x00000008,

            /// <summary>
            /// The NetworkString parameter points to an IPv6 address using Internet standard hexadecimal encoding. An IPv6 scope ID must not
            /// be present in the network string. A network port or prefix must not be present in the network string.
            /// <para>An example network string is the following:</para>
            /// <para>21DA:00D3:0000:2F3B:02AA:00FF:FE28:9C5A</para>
            /// </summary>
            NET_STRING_IPV6_ADDRESS_NO_SCOPE = 0x00000010,

            /// <summary>
            /// The NetworkString parameter points to an IPv6 service using Internet standard hexadecimal encoding. A network port is
            /// required as part of the network string. An IPv6 scope ID may be present in the network string. A prefix must not be present
            /// in the network string.
            /// <para>An example network string with a scope ID is the following:</para>
            /// <para>[21DA:00D3:0000:2F3B:02AA:00FF:FE28:9C5A%2]:8080</para>
            /// </summary>
            NET_STRING_IPV6_SERVICE = 0x00000020,

            /// <summary>
            /// The NetworkString parameter points to an IPv6 service using Internet standard hexadecimal encoding. A network port is
            /// required as part of the network string. An IPv6 scope ID must not be present in the network string. A prefix must not be
            /// present in the network string.
            /// <para>An example network string is the following:</para>
            /// <para>21DA:00D3:0000:2F3B:02AA:00FF:FE28:9C5A:8080</para>
            /// </summary>
            NET_STRING_IPV6_SERVICE_NO_SCOPE = 0x00000040,

            /// <summary>
            /// The NetworkString parameter points to an IPv6 network using Internet standard hexadecimal encoding. A network prefix in CIDR
            /// notation is required as part of the network string. A network port or scope ID must not be present in the network string.
            /// <para>An example network string is the following:</para>
            /// <para>21DA:D3::/48</para>
            /// </summary>
            NET_STRING_IPV6_NETWORK = 0x00000080,

            /// <summary>
            /// The NetworkString parameter points to an Internet address using a Domain Name System (DNS) name. A network port or prefix
            /// must not be present in the network string.
            /// <para>An example network string is the following:</para>
            /// <para>www.microsoft.com</para>
            /// </summary>
            NET_STRING_NAMED_ADDRESS = 0x00000100,

            /// <summary>
            /// The NetworkString parameter points to an Internet service using a DNS name. A network port must be present in the network string.
            /// <para>An example network string is the following:</para>
            /// <para>www.microsoft.com:80</para>
            /// </summary>
            NET_STRING_NAMED_SERVICE = 0x00000200,

            /// <summary>
            /// The NetworkString parameter points to an IPv4 address using Internet standard dotted-decimal notation or an IPv6 address
            /// using the Internet standard hexadecimal encoding. An IPv6 scope ID may be present in the network string. A network port or
            /// prefix must not be present in the network string.
            /// <para>This type matches either the NET_STRING_IPV4_ADDRESS or NET_STRING_IPV6_ADDRESS types.</para>
            /// </summary>
            NET_STRING_IP_ADDRESS = 0x00000009,

            /// <summary>
            /// The NetworkString parameter points to an IPv4 address using Internet standard dotted-decimal notation or an IPv6 address
            /// using Internet standard hexadecimal encoding. An IPv6 scope ID must not be present in the network string. A network port or
            /// prefix must not be present in the network string.
            /// <para>This type matches either the NET_STRING_IPV4_ADDRESS or NET_STRING_IPV6_ADDRESS_NO_SCOPE types.</para>
            /// </summary>
            NET_STRING_IP_ADDRESS_NO_SCOPE = 0x00000011,

            /// <summary>
            /// The NetworkString parameter points to an IPv4 service or IPv6 service. A network port is required as part of the network
            /// string. An IPv6 scope ID may be present in the network string. A prefix must not be present in the network string.
            /// <para>This type matches either the NET_STRING_IPV4_SERVICE or NET_STRING_IPV6_SERVICE types.</para>
            /// </summary>
            NET_STRING_IP_SERVICE = 0x00000022,

            /// <summary>
            /// The NetworkString parameter points to an IPv4 service or IPv6 service. A network port is required as part of the network
            /// string. An IPv6 scope ID must not be present in the network string. A prefix must not be present in the network string.
            /// <para>This type matches either the NET_STRING_IPV4_SERVICE or NET_STRING_IPV6_SERVICE_NO_SCOPE types.</para>
            /// </summary>
            NET_STRING_IP_SERVICE_NO_SCOPE = 0x00000042,

            /// <summary>
            /// The NetworkString parameter points to an IPv4 or IPv6 network. A network prefix in CIDR notation is required as part of the
            /// network string. A network port or scope ID must not be present in the network.
            /// <para>This type matches either the NET_STRING_IPV4_NETWORK or NET_STRING_IPV6_NETWORK types.</para>
            /// </summary>
            NET_STRING_IP_NETWORK = 0x00000084,

            /// <summary>
            /// The NetworkString parameter points to an IPv4 address in Internet standard dotted-decimal notation, an IPv6 address in
            /// Internet standard hexadecimal encoding, or a DNS name. An IPv6 scope ID may be present in the network string for an IPv6
            /// address. A network port or prefix must not be present in the network string.
            /// <para>This type matches either the NET_STRING_NAMED_ADDRESS or NET_STRING_IP_ADDRESS types.</para>
            /// </summary>
            NET_STRING_ANY_ADDRESS = 0x00000209,

            /// <summary>
            /// The NetworkString parameter points to an IPv4 address in Internet standard dotted-decimal notation, an IPv6 address in
            /// Internet standard hexadecimal encoding, or a DNS name. An IPv6 scope ID must not be present in the network string for an IPv6
            /// address. A network port or prefix must not be present in the network string.
            /// <para>This type matches either the NET_STRING_NAMED_ADDRESS or NET_STRING_IP_ADDRESS_NO_SCOPE types.</para>
            /// </summary>
            NET_STRING_ANY_ADDRESS_NO_SCOPE = 0x00000211,

            /// <summary>
            /// The NetworkString parameter points to an IPv4 service or IPv6 service using IP address notation or a DNS name. A network port
            /// is required as part of the network string. An IPv6 scope ID may be present in the network string. A prefix must not be
            /// present in the network string.
            /// <para>This type matches either the NET_STRING_NAMED_SERVICE or NET_STRING_IP_SERVICE types.</para>
            /// </summary>
            NET_STRING_ANY_SERVICE = 0x00000222,

            /// <summary>
            /// The NetworkString parameter points to an IPv4 service or IPv6 service using IP address notation or a DNS name. A network port
            /// is required as part of the network string. An IPv6 scope ID must not be present in the network string. A prefix must not be
            /// present in the network string.
            /// <para>This type matches either the NET_STRING_NAMED_SERVICE or NET_STRING_IP_SERVICE_NO_SCOPE types.</para>
            /// </summary>
            NET_STRING_ANY_SERVICE_NO_SCOPE = 0x00000242,
        }

        [DllImport("iphlpapi.dll", SetLastError = false, ExactSpelling = true)]
        private static extern uint ParseNetworkString([MarshalAs(UnmanagedType.LPWStr)] string networkString, NET_STRING types, [Optional] IntPtr addressInfo, [Optional] IntPtr portNumber, [Optional] IntPtr prefixLength);

        /// <summary>
        /// Determine if <paramref name="ipNetwork"/> is a valid IPv4 or IPv6 CIDR network notation
        /// </summary>
        /// <param name="ipNetwork">IPv4/IPv6 CIDR notation</param>
        /// <returns><c>true</c> if valid, otherwise <c>false</c></returns>
        public static bool IsValidIPNetwork(string ipNetwork)
        {
            return ParseNetworkString(ipNetwork.Trim(), NET_STRING.NET_STRING_IP_NETWORK) == 0;
        }

        /// <summary>
        /// Determine if <paramref name="ipAddress"/> is a valid IPv4 or IPv6 address
        /// </summary>
        /// <param name="ipAddress">IPv4/IPv6 address</param>
        /// <returns><c>true</c> if valid, otherwise <c>false</c></returns>
        public static bool IsValidIPAddress(string ipAddress)
        {
            return ParseNetworkString(ipAddress.Trim(), NET_STRING.NET_STRING_IP_ADDRESS) == 0;
        }

        /// <summary>
        /// Determine if <paramref name="address"/> is a valid IPv4, IPv6 address or DNS domain
        /// </summary>
        /// <param name="address">IPv4/IPv6 address or DNS domain, optionally with port specification</param>
        /// <returns><c>true</c> if valid, otherwise <c>false</c></returns>
        public static bool IsValidAddress(string address)
        {
            return ParseNetworkString(address.Trim(), NET_STRING.NET_STRING_ANY_SERVICE_NO_SCOPE) == 0;
        }
    }
}
