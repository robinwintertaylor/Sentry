# Sentry on Mistral Vibe

This is Sentry ported to **Mistral Vibe** (`mistral-vibe`), Mistral's terminal-native coding agent. Vibe reads an `AGENTS.md` for standing context and keeps its configuration in `~/.vibe/config.toml`, with per-tool permissions (`ALWAYS` / `ASK` / `NEVER`) — which is exactly the lever Sentry needs to stay read-only.

## What maps to what

| Buzz concept | Vibe equivalent |
|---|---|
| `sentry.persona.md` (system prompt) | `AGENTS.md` (read from the working directory) |
| "one MCP: filesystem, scoped" | `[mcp_servers.sentry-fs]` in `config.toml` (stdio transport) |
| "Turn off the shell / developer extension" | `[tools.permissions]` → `shell`, `bash`, `execute`, `write_file`, `edit_file` = `NEVER` |
| model, temperature 0.2 | `[model]` in `config.toml` |
| hourly / monthly wrappers | Windows scheduled tasks calling `vibe` non-interactively |

## Files in this folder

```
mistral-vibe/
  AGENTS.md       the persona / operating rules (standing context)
  config.toml     model, the one MCP tool, and the permission lockdown
  scripts/        the nine collectors (unchanged from Buzz)
  DEPLOY.md       this file
```

## Prerequisites

- Mistral Vibe installed (`uv tool install mistral-vibe` or per the project README) and authenticated with a provider
- Node.js (for `npx @modelcontextprotocol/server-filesystem`)
- The Windows-side setup from the original **DEPLOY-SENTRY.md steps 1–4** (the `sentry-svc` account, audit logging, `C:\ProgramData\Sentry` with restrictive permissions, and the collection + monthly scheduled tasks)

## Setup

1. Copy this folder to the machine, e.g. `C:\Sentry\mistral-vibe\`.
2. Put the config where Vibe will read it. Either copy `config.toml` to `~/.vibe/config.toml`, **or** set `VIBE_HOME` to this folder so Vibe reads `config.toml` from here. The second option keeps everything self-contained.
3. Open Vibe from this folder so it picks up `AGENTS.md` as context:

   ```bash
   cd C:\Sentry\mistral-vibe
   vibe
   ```

4. Confirm the lockdown. Vibe should show the `sentry-fs` MCP server connected with read tools, and shell/write tools blocked. If a `config.toml` key was rejected on load, generate a reference config once (run `vibe` through the first-run wizard) and align key names to your Vibe version — keep the intent: filesystem read allowed, shell and write `NEVER`.

## The one configuration that matters

The `NEVER` entries in `[tools.permissions]` are the enforcement behind the persona's "never construct your own PowerShell." Vibe ships shell and file-edit tools that are the whole point of a coding agent — for Sentry they're exactly wrong. Do not switch to an auto-approve/YOLO agent profile, and do not relax `shell = "NEVER"` "just to test something." A security-monitoring agent that can run arbitrary commands on the machine it monitors is the single deployment mistake that genuinely matters.

## Running it

**Interactively:**

```bash
cd C:\Sentry\mistral-vibe
vibe
> Do your hourly pass: read the newest folder under C:\ProgramData\Sentry\collections, check manifest.json, and report.
> Write this month's hardening report from the latest monthly posture file.
```

**On a schedule.** Register a Windows scheduled task, running as **your** interactive user (needs your Vibe auth — keep it separate from the `sentry-svc` collector identity), that runs Vibe non-interactively every hour:

```powershell
$action = New-ScheduledTaskAction -Execute 'vibe' `
  -Argument '--prompt "Do your hourly pass and report."' `
  -WorkingDirectory 'C:\Sentry\mistral-vibe'
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) `
  -RepetitionInterval (New-TimeSpan -Hours 1)
Register-ScheduledTask -TaskName 'Sentry-Vibe-Hourly' -Action $action -Trigger $trigger
```

Set `VIBE_HOME` in the task's environment if you're not using `~/.vibe/config.toml`. Add a first-Monday task for the monthly report. Check Vibe's current flags (`vibe --help`) for the exact non-interactive/prompt flag in your version.

## Test that detection works

Run the harmless encoded command from the original guide (`powershell -nop -w hidden -enc VwByAGkAdABlAC0ATwB1AHQAcAB1AHQAIAAiAHQAZQBzAHQAIgA=`). On the next hourly run Sentry should flag `encoded-command` and `hidden-or-noprofile`. If it doesn't, script-block logging isn't on — return to the Windows-side setup.

## Notes

- Vibe is a reasonable fit: `AGENTS.md` gives a clean persona surface and `[tools.permissions]` gives real, per-tool enforcement of the read-only boundary. Its exact config schema moves faster than the others, so verify keys against your installed version.
