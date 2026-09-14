# Sentry on Goose

This is Sentry ported to plain **Goose** (Block's open-source agent), run from recipes rather than as a Buzz-managed agent. Buzz already used the Goose *runtime*, so this is the closest port to the original — the difference is that here you drive Goose directly with recipe files and schedule them yourself, instead of Buzz doing it for you.

## What maps to what

| Buzz concept | Goose equivalent |
|---|---|
| `sentry.persona.md` (system prompt) | `instructions:` block in each recipe |
| "one MCP: filesystem, scoped to `C:\ProgramData\Sentry`" | `extensions:` → single `stdio` filesystem server |
| "Turn OFF Goose's developer extension" | recipe pins extensions, so `developer` never loads — plus disable it globally (below) |
| hourly / monthly wrappers | `sentry-hourly.recipe.yaml` / `sentry-monthly.recipe.yaml` |
| Buzz agent settings (model, temp 0.2, "only me") | recipe `settings:` + your local `~/.config/goose/config.yaml` |

## Files in this folder

```
goose/
  sentry-hourly.recipe.yaml    the hourly watch
  sentry-monthly.recipe.yaml   the monthly hardening report
  scripts/                     the nine collectors (unchanged from Buzz)
  DEPLOY.md                    this file
```

## Prerequisites

- Goose CLI installed and configured with a provider/model (`goose configure`)
- Node.js (for `npx @modelcontextprotocol/server-filesystem`)
- The Windows-side setup from the original **DEPLOY-SENTRY.md steps 1–4** already done (the `sentry-svc` account, audit logging, `C:\ProgramData\Sentry` with restrictive permissions, and the collection + monthly scheduled tasks). Those steps are harness-independent.

## The one configuration that matters

Goose ships with the **developer** extension enabled by default, and it includes a general shell. For this agent that default is wrong: an agent that watches for malicious PowerShell while able to run PowerShell is a contradiction, and a continuously-running process with a security remit is an attractive target.

Two layers protect you, use both:

1. **The recipe pins extensions.** Because each recipe lists only `sentry-fs`, running via `--recipe` loads only that. The model never sees a shell tool.
2. **Disable `developer` globally** so an accidental plain `goose session` (no recipe) can't reach a shell either. Run `goose configure` → *Toggle Extensions* → turn **developer** off, or remove it from `~/.config/goose/config.yaml`:

   ```yaml
   extensions:
     developer:
       enabled: false
   ```

If you skip this you have a security-monitoring agent that can run arbitrary commands on the machine it monitors. That is the single deployment mistake that genuinely matters.

## Model choice

Set a model with real reasoning ability (the original used `moonshotai/kimi-k3` via OpenRouter, temperature 0.2). Log analysis is exactly where a weak model produces confident nonsense. Configure it in `~/.config/goose/config.yaml`; the recipes set temperature 0.2.

## Running it

**Once, to check it works:**

```bash
goose run --recipe sentry-hourly.recipe.yaml
```

You should get a short summary naming the log sources it read, or a defence package. Then run the monthly once so you've seen it:

```bash
goose run --recipe sentry-monthly.recipe.yaml
```

**On a schedule.** Goose recipes can be scheduled with cron, or you can drive them from the OS scheduler. On Windows, register a Task Scheduler job that runs the hourly recipe every hour under your interactive user (not `sentry-svc` — the collector account and the review agent must stay separate identities):

```powershell
$action = New-ScheduledTaskAction -Execute 'goose' `
  -Argument 'run --recipe C:\Sentry\goose\sentry-hourly.recipe.yaml' `
  -WorkingDirectory 'C:\Sentry\goose'
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) `
  -RepetitionInterval (New-TimeSpan -Hours 1)
Register-ScheduledTask -TaskName 'Sentry-Goose-Hourly' -Action $action -Trigger $trigger
```

Add a second first-Monday task for the monthly recipe.

## Test that detection works

Run the harmless encoded command from the original guide (`powershell -nop -w hidden -enc VwByAGkAdABlAC0ATwB1AHQAcAB1AHQAIAAiAHQAZQBzAHQAIgA=`). On the next hourly run Sentry should flag `encoded-command` and `hidden-or-noprofile`. If it doesn't, script-block logging isn't on — return to the Windows-side setup.

## Notes

- `available_tools` in each recipe filters the filesystem server down to read-only calls even though the server itself can write. Keep that list read-only.
- Goose is a strong fit for this port — recipes were built precisely to pin extensions and remove the "the agent decides which tools to load" problem, which is exactly the guarantee Sentry needs.
