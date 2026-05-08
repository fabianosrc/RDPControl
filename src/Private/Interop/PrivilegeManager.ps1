<#
.SYNOPSIS
Registers RDPControl privilege management classes.

.DESCRIPTION
Defines the following classes via Add-Type:

    RDPControl.PrivilegeManager
        Internal static class responsible for reading and setting Win32 token
        privileges. Uses P/Invoke definitions from RDPControl.NativeMethods.

    RDPControl.PrivilegeScope
        IDisposable scope object (RAII pattern) that enables a privilege on
        construction and deterministically restores the previous privilege
        state on Dispose, preventing privilege leakage into the host process.

        Usage:
            $scope = [RDPControl.PrivilegeScope]::new("SeTakeOwnershipPrivilege")
            try     { # critical section }
            finally { $scope.Dispose() }

This file must be loaded after NativeMethods.ps1 by the module loader.
It must not be dot-sourced directly.
#>
if (-not ([System.Management.Automation.PSTypeName]'RDPControl.PrivilegeScope').Type) {
    Add-Type -TypeDefinition @"
    using System;
    using System.Runtime.InteropServices;
    using System.ComponentModel;

    namespace RDPControl
    {
        internal static class PrivilegeManager
        {

            internal static bool GetPrivilegeState(string privilegeName)
            {
                IntPtr tokenHandle = IntPtr.Zero;

                try {
                    bool opened = NativeMethods.OpenProcessToken(
                        System.Diagnostics.Process.GetCurrentProcess().Handle,
                        NativeMethods.TOKEN_QUERY,
                        ref tokenHandle
                    );

                    if (!opened) {
                        throw new Win32Exception(Marshal.GetLastWin32Error(),
                            "Failed to open process token for privilege state query.");
                    }

                    NativeMethods.LUID luid = new NativeMethods.LUID();

                    bool found = NativeMethods.LookupPrivilegeValue(null, privilegeName, ref luid);

                    if (!found) {
                        throw new Win32Exception(Marshal.GetLastWin32Error(),
                            string.Format(
                                "Failed to look up privilege value for '{0}'.", privilegeName));
                    }

                    // Query buffer size
                    int bufferSize = 0;
                    NativeMethods.GetTokenInformation(tokenHandle,
                        NativeMethods.TOKEN_INFORMATION_CLASS.TokenPrivileges,
                        IntPtr.Zero, 0, out bufferSize);

                    IntPtr buffer = Marshal.AllocHGlobal(bufferSize);

                    try {
                        int returnedSize = 0;
                        bool queried = NativeMethods.GetTokenInformation(tokenHandle,
                            NativeMethods.TOKEN_INFORMATION_CLASS.TokenPrivileges,
                            buffer, bufferSize, out returnedSize);

                        if (!queried) {
                            throw new Win32Exception(Marshal.GetLastWin32Error(),
                                "Failed to query token privilege information.");
                        }

                        int count = Marshal.ReadInt32(buffer);
                        int entrySize = Marshal.SizeOf(typeof(NativeMethods.LUID_AND_ATTRIBUTES));
                        IntPtr ptr = IntPtr.Add(buffer, sizeof(int));

                        for (int i = 0; i < count; i++) {
                            NativeMethods.LUID_AND_ATTRIBUTES la =
                                (NativeMethods.LUID_AND_ATTRIBUTES)Marshal.PtrToStructure(
                                    ptr, typeof(NativeMethods.LUID_AND_ATTRIBUTES));

                            if (la.Luid.LowPart == luid.LowPart &&
                                la.Luid.HighPart == luid.HighPart) {
                                return (la.Attributes & NativeMethods.SE_PRIVILEGE_ENABLED) != 0;
                            }

                            ptr = IntPtr.Add(ptr, entrySize);
                        }
                    } finally {
                        Marshal.FreeHGlobal(buffer);
                    }

                    return false;
                } finally {
                    if (tokenHandle != IntPtr.Zero) {
                        NativeMethods.CloseHandle(tokenHandle);
                    }
                }
            }

            internal static void SetPrivilegeState(string privilegeName, bool enable)
            {
                IntPtr tokenHandle = IntPtr.Zero;

                try {
                    bool opened = NativeMethods.OpenProcessToken(
                        System.Diagnostics.Process.GetCurrentProcess().Handle,
                        NativeMethods.TOKEN_ADJUST_PRIVILEGES | NativeMethods.TOKEN_QUERY,
                        ref tokenHandle
                    );

                    if (!opened) {
                        throw new Win32Exception(Marshal.GetLastWin32Error(),
                            "Failed to open process token.");
                    }

                    NativeMethods.LUID luid = new NativeMethods.LUID();

                    bool found = NativeMethods.LookupPrivilegeValue(null, privilegeName, ref luid);

                    if (!found) {
                        throw new Win32Exception(Marshal.GetLastWin32Error(),
                            string.Format(
                                "Failed to look up privilege value for '{0}'.", privilegeName));
                    }

                    // Correct TOKEN_PRIVILEGES layout using LUID_AND_ATTRIBUTES
                    NativeMethods.TOKEN_PRIVILEGES tp = new NativeMethods.TOKEN_PRIVILEGES {
                        PrivilegeCount = 1,
                        Privileges     = new NativeMethods.LUID_AND_ATTRIBUTES {
                            Luid       = luid,
                            Attributes = enable ? NativeMethods.SE_PRIVILEGE_ENABLED : 0u
                        }
                    };

                    bool adjusted = NativeMethods.AdjustTokenPrivileges(
                        tokenHandle, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero
                    );

                    // Must be read immediately after AdjustTokenPrivileges
                    int lastError = Marshal.GetLastWin32Error();

                    if (!adjusted) {
                        throw new Win32Exception(lastError,
                            string.Format(
                                "AdjustTokenPrivileges returned false for privilege '{0}'.",
                                privilegeName));
                    }

                    if (lastError == NativeMethods.ERROR_NOT_ALL_ASSIGNED) {
                        throw new UnauthorizedAccessException(
                            string.Format(
                                "Privilege '{0}' could not be fully {1} (ERROR_NOT_ALL_ASSIGNED).",
                                privilegeName,
                                enable ? "enabled" : "disabled"
                            )
                        );
                    }

                    if (lastError != 0) {
                        throw new Win32Exception(lastError,
                            string.Format(
                                "AdjustTokenPrivileges failed for privilege '{0}'.", privilegeName));
                    }
                } finally {
                    if (tokenHandle != IntPtr.Zero) {
                        NativeMethods.CloseHandle(tokenHandle);
                    }
                }
            }
        }

        public sealed class PrivilegeScope : IDisposable
        {
            private readonly string _privilegeName;
            private readonly bool   _previousState;
            private          bool   _disposed;

            public PrivilegeScope(string privilegeName)
            {
                if (string.IsNullOrWhiteSpace(privilegeName)) {
                    throw new ArgumentNullException("privilegeName");
                }

                _privilegeName = privilegeName;
                _previousState = PrivilegeManager.GetPrivilegeState(privilegeName);

                if (!_previousState) {
                    PrivilegeManager.SetPrivilegeState(privilegeName, true);
                }
            }

            public void Dispose()
            {
                if (_disposed) {
                    return;
                }

                _disposed = true;

                // Restore previous state only if we changed it
                if (!_previousState) {
                    PrivilegeManager.SetPrivilegeState(_privilegeName, false);
                }
            }
        }
    }
"@
}
