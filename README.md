# RDPControl

A PowerShell module for managing Remote Desktop on Windows — port configuration,
multi-session policy, user access control, session management, binary snapshots,
and a self-healing watchdog.

[![PowerShell Gallery](https://img.shields.io/powershellgallery/v/RDPControl)](https://www.powershellgallery.com/packages/RDPControl)
[![License](https://img.shields.io/github/license/fabianosrc/RDPControl)](LICENSE)

---

## ⚠️ Disclaimer

> **RDPControl does not distribute any modified, modified, or pre-configured binary
> files.** The module works exclusively with binaries already present on the
> operating system of the machine where it runs. All modifications are computed
> locally at runtime from the original system file on that specific machine.
>
> **Use of this module is at the sole responsibility of the user.** The author
> provides this software as-is, without warranty of any kind, and is not liable
> for any damage, data loss, license violation, or legal consequence arising from
> its use. Users are responsible for ensuring compliance with all applicable laws,
> software license agreements, and organizational policies before using this module.

---

## Requirements

| Requirement | Minimum |
|---|---|
| Operating System | Windows 10 / Windows Server 2016 or later |
| PowerShell | 5.1 (Windows PowerShell) or 7.0+ (PowerShell Core) |
| Privileges | **Administrator** — required for all state-changing cmdlets |
| Architecture | x64 or x86 |

---

## Installation

```powershell
Install-Module -Name RDPControl -Scope CurrentUser
```

After installation, initialize the environment once (required before using any
other cmdlet):

```powershell
# Must run as Administrator
Initialize-RdpEnvironment
```

This creates the `%ProgramData%\RDPControl` directory tree and initializes the
SQLite database used for snapshots and audit records.

---

## Quick Start

```powershell
# 1. Initialize (once per machine)
Initialize-RdpEnvironment

# 2. Check current RDP configuration
Get-RdpEnvironment
Get-RdpPort
Get-RdpService

# 3. Change the RDP port
Set-RdpPort -Port 3390

# 4. Take a snapshot of the current system binary
New-RdpSnapshot

# 5. Enable multi-session mode
Set-RdpSessionMode -Mode MultiSession

# 6. Enable the self-healing watchdog
Start-RdpWatchdog
```

---

## Cmdlet Reference

### Environment

| Cmdlet | Description |
|---|---|
| `Initialize-RdpEnvironment` | Creates the data directory and initializes the SQLite schema. Run once. |
| `Get-RdpEnvironment` | Returns the current environment configuration and paths. |

```powershell
# Repair missing components without affecting existing data
Initialize-RdpEnvironment -Force

# Full reset (prompts for confirmation)
Initialize-RdpEnvironment -Purge
```

---

### Policy

| Cmdlet | Description |
|---|---|
| `Get-RdpPort` | Returns the current RDP listening port from the registry. |
| `Set-RdpPort` | Changes the RDP port, updates the firewall rule, and restarts TermService. |
| `Get-RdpService` | Returns the current state of the Remote Desktop service. |
| `Set-RdpService` | Enables or disables the Remote Desktop service. |
| `Get-RdpSessionMode` | Returns the current single/multi-session mode. |
| `Set-RdpSessionMode` | Configures single-session or multi-session (RDM) mode. |

```powershell
# Change RDP port without modifying the firewall rule
Set-RdpPort -Port 3390 -SkipFirewall

# Preview the change before applying
Set-RdpPort -Port 3390 -WhatIf

# Enable multi-session mode
Set-RdpSessionMode -Mode MultiSession

# Enable Remote Desktop
Set-RdpService -Enabled $true
```

---

### User Management

| Cmdlet | Description |
|---|---|
| `Add-RdpUser` | Adds a user or group to the Remote Desktop Users local group. |
| `Get-RdpUser` | Lists members of the Remote Desktop Users local group. |
| `Remove-RdpUser` | Removes a user or group from the Remote Desktop Users local group. |

```powershell
Add-RdpUser -Identity 'DOMAIN\JohnDoe'
Add-RdpUser -Identity 'Support Team'  # local group

Get-RdpUser

Remove-RdpUser -Identity 'DOMAIN\JohnDoe'
```

---

### Session Management

| Cmdlet | Description |
|---|---|
| `Get-RdpSession` | Enumerates active and disconnected RDP sessions. |
| `Disconnect-RdpSession` | Disconnects a session by ID (session is preserved, not logged off). |
| `Stop-RdpSession` | Logs off a session by ID. |

```powershell
# List all sessions
Get-RdpSession

# Disconnect session 3 without logging it off
Disconnect-RdpSession -Id 3

# Log off session 3
Stop-RdpSession -Id 3

# Preview before acting
Stop-RdpSession -Id 3 -WhatIf
```

---

### Snapshots

Snapshots capture a SHA-256 hash and the raw bytes of `termsrv.dll`. They are
stored in the local SQLite database and can be used to restore the system binary
to a known-good state.

| Cmdlet | Description |
|---|---|
| `New-RdpSnapshot` | Captures a snapshot of the current system binary. |
| `Get-RdpSnapshot` | Queries stored snapshots. |
| `Remove-RdpSnapshot` | Deletes a snapshot by ID. |
| `Restore-RdpSnapshot` | Restores the system binary from a stored snapshot. |

```powershell
# Capture the current binary before making any changes
New-RdpSnapshot

# List all stored snapshots
Get-RdpSnapshot

# Restore from snapshot ID 1
Restore-RdpSnapshot -Id 1

# Restore from the most recent snapshot (no confirmation prompt)
Restore-RdpSnapshot -Latest -Force
```

> **Note:** `New-RdpSnapshot` detects duplicate hashes and will not create a
> second snapshot if the binary has not changed since the last capture.

---

### Watchdog

The watchdog is a Windows Scheduled Task (`\RDPControl\RDPControl Watchdog`)
that runs under the `SYSTEM` account. It is triggered by Windows Update events
(Event ID 19 and 20 from the `WindowsUpdateClient` log) and re-applies
enforcement automatically if changes are detected.

| Cmdlet | Description |
|---|---|
| `Start-RdpWatchdog` | Registers the watchdog scheduled task. Requires active enforcement. |
| `Stop-RdpWatchdog` | Unregisters the watchdog scheduled task. |
| `Get-RdpWatchdogStatus` | Returns the registration state and last run time. |

```powershell
# Enable enforcement first, then start the watchdog
Set-RdpSessionMode -Mode MultiSession
Start-RdpWatchdog

# Check watchdog state
Get-RdpWatchdogStatus

# Disable the watchdog
Stop-RdpWatchdog
```

---

## Typical Workflow

```
Initialize-RdpEnvironment
        │
        ▼
  New-RdpSnapshot          ← capture original binary before any change
        │
        ▼
Set-RdpSessionMode -Mode MultiSession   ← apply enforcement
        │
        ▼
  Start-RdpWatchdog        ← protect against Windows Update reverting the change
        │
        ▼
  (normal operation)
        │
        ├── Windows Update runs → Watchdog re-applies enforcement automatically
        │
        └── To revert:
              Stop-RdpWatchdog
              Restore-RdpSnapshot -Latest
```

---

## Audit Trail

Every state-changing operation writes a record to the local SQLite audit table.
Use `Get-RdpAuditLog` *(planned for v0.2.0)* to query the history.

The database is located at:

```
%ProgramData%\RDPControl\database\rdpcontrol.db
```

---

## Architecture Notes

- **Dual-runtime SQLite:** The module ships `System.Data.SQLite` for both
  `net46` (Windows PowerShell 5.1) and `netstandard2.0` (PowerShell 7+), with
  architecture-specific native interop DLLs for `x64` and `x86`.
- **Win32 privilege management:** File ACL operations that require
  `SeTakeOwnershipPrivilege` or `SeRestorePrivilege` use a C# RAII scope
  (`RDPControl.PrivilegeScope`) to guarantee deterministic rollback, preventing
  privilege leakage into the host process.
- **No wildcards exported:** All 21 public functions are listed explicitly in
  `FunctionsToExport` for performance and discoverability.

---

## Security

Please read [SECURITY.md](SECURITY.md) before reporting any issue.

Do not open public GitHub issues for security vulnerabilities. Use the
[GitHub private advisory](https://github.com/fabianosrc/RDPControl/security/advisories/new)
channel instead.

---

## License

[Apache License 2.0](LICENSE) — Copyright © Fabiano Moreira da Silva.
