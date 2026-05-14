# Security Policy

## Supported Versions

Only the latest published version of RDPControl receives security fixes.
Older versions are not modified; upgrade to the current release.

| Version | Supported |
|---------|-----------|
| 0.1.x   | ✅ Current |

---

## Scope and Threat Model

RDPControl is a PowerShell module that operates with **Administrator privileges**
on Windows systems. Its scope includes:

- Reading and writing Windows Registry keys under `HKLM:\SYSTEM\CurrentControlSet`.
- Managing Windows Firewall rules via the NetFW COM API.
- Stopping and starting the TermService (Remote Desktop Services).
- Reading, hashing, and restoring system binaries under `%SystemRoot%\System32`.
- Registering and unregistering Windows Scheduled Tasks under the `SYSTEM` account.
- Persisting state in a SQLite database under `%ProgramData%\RDPControl`.

Because the module requires and validates elevation before every state-changing
operation, **it is not intended to be used as a privilege escalation vector**.
Any finding that allows a non-elevated process to leverage this module to gain
elevated capabilities is considered a valid security issue.

---

## Reporting a Vulnerability

**Please do not open a public GitHub issue for security vulnerabilities.**

Report security issues privately via one of the following channels:

- **GitHub private advisory:** [Security → Report a vulnerability](https://github.com/fabianosrc/RDPControl/security/advisories/new)
- **Email:** fabiano.msrc@outlook.com

Include as much of the following as possible:

- A clear description of the vulnerability and its potential impact.
- Steps to reproduce the issue, including PowerShell version, Windows build, and
  module version (`(Get-Module RDPControl).Version`).
- Any proof-of-concept code or scripts.
- Whether you believe the issue is exploitable without Administrator privileges.

You will receive an acknowledgement within **72 hours**. If you do not hear back,
follow up via GitHub.

---

## Disclosure Policy

This project follows **coordinated disclosure**:

1. You report the issue privately.
2. The maintainer confirms and investigates within 72 hours.
3. A fix is developed and tested.
4. A modified release is published.
5. A GitHub Security Advisory is made public after the fix is available.

The target remediation window is **30 days** for critical issues and **90 days**
for lower-severity findings, subject to complexity.

---

## Security Design Notes

The following design decisions are intentional and are documented here to
avoid being reported as vulnerabilities:

### Binary modification without distribution
RDPControl **does not distribute modified binaries**. The module reads,
hashes, and snapshots `termsrv.dll` *as it exists on the target system*.
Any modification applied by the module is computed locally at runtime from
the original binary on that specific machine. The module never downloads,
ships, or injects pre-built modified files. See [`DISCLAIMER`](#disclaimer) below.

### `PATH` mutation for SQLite interop
On load, the module prepends the native interop directory to `$env:PATH`
so the .NET runtime can resolve `SQLite.Interop.dll`. This is the standard
pattern for managed/native hybrid assemblies and is scoped to the current
process. No persistent `PATH` changes are made to the system.

### Scheduled Task runs as SYSTEM
The watchdog task created by `Start-RdpWatchdog` runs under the `SYSTEM`
account. This is required because re-applying enforcement after a Windows
Update must succeed before a user session is present. Registering this
task requires Administrator privileges, which the module verifies before
proceeding.

### SQLite database permissions
The database at `%ProgramData%\RDPControl\database\rdpcontrol.db` is
created with NTFS permissions inherited from `%ProgramData%`. The module
does not explicitly restrict or expand those permissions beyond what the
OS provides by default. If your environment requires stricter database
ACLs, set them manually after `Initialize-RdpEnvironment`.

---

## Disclaimer

> **RDPControl does not distribute any modified or pre-configured
> binary files.** The module works exclusively with binaries already present
> on the operating system of the machine where it runs. All modifications are
> computed locally from the original system file.
>
> Use of this module is at the **sole responsibility of the user**.
> The author provides this software as-is, without warranty of any kind.
> The author is not liable for any damage, data loss, license violation,
> or legal consequence arising from its use. Users are responsible for
> ensuring that their use of this module complies with all applicable laws,
> software license agreements, and organizational policies.
