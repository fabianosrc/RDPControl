<#
.SYNOPSIS
Registers native Win32 API definitions required by the RDPControl Engine.

.DESCRIPTION
Defines the RDPControl.NativeMethods class via Add-Type using P/Invoke signatures.
Contains only P/Invoke declarations, Win32 constants, and interop structures.

No business logic is present in this class. Privilege orchestration is handled
by RDPControl.PrivilegeManager and RDPControl.PrivilegeScope (PrivilegeManager.ps1).

This file is loaded once by the module loader and must not be dot-sourced directly.

Interop notes:
    - Struct layout uses LayoutKind.Sequential without Pack to preserve Win32
      natural alignment and avoid memory corruption.
    - All flags and masks use uint (DWORD) to match Win32 type definitions exactly.
    - TOKEN_PRIVILEGES uses LUID_AND_ATTRIBUTES (not flattened) per Win32 spec.
    - TOKEN_INFORMATION_CLASS is declared as a partial enum. Only the value
      required by this module (TokenPrivileges = 3) is defined intentionally.
    - SafeHandle is not used in v0.1.0. Tracked for future improvement.
#>
if (-not ([System.Management.Automation.PSTypeName]'RDPControl.NativeMethods').Type) {
    Add-Type -TypeDefinition @"
    using System;
    using System.Runtime.InteropServices;

    namespace RDPControl
    {
        internal static class NativeMethods
        {

            // Token access rights (Win32 DWORD -> uint)
            public const uint TOKEN_QUERY             = 0x0008u;
            public const uint TOKEN_ADJUST_PRIVILEGES = 0x0020u;

            // Privilege attributes (Win32 DWORD -> uint)
            public const uint SE_PRIVILEGE_ENABLED    = 0x00000002u;

            // Win32 error codes
            public const int ERROR_NOT_ALL_ASSIGNED   = 1300;

            // Partial enum - only TokenPrivileges (3) is required by this module.
            // Additional values are intentionally omitted to reduce surface area.
            public enum TOKEN_INFORMATION_CLASS
            {
                TokenPrivileges = 3
            }

            // LUID - Locally Unique Identifier
            [StructLayout(LayoutKind.Sequential)]
            public struct LUID
            {
                public uint LowPart;
                public int  HighPart;
            }

            // LUID_AND_ATTRIBUTES - privilege entry with state flags
            [StructLayout(LayoutKind.Sequential)]
            public struct LUID_AND_ATTRIBUTES
            {
                public LUID Luid;
                public uint Attributes;  // Win32 DWORD -> uint
            }

            // TOKEN_PRIVILEGES - correct Win32 layout using LUID_AND_ATTRIBUTES
            // Per Win32 spec: DWORD PrivilegeCount + LUID_AND_ATTRIBUTES Privileges[ANYSIZE_ARRAY]
            // For single privilege operations, Privileges holds exactly one entry.
            [StructLayout(LayoutKind.Sequential)]
            public struct TOKEN_PRIVILEGES
            {
                public uint                PrivilegeCount;
                public LUID_AND_ATTRIBUTES Privileges;
            }

            [DllImport("advapi32.dll", ExactSpelling = true, SetLastError = true)]
            internal static extern bool OpenProcessToken(
                IntPtr     ProcessHandle,
                uint       DesiredAccess,
                ref IntPtr TokenHandle
            );

            [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
            internal static extern bool LookupPrivilegeValue(
                string   SystemName,
                string   Name,
                ref LUID Luid
            );

            [DllImport("advapi32.dll", ExactSpelling = true, SetLastError = true)]
            internal static extern bool AdjustTokenPrivileges(
                IntPtr               TokenHandle,
                bool                 DisableAllPrivileges,
                ref TOKEN_PRIVILEGES NewState,
                int                  BufferLength,
                IntPtr               PreviousState,
                IntPtr               ReturnLength
            );

            [DllImport("advapi32.dll", SetLastError = true)]
            internal static extern bool GetTokenInformation(
                IntPtr                  TokenHandle,
                TOKEN_INFORMATION_CLASS TokenInformationClass,
                IntPtr                  TokenInformation,
                int                     TokenInformationLength,
                out int                 ReturnLength
            );

            // Internal only - prevents misuse from other module components
            [DllImport("kernel32.dll", ExactSpelling = true, SetLastError = true)]
            internal static extern bool CloseHandle(IntPtr Handle);
        }
    }
"@
}
