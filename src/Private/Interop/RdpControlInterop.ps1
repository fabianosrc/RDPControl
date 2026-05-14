<#
.SYNOPSIS
Registers native Win32 interop definitions required by the RDPControl Engine.

.DESCRIPTION
Defines the following classes via a single Add-Type call to ensure all
types are available within the same compiled context:

    RDPControl.NativeMethods
        P/Invoke declarations, Win32 constants, and interop structures.
        No business logic. Internal visibility only.

    RDPControl.PrivilegeManager
        Internal static class for enabling and restoring Win32 token
        privileges.Depends on NativeMethods.

    RDPControl.PrivilegeScope
        IDisposable scope object(RAII pattern) that enables a privilege
        on construction and deterministically restores the previous state
        on Dispose, preventing privilege leakage into the host process.

        Usage:
            $scope = [RDPControl.PrivilegeScope]::new('SeTakeOwnershipPrivilege')
            try
    { # critical section }
            finally { $scope.Dispose() }

Interop notes:
    -Struct layout uses LayoutKind.Sequential without Pack to preserve
      Win32 natural alignment and avoid memory corruption.
    - All flags and masks use uint (DWORD) to match Win32 type definitions.
    - TOKEN_PRIVILEGES uses LUID_AND_ATTRIBUTES per Win32 spec.
    - TOKEN_INFORMATION_CLASS is a partial enum (only TokenPrivileges = 3).
    - SafeHandle is not used in v0.1.0. Tracked for future improvement.

This file is loaded once by the module loader and must not be dot-sourced directly.
#>

if (-not ([System.Management.Automation.PSTypeName] 'RDPControl.PrivilegeScope').Type) {
    Add-Type -Language CSharp -TypeDefinition @"
using System;
using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace RDPControl
{
    internal static class NativeMethods
    {
        //
        // Token access rights
        //
        internal const uint TOKEN_QUERY             = 0x0008u;
        internal const uint TOKEN_ADJUST_PRIVILEGES = 0x0020u;

        //
        // Privilege attributes
        //
        internal const uint SE_PRIVILEGE_ENABLED = 0x00000002u;

        //
        // Win32 error codes
        //
        internal const int ERROR_NOT_ALL_ASSIGNED   = 1300;
        internal const int ERROR_INSUFFICIENT_BUFFER = 122;

        internal enum TOKEN_INFORMATION_CLASS
        {
            TokenPrivileges = 3
        }

        [StructLayout(LayoutKind.Sequential)]
        internal struct LUID
        {
            public uint LowPart;
            public int HighPart;
        }

        [StructLayout(LayoutKind.Sequential)]
        internal struct LUID_AND_ATTRIBUTES
        {
            public LUID Luid;
            public uint Attributes;
        }

        //
        // TOKEN_PRIVILEGES with single-entry optimization.
        //
        [StructLayout(LayoutKind.Sequential)]
        internal struct TOKEN_PRIVILEGES
        {
            public uint PrivilegeCount;
            public LUID_AND_ATTRIBUTES Privileges;
        }

        [DllImport("advapi32.dll", ExactSpelling = true, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
internal static extern bool OpenProcessToken(
            IntPtr ProcessHandle,
            uint DesiredAccess,
            out SafeAccessTokenHandle TokenHandle
        );

[DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
[return: MarshalAs(UnmanagedType.Bool)]
internal static extern bool LookupPrivilegeValue(
    string lpSystemName,
    string lpName,
    out LUID lpLuid
);

[DllImport("advapi32.dll", ExactSpelling = true, SetLastError = true)]
[return: MarshalAs(UnmanagedType.Bool)]
internal static extern bool AdjustTokenPrivileges(
    SafeAccessTokenHandle TokenHandle,
    bool DisableAllPrivileges,
    ref TOKEN_PRIVILEGES NewState,
    int BufferLength,
    IntPtr PreviousState,
    IntPtr ReturnLength
);

[DllImport("advapi32.dll", SetLastError = true)]
[return: MarshalAs(UnmanagedType.Bool)]
internal static extern bool GetTokenInformation(
    SafeAccessTokenHandle TokenHandle,
    TOKEN_INFORMATION_CLASS TokenInformationClass,
    IntPtr TokenInformation,
    int TokenInformationLength,
    out int ReturnLength
);
    }

    internal static class TokenPrivilegeManager
{
    internal static bool GetPrivilegeState(string privilegeName)
    {
        using (SafeAccessTokenHandle tokenHandle =
            OpenCurrentProcessToken(NativeMethods.TOKEN_QUERY))
        {
            NativeMethods.LUID luid =
                LookupPrivilegeLuid(privilegeName);

            int requiredSize = 0;

            NativeMethods.GetTokenInformation(
                tokenHandle,
                NativeMethods.TOKEN_INFORMATION_CLASS.TokenPrivileges,
                IntPtr.Zero,
                0,
                out requiredSize
            );

            int lastError = Marshal.GetLastWin32Error();

            if (requiredSize <= 0 ||
                lastError != NativeMethods.ERROR_INSUFFICIENT_BUFFER)
            {
                throw new Win32Exception(
                    lastError,
                    "Failed to determine token information buffer size."
                );
            }

            IntPtr buffer = Marshal.AllocHGlobal(requiredSize);

            try
            {
                bool success = NativeMethods.GetTokenInformation(
                    tokenHandle,
                    NativeMethods.TOKEN_INFORMATION_CLASS.TokenPrivileges,
                    buffer,
                    requiredSize,
                    out requiredSize
                );

                if (!success)
                {
                    throw new Win32Exception(
                        Marshal.GetLastWin32Error(),
                        "Failed to query token privilege information."
                    );
                }

                int privilegeCount = Marshal.ReadInt32(buffer);

                IntPtr current =
                    IntPtr.Add(buffer, sizeof(uint));

                int entrySize =
                    Marshal.SizeOf<NativeMethods.LUID_AND_ATTRIBUTES>();

                for (int i = 0; i < privilegeCount; i++)
                {
                    NativeMethods.LUID_AND_ATTRIBUTES entry =
                        Marshal.PtrToStructure<
                            NativeMethods.LUID_AND_ATTRIBUTES>(current);

                    bool isTargetPrivilege =
                        entry.Luid.LowPart == luid.LowPart &&
                        entry.Luid.HighPart == luid.HighPart;

                    if (isTargetPrivilege)
                    {
                        return (entry.Attributes &
                            NativeMethods.SE_PRIVILEGE_ENABLED) != 0;
                    }

                    current = IntPtr.Add(current, entrySize);
                }

                return false;
            }
            finally
            {
                Marshal.FreeHGlobal(buffer);
            }
        }
    }

    internal static void SetPrivilegeState(
        string privilegeName,
        bool enable)
    {
        using (SafeAccessTokenHandle tokenHandle =
            OpenCurrentProcessToken(
                NativeMethods.TOKEN_QUERY |
                NativeMethods.TOKEN_ADJUST_PRIVILEGES))
        {
            NativeMethods.LUID luid =
                LookupPrivilegeLuid(privilegeName);

            NativeMethods.TOKEN_PRIVILEGES privileges =
                new NativeMethods.TOKEN_PRIVILEGES
                {
                    PrivilegeCount = 1,
                    Privileges = new NativeMethods.LUID_AND_ATTRIBUTES
                    {
                        Luid = luid,
                        Attributes = enable
                            ? NativeMethods.SE_PRIVILEGE_ENABLED
                            : 0u
                    }
                };

            bool adjusted = NativeMethods.AdjustTokenPrivileges(
                tokenHandle,
                false,
                ref privileges,
                0,
                IntPtr.Zero,
                IntPtr.Zero
            );

            int lastError = Marshal.GetLastWin32Error();

            if (!adjusted)
            {
                throw new Win32Exception(
                    lastError,
                    string.Format(
                        "AdjustTokenPrivileges failed for privilege '{0}'.",
                        privilegeName
                    )
                );
            }

            //
            // API peculiarity:
            // AdjustTokenPrivileges may return TRUE even on partial failure.
            //
            if (lastError == NativeMethods.ERROR_NOT_ALL_ASSIGNED)
            {
                throw new UnauthorizedAccessException(
                    string.Format(
                        "Privilege '{0}' was not assigned to the current token.",
                        privilegeName
                    )
                );
            }

            if (lastError != 0)
            {
                throw new Win32Exception(
                    lastError,
                    string.Format(
                        "Unexpected Win32 error while adjusting privilege '{0}'.",
                        privilegeName
                    )
                );
            }
        }
    }

    private static SafeAccessTokenHandle OpenCurrentProcessToken(
        uint desiredAccess)
    {
        SafeAccessTokenHandle tokenHandle;

        bool success = NativeMethods.OpenProcessToken(
            Process.GetCurrentProcess().Handle,
            desiredAccess,
            out tokenHandle
        );

        if (!success)
        {
            throw new Win32Exception(
                Marshal.GetLastWin32Error(),
                "Failed to open current process token."
            );
        }

        return tokenHandle;
    }

    private static NativeMethods.LUID LookupPrivilegeLuid(
        string privilegeName)
    {
        if (string.IsNullOrWhiteSpace(privilegeName))
        {
            throw new ArgumentNullException("privilegeName");
        }

        NativeMethods.LUID luid;

        bool success = NativeMethods.LookupPrivilegeValue(
            null,
            privilegeName,
            out luid
        );

        if (!success)
        {
            throw new Win32Exception(
                Marshal.GetLastWin32Error(),
                string.Format(
                    "Failed to resolve privilege '{0}'.",
                    privilegeName
                )
            );
        }

        return luid;
    }
}

//
// RAII privilege scope.
//
// Guarantees deterministic rollback of privilege state.
//
// Dispose intentionally never throws.
//
public sealed class PrivilegeScope : IDisposable
{
    private readonly string _privilegeName;
    private readonly bool _restoreRequired;

    private bool _disposed;

    public PrivilegeScope(string privilegeName)
    {
        if (string.IsNullOrWhiteSpace(privilegeName))
        {
            throw new ArgumentNullException("privilegeName");
        }

        _privilegeName = privilegeName;

        bool alreadyEnabled =
            TokenPrivilegeManager.GetPrivilegeState(privilegeName);

        _restoreRequired = !alreadyEnabled;

        if (_restoreRequired)
        {
            TokenPrivilegeManager.SetPrivilegeState(
                privilegeName,
                true
            );
        }
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;

        if (!_restoreRequired)
        {
            return;
        }

        try
        {
            TokenPrivilegeManager.SetPrivilegeState(
                _privilegeName,
                false
            );
        }
        catch
        {
            //
            // Dispose must never throw.
            //
            // Swallow intentionally to preserve finally semantics.
            //
        }

        GC.SuppressFinalize(this);
    }
}
}
"@
}
