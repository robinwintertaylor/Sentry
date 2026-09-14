# Sentry on Claude Code

This is Sentry ported from Buzz to **Claude Code** (the Anthropic CLI / Agent SDK). The security model is identical to the original: a Windows scheduled task runs read-only collectors, and the agent only *reads* their JSON output. The port's job is to reproduce that boundary in Claude Code's own configuration.

## What maps to what

| Buzz concept | Claude Code equivalent |
|---|---|
| `sentry.persona.md` (system prompt) | `.claude/agents/sentry.md` — a subagent with its own system prompt |
| Goose "one MCP: filesystem, scoped" | `.mcp.json` → `sentry-fs` server, scoped to `C:\ProgramData\Sentry` |
| "Turn off Goose's developer/shell extension" | `.claude/settings.json` → `Bash`, `Write`, `Edit` **denied** |
| `instructions.md` (operating rules) | `CLAUDE.md` (project memory, always in context) |
| Hourly / monthly scheduled agent runs | Windows Task Scheduler calling `claude -p` headless (below) |
| `#watch`, "Only me" | Runs locally under your account; no shared channel to lock down |

## Files in this folder

```
claude-code/
  .claude/
    agents/sentry.md      the agent (system prompt + tool allow-list)
    settings.json         permission lockdown — the enforcement layer
  .mcp.json               the one tool: read-only filesystem MCP
  CLAUDE.md               operating rules, always in context
  scripts/                the nine collectors (unchanged from Buzz)
  DEPLOY.md               this file
```

## Prerequisites

- Claude Code installed (`npm i -g @anthropic-ai/claude-code`) and authenticated
- Node.js (for `npx @modelcontextprotocol/server-filesystem`)
- A Windows 10/11 machine you administer
- The Windows-side setup from the original **DEPLOY-SENTRY.md steps 1–4** already done: the `sentry-svc` account, the audit-logging registry changes, `C:\ProgramData\Sentry` with restrictive permissions, and the two scheduled tasks that run `Invoke-SentryCollection.ps1` (hourly) and `Invoke-SentryMonthly.ps1` (monthly). Those steps are harness-independent — run them exactly as written.

## Install

1. Copy this whole `claude-code/` folder to wherever you want Sentry to live, e.g. `C:\Sentry\`. Open Claude Code there (`cd C:\Sentry` then `claude`).
2. On first launch Claude Code will detect `.mcp.json` and ask you to approve the `sentry-fs` server. Approve it.
3. Verify the lockdown: `/permissions` should show `Bash`, `Write`, and `Edit` in the deny list. If it doesn't, the settings file isn't being read — check it's at `.claude/settings.json` in the project root.
4. Verify the tool: `/mcp` should list `sentry-fs` with read tools only.

## The critical configuration

Everything in the persona about *"never construct your own PowerShell"* is an **instruction**. The deny list in `.claude/settings.json` is the **enforcement**. Both matter, but if you change nothing else, keep `Bash` denied.

A security-monitoring agent that can run arbitrary shell commands on the machine it monitors is the one configuration mistake that genuinely matters — it's the direct equivalent of leaving Goose's developer extension on in the original deployment. Do not add `Bash` to the allow list "just to test something."

## Running it

**Interactively** — from the project folder:

```
claude
> use the sentry subagent: what did you see in the last hour?
> use the sentry subagent: give me this month's hardening report
```

**Hourly, headless** — register a Windows scheduled task that runs Claude Code in print mode and appends to a log (or pipe to your notifier of choice):

```powershell
$claude = "$env:APPDATA\npm\claude.cmd"   # adjust to your install
$action = New-ScheduledTaskAction -Execute $claude `
  -Argument '-p "use the sentry subagent: do your hourly pass" --permission-mode default' `
  -WorkingDirectory 'C:\Sentry'
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) `
  -RepetitionInterval (New-TimeSpan -Hours 1)
Register-ScheduledTask -TaskName 'Sentry-CC-Hourly' -Action $action -Trigger $trigger `
  -Description 'Sentry hourly review via Claude Code (read-only)'
```

Run the headless task under **your** interactive user (it needs your Claude Code auth), and keep it separate from the `sentry-svc` account that does collection. The collector task and the review task should never share an identity — that separation is what keeps the evidence trail out of the agent's reach.

For the monthly report, register a second task with the monthly prompt on a first-Monday trigger.

## Test that detection works

From an ordinary prompt, run the harmless encoded command from the original guide (`powershell -nop -w hidden -enc VwByAGkAdABlAC0ATwB1AHQAcAB1AHQAIAAiAHQAZQBzAHQAIgA=`). On the next hourly pass Sentry should flag `encoded-command` and `hidden-or-noprofile`. If it doesn't, script-block logging isn't on — go back to the Windows-side setup.

## Notes and limits

- **Model.** The subagent pins `opus`. Log analysis is where a weak model produces confident nonsense; don't economise here.
- **`--dangerously-skip-permissions` defeats the entire model.** Never use it with this agent.
- Claude Code is a good fit for this port: subagents give a clean system-prompt boundary, and `settings.json` deny rules give real enforcement of the "no shell" invariant rather than relying on the prompt alone.
