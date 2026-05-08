<#
.SYNOPSIS
Registers the RDPControl privilege management class.

.DESCRIPTION
Defines the RDPControl.PrivilegeManager class via Add-Type. Provides high-level
privilege orchestration using the P/Invoke definitions from RDPControl.NativeMethods.

Responsibilities:
    - Enable Win32 token privileges
    - Validate privilege assignment success
    - Handle Win32 errors consistently

This file must be loaded after NativeMethods.ps1 by the module loader.
It must not be dot-sourced directly.
#>
if (-not ([System.Management.Automation.PSTypeName]'RDPControl.PrivilegeManager').Type) {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.ComponentModel;

namespace RDPControl {

    internal static class PrivilegeManager {

        public static void EnablePrivilege(string privilegeName) {

            IntPtr tokenHandle = IntPtr.Zero;

            try {

                bool opened = NativeMethods.OpenProcessToken(
                    System.Diagnostics.Process.GetCurrentProcess().Handle,
                    NativeMethods.TOKEN_ADJUST_PRIVILEGES | NativeMethods.TOKEN_QUERY,
                    ref tokenHandle
                );

                if (!opened) {
                    throw new Win32Exception(
                        Marshal.GetLastWin32Error(),
                        "Failed to open process token."
                    );
                }

                NativeMethods.LUID luid = new NativeMethods.LUID();

                bool found = NativeMethods.LookupPrivilegeValue(
                    null,
                    privilegeName,
                    ref luid
                );

                if (!found) {
                    throw new Win32Exception(
                        Marshal.GetLastWin32Error(),
                        string.Format("Failed to look up privilege value for '{0}'.", privilegeName)
                    );
                }

                NativeMethods.TOKEN_PRIVILEGES tp = new NativeMethods.TOKEN_PRIVILEGES {
                    PrivilegeCount = 1,
                    Luid           = luid,
                    Attributes     = NativeMethods.SE_PRIVILEGE_ENABLED
                };

                NativeMethods.AdjustTokenPrivileges(
                    tokenHandle,
                    false,
                    ref tp,
                    0,
                    IntPtr.Zero,
                    IntPtr.Zero
                );

                // GetLastWin32Error must be read immediately after AdjustTokenPrivileges
                // before any other call can overwrite the thread error state
                int lastError = Marshal.GetLastWin32Error();

                if (lastError == NativeMethods.ERROR_NOT_ALL_ASSIGNED) {
                    throw new UnauthorizedAccessException(
                        string.Format(
                            "Privilege '{0}' could not be fully assigned (ERROR_NOT_ALL_ASSIGNED).",
                            privilegeName
                        )
                    );
                }

                if (lastError != 0) {
                    throw new Win32Exception(
                        lastError,
                        string.Format(
                            "AdjustTokenPrivileges failed for privilege '{0}'.",
                            privilegeName
                        )
                    );
                }
            }
            finally {
                if (tokenHandle != IntPtr.Zero) {
                    NativeMethods.CloseHandle(tokenHandle);
                }
            }
        }
    }
}
"@
}
