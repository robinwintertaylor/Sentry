# Deploying Sentry

End to end, about twenty minutes. Steps 1–4 are on the Windows machine and need an administrator prompt once. Steps 5–7 are in Buzz.

Read `WHAT-IS-SENTRY.md` first if you haven't — it explains why the design looks the way it does, which makes several steps here make more sense.

---

## Before you start

You need:

- A Windows 10 or 11 machine you administer
- A Buzz relay you can reach, and the desktop app
- An API key for whichever model provider you're using
- About 2 GB of disk for logs and collections

**One decision to make now:** where evidence goes. Local-only is fine for a first run, but if the machine is ever genuinely compromised the local logs are the first thing an attacker clears. Step 7 covers the options; it's worth reading before you start rather than after.

---

## 1. Create the collection account

Open PowerShell **as Administrator**:

```powershell
$pw = Read-Host -AsSecureString "Password for sentry-svc"
New-LocalUser -Name 'sentry-svc' -Password $pw -PasswordNeverExpires `
  -Description 'Sentry read-only security collection'
```

Do **not** add it to Administrators. Nothing here needs admin rights. Reading the Security log needs membership of *Event Log Readers*, which is a much narrower grant and is handled in the next step.

Use a long random password and put it in your password manager. You'll need it once, when registering the scheduled tasks.

---

## 2. Copy the scripts and run setup

Copy the `scripts` folder to `C:\ProgramData\Sentry\scripts`, then:

```powershell
cd C:\ProgramData\Sentry\scripts
.\Register-SentryTask.ps1 -SentryUser 'sentry-svc'
```

That single script does seven things:

| # | What | Why it matters |
|---|---|---|
| 1 | Process-creation auditing **with command lines** | Off by default. Without command lines you see "powershell.exe ran" and nothing about what it did |
| 2 | PowerShell script-block logging | Captures what scripts actually contained, including after de-obfuscation |
| 3 | Security log grown to 1 GB | The default rolls over in hours on a busy machine, so an hourly agent sees nothing |
| 4 | Adds the account to *Event Log Readers* and *Performance Log Users* | Least-privilege log access, and process-to-connection mapping |
| 5 | Creates `C:\ProgramData\Sentry` with restrictive permissions | The account can write collections but **not delete** them |
| 6 | Registers the hourly collection task | Runs `Invoke-SentryCollection.ps1` |
| 7 | Registers the monthly posture task | Runs `Invoke-SentryMonthly.ps1`, first Monday 09:00 |

You'll be prompted for the `sentry-svc` password when the tasks register.

Verify:

```powershell
Get-ScheduledTask Sentry-*
```

Two tasks should appear, both Ready.

---

## 3. Install Sysmon

Optional but strongly recommended. The collectors fall back to standard Windows auditing without it, but Sysmon is the difference between *"powershell.exe ran"* and *"powershell.exe ran from Word, unsigned, hash abc123, and resolved a domain registered last Tuesday."*

Download Sysmon from Microsoft Sysinternals, and a community configuration — SwiftOnSecurity's or Olaf Hartong's modular config are the usual starting points. Then:

```powershell
.\Sysmon64.exe -accepteula -i sysmonconfig.xml
wevtutil sl "Microsoft-Windows-Sysmon/Operational" /ms:1073741824
```

`Get-SecuritySnapshot.ps1` reports whether Sysmon is present, so Sentry knows how far to trust its own visibility and will say so in reports.

---

## 4. Confirm the collectors work

```powershell
cd C:\ProgramData\Sentry\scripts
.\Invoke-SentryCollection.ps1
Get-Content "$env:ProgramData\Sentry\collections\*\manifest.json" | Select-Object -Last 20
```

Every collector should report `ok: true`. If one fails, fix it now — a broken collector produces silence, and silence is indistinguishable from a clean machine.

Then generate the monthly posture once so the agent has something to read before the first month elapses:

```powershell
.\Invoke-SentryMonthly.ps1
```

---

## 5. Create the agent in Buzz

Create a channel called `#watch`, then import the agent:

**My Agents → Import**, choose `sentry.agent.json`.

Then open it and set:

| Field | Value |
|---|---|
| **Who can send instructions** | **Only me** |
| **Where to run** | Goose |
| **Provider / Model** | `openrouter` / `moonshotai/kimi-k3` (or your choice — see below) |
| **Environment variables** | `OPENROUTER_API_KEY` = your key |

**"Only me" is deliberate.** No orchestrator should be able to task the security agent, and Sentry should not be reachable from a shared job channel. If you want another agent aware of an incident, you relay it yourself.

On model choice: log analysis is exactly the kind of work where a weak model produces confident nonsense. Use something with real reasoning ability. This is not the place to economise.

Finally, add Sentry to `#watch` and nothing else.

---

## 6. Configure its one tool

Sentry needs exactly one MCP server:

```
npx -y @modelcontextprotocol/server-filesystem C:\ProgramData\Sentry
```

Scope it to `C:\ProgramData\Sentry` — not the `collections` subfolder, or the monthly report will have nothing to read. That directory argument is the sandbox; it cannot see anything else on the machine.

**Now the important part.** Goose ships with its developer extension enabled by default, which includes a general shell. For this agent that default is wrong, and you need to turn it off in Goose's own configuration for Sentry specifically. Everything in the persona about "never construct your own PowerShell" is an instruction; removing the shell is the enforcement.

If you skip this, you have a security-monitoring agent with the ability to run arbitrary commands on the machine it monitors. That is the one configuration mistake in this deployment that genuinely matters.

---

## 7. Get evidence off the machine

Local logs are worthless if the machine is compromised. Pick one:

**Simplest** — point the archive at a synced folder. Add a nightly scheduled task:

```powershell
Compress-Archive -Path "$env:ProgramData\Sentry\collections\*" `
  -DestinationPath "$env:OneDrive\SentryArchive\$(Get-Date -f yyyyMMdd).zip"
```

Google Drive works identically; you already have that connector available in Buzz, so the agent can read history from there rather than from the endpoint.

**Better** — append-only storage the machine's own account cannot delete from: S3 with object lock, or Azure Blob with an immutability policy. Overkill for a home laptop, correct for a work one.

Whichever you choose, the account that writes archives should not be able to delete them. That's the whole point.

---

## 8. First conversation

In `#watch`:

```
@sentry what did you see in the last hour?
```

You should get a short summary naming the log sources it read. If it reports gaps — script-block logging off, no Sysmon — fix those before trusting a quiet report.

**Test that detection actually works.** From an ordinary user prompt:

```powershell
powershell -nop -w hidden -enc VwByAGkAdABlAC0ATwB1AHQAcAB1AHQAIAAiAHQAZQBzAHQAIgA=
```

That's an encoded `Write-Output "test"` — completely harmless, but it should trip both `encoded-command` and `hidden-or-noprofile`. If Sentry doesn't mention it on the next hourly pass, script-block logging isn't working and you should go back to step 2.

Then ask for the hardening report:

```
@sentry give me this month's hardening report
```

---

## Tuning it

**Too noisy?** Tell Sentry directly in `#watch` — "the Acme backup agent runs unsigned from ProgramData every night, that's expected." It'll factor that into future passes. If a pattern recurs weekly, better to add it to the persona under a "known-normal on this machine" section so it survives context loss.

**Too quiet?** Check `manifest.json` for failed collectors first, then whether Sysmon is installed. Genuine quiet is normal; unexplained quiet is not.

**Reports too long?** The persona caps the monthly report at three to seven recommendations. If you want fewer, say so — that's a one-line persona edit.

---

## Troubleshooting

| Symptom | Cause |
|---|---|
| "No collections found" | Task not running, or the MCP path is scoped to the wrong folder |
| Every report says logging is disabled | `Register-SentryTask.ps1` wasn't run as Administrator |
| Process events with no command lines | Step 2 item 1 didn't apply — check the `ProcessCreationIncludeCmdLine_Enabled` registry value |
| Script activity always empty | Script-block logging off, or the machine genuinely runs no PowerShell |
| Task shows "Ready" but never runs | Laptop asleep at the trigger time; `StartWhenAvailable` catches up on next wake |
| Agent silent entirely | Not a member of `#watch`, or stopped |
| Agent tries to run its own commands | Goose developer extension still enabled — step 6 |

---

## A closing note on trust

Run it for a few weeks before relying on it. Watch how often it's right and how often it's noise. Build a sense of what its "nothing of note" is worth, because that judgement is what makes the alarming report meaningful when it eventually comes.

And if you later want a narrow set of pre-approved containment actions — isolate the network adapter, kill a specific named process — that's a reasonable next step. But it should be a fixed allowlist of specific, reviewed scripts, never a general grant to run PowerShell. The gap between those two things is the entire security model.
