# RDPControl

A PowerShell module for managing Remote Desktop on Windows — port configuration,
multi-session policy, user access control, session management, binary snapshots,
and a self-healing watchdog.

[![PowerShell Gallery](https://img.shields.io/powershellgallery/v/RDPControl)](https://www.powershellgallery.com/packages/RDPControl)
[![License](https://img.shields.io/github/license/fabianosrc/RDPControl)](LICENSE)

---

## ⚠️ Disclaimer

> **RDPControl does not distribute any modified or pre-configured binary
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

# 5. Preview what enabling multi-session would do (no changes applied)
Set-RdpSessionMode -Enabled -DryRun

# 6. Enable multi-session mode
Set-RdpSessionMode -Enabled

# 7. Enable the self-healing watchdog
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
| `Get-RdpSessionMode` | Returns the current session mode and enforcement state. |
| `Set-RdpSessionMode` | Configures Standard or Concurrent session mode. |

```powershell
# Change RDP port without modifying the firewall rule
Set-RdpPort -Port 3390 -SkipFirewall

# Preview the change before applying
Set-RdpPort -Port 3390 -WhatIf

# Enable concurrent session mode
Set-RdpSessionMode -Enabled

# Enable Remote Desktop
Set-RdpService -Enabled
```

---

### Session Mode — DryRun

Before applying any session mode change, use `-DryRun` to analyze the system
binary without modifying anything. The result is a structured
`RDPControl.DryRunResult` object — fully pipeline-friendly.

```powershell
# Analyze without applying
Set-RdpSessionMode -Enabled -DryRun

# Export analysis as JSON (useful for CI/CD)
Set-RdpSessionMode -Enabled -DryRun | ConvertTo-Json

# Gate a CI pipeline on signature availability
$analysis = Set-RdpSessionMode -Enabled -DryRun
if (-not $analysis.IsApplicable) {
    throw 'Signature not found. Enforcement is not supported on this binary.'
}

# Check if a new snapshot would be required
if ($analysis.RequiresSnapshot) {
    Write-Host 'A new snapshot will be created before applying changes.'
}
```

**DryRun output properties:**

| Property | Description |
|---|---|
| `CurrentState` | Current session mode (`Standard` or `Concurrent`) |
| `TargetState` | Session mode that would be applied |
| `BinaryPath` | Full path to the target binary |
| `Hash` | SHA-256 hash of the current binary |
| `SnapshotAction` | Whether a new snapshot would be created or reused |
| `SignatureFound` | Whether the configuration signature was located |
| `SignatureOffset` | Hex offset of the located signature |
| `WriteOffset` | Hex offset where bytes would be written |
| `BranchType` | Branch instruction type (`jz` or `jne`) |
| `CurrentBytes` | Hex dump of the bytes currently at the write location |
| `ReplacementHex` | Hex dump of the bytes that would be written |
| `IsApplicable` | Computed: `$true` if signature was found and enforcement can proceed |
| `RequiresSnapshot` | Computed: `$true` if a new snapshot would be created |

---

### User Management

| Cmdlet | Description |
|---|---|
| `Add-RdpUser` | Adds a user or group to the Remote Desktop Users local group. |
| `Get-RdpUser` | Lists members of the Remote Desktop Users local group. |
| `Remove-RdpUser` | Removes a user or group from the Remote Desktop Users local group. |

```powershell
Add-RdpUser -Identity 'DOMAIN\JohnDoe'
Add-RdpUser -Identity 'Support Team'

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
Get-RdpSession

Disconnect-RdpSession -Id 3

Stop-RdpSession -Id 3

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
New-RdpSnapshot

Get-RdpSnapshot

Restore-RdpSnapshot -Id 1

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
Set-RdpSessionMode -Enabled
Start-RdpWatchdog

Get-RdpWatchdogStatus

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
Set-RdpSessionMode -Enabled -DryRun   ← analyze without applying
        │
        ▼
Set-RdpSessionMode -Enabled           ← apply enforcement
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

## Development

### Pipeline

All development tasks are orchestrated via a single entry point:

```powershell
# Full pipeline: lint → validate → test → build
.\tools\Invoke-Pipeline.ps1

# Dev workflow: lint + validate + reimport from source (fastest, no build)
.\tools\Invoke-Pipeline.ps1 -SkipTests -SkipBuild -DevImport

# Dev workflow with build: lint + validate + build + reimport
.\tools\Invoke-Pipeline.ps1 -SkipTests -ImportAfterBuild

# Lint and validation only (no tests, no build, no import)
.\tools\Invoke-Pipeline.ps1 -SkipTests -SkipBuild

# Full pipeline + publish to Gallery (requires PSGALLERY_API_KEY)
.\tools\Invoke-Pipeline.ps1 -Publish
```

| Scenario | Command |
|---|---|
| Quick dev loop | `-SkipTests -SkipBuild -DevImport` |
| Validate before commit | `-SkipTests -SkipBuild` |
| Full local test | *(no flags)* |
| Publish to Gallery | `-Publish` |

> **Note:** `-Publish` is blocked when `-SkipTests` is active.
> 80% Pester code coverage is required before publishing to the PowerShell Gallery.

### Individual tools

The `tools\private\` scripts can also be run independently:

```powershell
# Lint only
.\tools\private\Lint.ps1 -Strict

# Tests with coverage
.\tools\private\Tests.ps1 -Coverage

# Reimport module from source
.\tools\private\DevImport.ps1

# Build artifact only
.\tools\private\Build.ps1 -SkipLint -SkipTests
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
- **Declarative output formatting:** The module ships `RDPControl.format.ps1xml`
  and `RDPControl.types.ps1xml` for structured, pipeline-friendly output. All
  public cmdlets return typed objects — no `Write-Host` in the public surface.
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
