# Changelog

All notable changes to this project will be documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Planned
- Pester unit and integration test suite (80% coverage gate before Gallery publish)
- `Get-RdpAuditLog` cmdlet for querying the audit trail
- `Export-RdpSnapshot` / `Import-RdpSnapshot` for offline snapshot transfer
- GitHub Actions CI pipeline (lint → test → build → publish)
- External Pester module dependency declared in manifest

---

## [0.1.0] — 2026-05-05

### Added

#### Environment
- `Initialize-RdpEnvironment` — creates the `%ProgramData%\RDPControl` directory tree, writes `environment.json`, and initializes the SQLite schema. Supports `-Force` (repair) and `-Purge` (full reset with confirmation).
- `Get-RdpEnvironment` — reads and returns the current environment configuration. Supports `-Strict` for full path validation.
- `Assert-RdpEnvironment` (private) — validates the environment is initialized before any cmdlet executes.

#### Policy
- `Get-RdpPort` — reads the current RDP listening port from the registry.
- `Set-RdpPort` — changes the RDP port, optionally updates the firewall rule, and restarts TermService. Supports `-SkipFirewall`, `-Force`, and `-WhatIf`.
- `Get-RdpService` — returns the current state of the TermService (Remote Desktop Services).
- `Set-RdpService` — enables or disables the Remote Desktop service. Supports `-WhatIf`. Detects active RDP sessions before disabling to prevent lock-out.
- `Get-RdpSessionMode` — returns the current session mode (`Standard` / `Concurrent`) and binary integrity hash.
- `Set-RdpSessionMode` — configures Standard or Concurrent session mode by applying or reverting binary enforcement. Supports `-WhatIf`, `-Force`, and `-DryRun`.

#### Session Mode — DryRun
- `Set-RdpSessionMode -DryRun` — analyzes the target binary and returns a `RDPControl.DryRunResult` object without applying any changes. Fully pipeline-friendly.
- `RDPControl.format.ps1xml` — declarative list view for `RDPControl.DryRunResult`.
- `RDPControl.types.ps1xml` — computed properties `IsApplicable` and `RequiresSnapshot`, alias properties `Current` and `Target`, and `DefaultDisplayPropertySet`.

#### User management
- `Add-RdpUser` — adds a user or group to the Remote Desktop Users local group. Accepts array and pipeline input. Skips existing members.
- `Get-RdpUser` — lists members of the Remote Desktop Users local group via `Get-LocalGroupMember`.
- `Remove-RdpUser` — removes a user or group from the Remote Desktop Users local group. Accepts array and pipeline input.

#### Session
- `Get-RdpSession` — enumerates active and disconnected RDP sessions via the WTS API.
- `Disconnect-RdpSession` — disconnects a session by ID without logging it off. Supports `-WhatIf`.
- `Stop-RdpSession` — logs off a session by ID. Supports `-WhatIf`.

#### Snapshot
- `New-RdpSnapshot` — captures a SHA-256 snapshot of the target binary and stores it in the SQLite database. Detects duplicate hashes (idempotent).
- `Get-RdpSnapshot` — queries stored snapshots, optionally filtering by ID or returning only the latest.
- `Remove-RdpSnapshot` — deletes a snapshot by ID. Blocks removal of the last snapshot while enforcement is active.
- `Restore-RdpSnapshot` — restores the target binary from a stored snapshot. Supports restore by ID or from the most recent snapshot.

#### Watchdog
- `Start-RdpWatchdog` — registers a Windows Scheduled Task (`\RDPControl\RDPControl Watchdog`) triggered by Windows Update events (Event ID 19/20) to re-apply enforcement automatically. Runs as `SYSTEM`.
- `Stop-RdpWatchdog` — unregisters the watchdog scheduled task.
- `Get-RdpWatchdogStatus` — returns the current registration state and last run time of the watchdog task.

#### Infrastructure
- SQLite-backed store with `System.Data.SQLite` — dual-runtime support (`net46` for Windows PowerShell 5.1, `netstandard2.0` for PowerShell 7+), with native interop DLLs for `x64` and `x86`.
- Store Core/Provider pattern — `Store\Core` defines domain contracts, `Store\Providers\SQLite` implements persistence. Provider is replaceable without touching Core or public cmdlets.
- `RDPControl.PrivilegeScope` (C# / P/Invoke) — RAII privilege scope for `SeTakeOwnershipPrivilege` and `SeRestorePrivilege`, ensuring deterministic privilege rollback.
- `RDPControl.NativeMethods` / `RDPControl.TokenPrivilegeManager` — internal Win32 interop layer (advapi32).
- Audit trail — every state-changing operation writes a record to the SQLite audit table.
- `PSScriptAnalyzerSettings.psd1` — strict ruleset covering security, compatibility, documentation, and formatting.
- Build pipeline — `tools\Invoke-Pipeline.ps1` orchestrating lint, validation, test, build, and publish. Blocks publish when `-SkipTests` is active (80% coverage required).

### Performance
- `Get-RdpUser` migrated from legacy ADSI `WinNT://` provider to `Get-LocalGroupMember` — ~7x faster, eliminates COM/RPC overhead.
- `Find-BinarySignature` optimized with `Array.IndexOf` for fast native byte scanning — significantly faster on large binaries. Logic moved to `end` block to guarantee single execution regardless of pipeline input.

### Fixed
- UNIQUE constraint violation on duplicate snapshot hash — `New-StoreSnapshot` now returns the existing snapshot ID instead of failing.
- `Find-BinarySignature` executing multiple times when called via pipeline — resolved by moving search logic to the `end` block.

[Unreleased]: https://github.com/fabianosrc/RDPControl/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/fabianosrc/RDPControl/releases/tag/v0.1.0
