<#
.SYNOPSIS
Registers native Win32 API definitions required by the RDPControl Engine.

.DESCRIPTION
Defines the RDPControl.NativeMethods class via Add-Type using P/Invoke signatures.
Contains only P/Invoke declarations, Win32 constants, and interop structures.

No business logic is present in this class. Privilege orchestration is handled
by RDPControl.PrivilegeManager (PrivilegeManager.ps1).

This file is loaded once by the module loader and must not be dot-sourced directly.

.NOTES
Struct layout uses LayoutKind.Sequential without Pack to preserve Win32 natural
alignment and avoid memory corruption from forced byte-level packing.
#>
if (-not ([System.Management.Automation.PSTypeName]'RDPControl.NativeMethods').Type) {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

namespace RDPControl {

    internal static class NativeMethods {

        // Token access rights
        public const int TOKEN_QUERY             = 0x0008;
        public const int TOKEN_ADJUST_PRIVILEGES = 0x0020;

        // Privilege attributes
        public const int SE_PRIVILEGE_ENABLED    = 0x00000002;

        // Win32 error codes
        public const int ERROR_NOT_ALL_ASSIGNED  = 1300;

        // LUID - Locally Unique Identifier
        // Sequential layout without Pack to preserve Win32 natural alignment
        [StructLayout(LayoutKind.Sequential)]
        public struct LUID {
            public uint LowPart;
            public int  HighPart;
        }

        // TOKEN_PRIVILEGES - used in AdjustTokenPrivileges
        [StructLayout(LayoutKind.Sequential)]
        public struct TOKEN_PRIVILEGES {
            public uint PrivilegeCount;
            public LUID Luid;
            public int  Attributes;
        }

        [DllImport("advapi32.dll", ExactSpelling = true, SetLastError = true)]
        public static extern bool OpenProcessToken(
            IntPtr     ProcessHandle,
            int        DesiredAccess,
            ref IntPtr TokenHandle
        );

        [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        public static extern bool LookupPrivilegeValue(
            string   SystemName,
            string   Name,
            ref LUID Luid
        );

        [DllImport("advapi32.dll", ExactSpelling = true, SetLastError = true)]
        public static extern bool AdjustTokenPrivileges(
            IntPtr              TokenHandle,
            bool                DisableAllPrivileges,
            ref TOKEN_PRIVILEGES NewState,
            int                 BufferLength,
            IntPtr              PreviousState,
            IntPtr              ReturnLength
        );

        [DllImport("kernel32.dll", ExactSpelling = true, SetLastError = true)]
        public static extern bool CloseHandle(IntPtr Handle);
    }
}
"@
}
