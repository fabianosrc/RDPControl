# Changelog

All notable changes to this project will be documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Planned
- Pester unit and integration test suite
- `Get-RdpAuditLog` cmdlet for querying the audit trail
- `Export-RdpSnapshot` / `Import-RdpSnapshot` for offline snapshot transfer
- GitHub Actions CI pipeline (lint → test → build → publish)
- External Pester module dependency declared in manifest

---

## [0.1.0] — 2025-05-05

### Added

#### Environment
- `Initialize-RdpEnvironment` — creates the `%ProgramData%\RDPControl` directory tree, writes `environment.json`, and initializes the SQLite schema. Supports `-Force` (repair) and `-Purge` (full reset with confirmation).
- `Get-RdpEnvironment` — reads and returns the current environment configuration.
- `Assert-RdpEnvironment` (private) — validates the environment is initialized before any cmdlet executes.

#### Policy
- `Get-RdpPort` — reads the current RDP listening port from the registry.
- `Set-RdpPort` — changes the RDP port, optionally updates the firewall rule, and restarts TermService. Supports `-SkipFirewall`, `-Force`, and `-WhatIf`.
- `Get-RdpService` — returns the current state of the TermService (Remote Desktop Services).
- `Set-RdpService` — enables or disables the Remote Desktop service. Supports `-WhatIf`.
- `Get-RdpSessionMode` — returns the current multi-session (RDM) mode.
- `Set-RdpSessionMode` — configures single-session or multi-session mode by applying enforcement or restoring the original binary. Supports `-WhatIf`.

#### User management
- `Add-RdpUser` — adds a user or group to the Remote Desktop Users local group.
- `Get-RdpUser` — lists members of the Remote Desktop Users local group.
- `Remove-RdpUser` — removes a user or group from the Remote Desktop Users local group.

#### Session
- `Get-RdpSession` — enumerates active and disconnected RDP sessions via the WTS API.
- `Disconnect-RdpSession` — disconnects a session by ID without logging it off. Supports `-WhatIf`.
- `Stop-RdpSession` — logs off a session by ID. Supports `-WhatIf`.

#### Snapshot
- `New-RdpSnapshot` — captures a SHA-256 snapshot of `termsrv.dll` and stores it in the SQLite database.
- `Get-RdpSnapshot` — queries stored snapshots, optionally filtering by ID, hash, or returning only the latest.
- `Remove-RdpSnapshot` — deletes a snapshot by ID. Enforced snapshots are protected and require `-Force`.
- `Restore-RdpSnapshot` — restores `termsrv.dll` from a stored snapshot. Supports restore by ID or from the latest snapshot.

#### Watchdog
- `Start-RdpWatchdog` — registers a Windows Scheduled Task (`\RDPControl\RDPControl Watchdog`) triggered by Windows Update events (Event ID 19/20) to re-apply enforcement automatically.
- `Stop-RdpWatchdog` — unregisters the watchdog scheduled task.
- `Get-RdpWatchdogStatus` — returns the current registration state and last run time of the watchdog task.

#### Infrastructure
- SQLite-backed store with `System.Data.SQLite` — dual-runtime support (`net46` for Windows PowerShell 5.1, `netstandard2.0` for PowerShell 7+), with native interop DLLs for `x64` and `x86`.
- `RDPControl.PrivilegeScope` (C# / P/Invoke) — RAII privilege scope for `SeTakeOwnershipPrivilege` and `SeRestorePrivilege`, ensuring deterministic privilege rollback.
- `RDPControl.NativeMethods` / `RDPControl.TokenPrivilegeManager` — internal Win32 interop layer (advapi32: `OpenProcessToken`, `LookupPrivilegeValue`, `AdjustTokenPrivileges`, `GetTokenInformation`).
- Audit trail: every state-changing operation writes a record to the SQLite audit table.
- `PSScriptAnalyzerSettings.psd1` — strict ruleset covering security, compatibility (`5.1`), documentation, and formatting.
- Build pipeline: `Invoke-Pipeline.ps1` orchestrating validation (AST parse, approved verbs, comment-based help), lint, test, and artifact build with SHA-256 integrity manifest (`hashes.json`).

[Unreleased]: https://github.com/fabianosrc/RDPControl/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/fabianosrc/RDPControl/releases/tag/v0.1.0
