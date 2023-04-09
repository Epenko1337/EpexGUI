using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Security.Principal;

namespace WireSockUI.Native
{
    public class ProcessEntry
    {
        /// <summary>
        /// Unique process identifier
        /// </summary>
        public int ProcessId { get; private set; }

        /// <summary>
        /// Process display name
        /// </summary>
        public string Name { get; private set; }

        /// <summary>
        /// Process image executable path
        /// </summary>
        public string ImageName { get; private set; }

        /// <summary>
        /// Process username
        /// </summary>
        public string User { get; private set; }

        public static IEqualityComparer<ProcessEntry> Comparer { get; } = new ProcessEntryEqualityComparer();

        public ProcessEntry(int processId, string name, string imageName, string user)
        {
            ProcessId = processId;
            Name = name;
            ImageName = imageName;
            User = user;
        }

        private sealed class ProcessEntryEqualityComparer : IEqualityComparer<ProcessEntry>
        {
            public bool Equals(ProcessEntry x, ProcessEntry y)
            {
                return String.Equals(x.Name, y.Name, StringComparison.OrdinalIgnoreCase);
            }

            public int GetHashCode(ProcessEntry p)
            {
                return (p.Name != null ? p.Name.GetHashCode() : 0);
            }
        }
    }

    internal class ProcessList
    {
        [DllImport("advapi32", SetLastError = true)]
        private static extern bool OpenProcessToken(IntPtr ProcessHandle, int DesiredAccess, out IntPtr TokenHandle);

        [DllImport("kernel32", SetLastError = true)]
        private static extern IntPtr OpenProcess(int dwDesiredAccess, bool bInheritHandle, int dwProcessId);

        [DllImport("kernel32", SetLastError = true)]
        private static extern bool CloseHandle(IntPtr hObject);

        [DllImport("kernel32", SetLastError = true)]
        private static extern IntPtr CreateToolhelp32Snapshot(int dwFlags, int th32ProcessID);

        [DllImport("kernel32", SetLastError = true, CharSet = CharSet.Unicode)]
        private static extern bool Process32First(IntPtr hSnapshot, ref PROCESSENTRY32 lppe);

        [DllImport("kernel32", SetLastError = true, CharSet = CharSet.Unicode)]
        private static extern bool Process32Next(IntPtr hSnapshot, ref PROCESSENTRY32 lppe);

        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Auto)]
        private static extern bool QueryFullProcessImageName(IntPtr hProcess, uint dwFlags, [Out] char[] lpExeName, [In, Out] ref int lpdwSize);

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
        private struct PROCESSENTRY32
        {
            public int dwSize;
            public int cntUsage;
            public int th32ProcessID;
            public IntPtr th32DefaultHeapID;
            public int th32ModuleID;
            public int cntThreads;
            public int th32ParentProcessID;
            public int pcPriClassBase;
            public int dwFlags;

            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)]
            public string szExeFile;
        }

        private static string GetProcessUser(IntPtr handle)
        {
            const int TOKEN_QUERY = 0x0008;

            if (handle == IntPtr.Zero)
                return null;


            if (!OpenProcessToken(handle, TOKEN_QUERY, out var tokenHandle))
                return null;

            using (WindowsIdentity wi = new WindowsIdentity(tokenHandle))
            {
                CloseHandle(tokenHandle);
                return wi.Name;
            }
        }

        private static string GetProcessImage(IntPtr handle)
        {
            char[] buffer = new char[1024];
            int size = 1024;

            if (QueryFullProcessImageName(handle, 0, buffer, ref size))
                return new string(buffer, 0, size);

            return null;
        }

        /// <summary>
        /// Retrieve a list of <see cref="ProcessEntry" /> for all processes running in the system.
        /// </summary>
        /// <returns>Lis of <see cref="ProcessEntry" /></returns>
        public static IEnumerable<ProcessEntry> GetProcessList()
        {
            const int TH32CS_SNAPPROCESS = 2;
            const int PROCESS_QUERY_LIMITED_INFORMATION = 0x00001000;

            IntPtr snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);

            PROCESSENTRY32 entry = new PROCESSENTRY32() { dwSize = Marshal.SizeOf<PROCESSENTRY32>() };

            if (Process32First(snap, ref entry))
            {
                do
                {
                    IntPtr handle = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, entry.th32ProcessID);

                    yield return new ProcessEntry(
                        entry.th32ProcessID,
                        entry.szExeFile,
                        GetProcessImage(handle),
                        GetProcessUser(handle));

                    if (handle != IntPtr.Zero)
                        CloseHandle(handle);
                }
                while (Process32Next(snap, ref entry));
            }

            CloseHandle(snap);
        }
    }
}
