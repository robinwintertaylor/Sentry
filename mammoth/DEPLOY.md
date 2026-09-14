# Sentry on Mammoth

This is Sentry ported to **Mammoth** (2389 Research's DOT-based pipeline runner). Mammoth reads a `.dot` graph and walks it node by node, dispatching each stage to an LLM coding agent, with checkpoints, retries, and human-in-the-loop gates.

**Read the security note below before deploying — Mammoth is the loosest-fitting harness of the set, and it needs an extra guardrail the others don't.**

## The security tension, and how this port resolves it

Mammoth's `box` (codergen) nodes run an agent that, by default, has **file write and shell** tools. Sentry's entire design is that the agent is read-only and never runs a command. Those two facts are in direct conflict, so this port does three specific things:

1. **Run the pipeline under the low-privilege, read-only `sentry-svc` account.** This is the load-bearing control. Even if the agent tried to change a setting or run a privileged command, the OS refuses — `sentry-svc` is not an administrator, has read-only access outside `C:\ProgramData\Sentry`, and can't stop the collection task. This plays the same role that "turn off Goose's developer extension" plays in the original deployment: it makes the read-only rule an enforced fact, not just an instruction.
2. **Keep collection out of the pipeline.** The read-only collectors are still run by a *separate* Windows scheduled task (from the original DEPLOY steps). The pipeline only *reads* their output. The `octagon` check nodes here run one deterministic, fixed shell line — an existence check on the evidence folder, no LLM involved — and nothing else.
3. **A human gate (`house` node) before anything is filed or sent.** This is the `APPROVE <id>` step. Approving a defence package means you accept the proposal to run *manually yourself*; Sentry still never executes it.

If you cannot run the pipeline under a restricted account, do not deploy Sentry on Mammoth — use the Claude Code or Goose port, where the "no shell" boundary is enforced by the harness itself.

## What maps to what

| Buzz concept | Mammoth equivalent |
|---|---|
| `sentry.persona.md` (system prompt) | `sentry-instructions.md`, read by each `box` node's prompt |
| hourly / monthly wrappers | `sentry-hourly.dot` / `sentry-monthly.dot` |
| "read the evidence, don't collect it" | `octagon` existence check → `box` analysis (read-only) |
| "APPROVE \<id\>" human step | `house` gate node before the exit |
| "no shell for the agent" | run under `sentry-svc` (OS-enforced) — see above |

## Files in this folder

```
mammoth/
  sentry-hourly.dot        the hourly watch pipeline
  sentry-monthly.dot       the monthly hardening report pipeline
  sentry-instructions.md   the full persona, read by the analysis nodes
  reports/                 created on first run; where reports are written
  scripts/                 the nine collectors (unchanged from Buzz)
  DEPLOY.md                this file
```

## Prerequisites

- Mammoth installed (`go install github.com/2389-research/mammoth/cmd/mammoth@latest`, Go 1.25+), or a release binary
- An LLM API key with real reasoning ability — `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, or `GEMINI_API_KEY`. Log analysis is where a weak model produces confident nonsense; don't economise. Pin a strong model per node with a `model=` attribute if you like.
- The Windows-side setup from the original **DEPLOY-SENTRY.md steps 1–4** (the `sentry-svc` account, audit logging, `C:\ProgramData\Sentry` with restrictive permissions, and the collection + monthly scheduled tasks)
- Graphviz (optional, only for rendering the graph to SVG/PNG)

## Setup

1. Copy this folder to the machine, e.g. `C:\Sentry\mammoth\`, and create the `reports\` folder.
2. Confirm the graphs are valid: `mammoth --lint sentry-hourly.dot` (Mammoth validates against its 21 lint rules before running).
3. Do a supervised first run **as `sentry-svc`** so you can watch the human gate:

   ```bash
   mammoth sentry-hourly.dot --tui
   ```

   The `--tui` dashboard shows the live DAG. You'll see the octagon check, then the analysis node, then the `review` gate pausing for your approve/reject.

## Running it on a schedule

Register a Windows scheduled task **running as `sentry-svc`** (not your admin account, not the collector's identity if you can avoid sharing) that invokes Mammoth hourly. Because the `review` node is a human gate, for unattended hourly runs rely on its `default="approve"` with the timeout — the report is still written and filed; a human reviews the filed reports rather than each run live. For the monthly report, a first-Monday trigger with the longer gate timeout.

```powershell
$action = New-ScheduledTaskAction -Execute 'mammoth' `
  -Argument 'C:\Sentry\mammoth\sentry-hourly.dot' `
  -WorkingDirectory 'C:\Sentry\mammoth'
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) `
  -RepetitionInterval (New-TimeSpan -Hours 1)
Register-ScheduledTask -TaskName 'Sentry-Mammoth-Hourly' -Action $action -Trigger $trigger `
  -User 'sentry-svc'
```

Mammoth checkpoints every successful node, so an interrupted run resumes where it left off; use `--fresh` to force a clean start.

## Test that detection works

Run the harmless encoded command from the original guide (`powershell -nop -w hidden -enc VwByAGkAdABlAC0ATwB1AHQAcAB1AHQAIAAiAHQAZQBzAHQAIgA=`). On the next hourly run Sentry should flag `encoded-command` and `hidden-or-noprofile` in its report. If it doesn't, script-block logging isn't on — return to the Windows-side setup.

## Honest assessment

Mammoth is built for multi-stage *coding* pipelines where a shell-capable agent is the point. Sentry is the opposite — a read-only watcher. The port works, and the `octagon`/`house` node types actually map nicely onto "deterministic check" and "human approval," but the read-only guarantee here rests on the OS account, not the harness. If you want the harness to enforce it, prefer Claude Code (`Bash` denied in settings) or Goose (recipe pins a filesystem-only extension).
