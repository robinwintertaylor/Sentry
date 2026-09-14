# Porting Sentry to other harnesses

Sentry was built for **Buzz** (running on the Goose runtime). This repo now also carries ports to five other agent harnesses, one folder each:

| Folder | Harness | What it is |
|---|---|---|
| `claude-code/` | **Claude Code** | Anthropic's CLI / Agent SDK — subagent + MCP + permission deny-list |
| `goose/` | **Goose** | Block's open-source agent — pinned-extension recipes |
| `copilot/` | **Microsoft 365 Copilot** | cloud declarative agent reading evidence from SharePoint |
| `mammoth/` | **Mammoth** | 2389 Research's DOT-based pipeline runner |
| `mistral-vibe/` | **Mistral Vibe** | Mistral's terminal coding agent — `AGENTS.md` + `config.toml` permissions |

Each folder is self-contained: the harness-native config, a copy of the persona in that harness's format, the nine collector scripts, and its own `DEPLOY.md`.

## The one thing every port must preserve

Sentry's entire design is a single boundary:

> **Sentry reads. You decide. You act.**

Concretely, the agent must be **read-only** and must **never run or construct a command**. Collection is done by a *separate* Windows scheduled task under a low-privilege account (`sentry-svc`) that the agent cannot influence; the agent only reads the JSON that task writes to `C:\ProgramData\Sentry`. An agent whose job is to detect malicious PowerShell, while itself able to run PowerShell, is a contradiction and an attractive target.

So porting Sentry is **not** mostly about the persona (that text is nearly identical everywhere). It is about reproducing the *enforcement* — the "no shell" guarantee — in each harness's own machinery. That is where the ports genuinely differ.

## What stays identical across all ports

- **The nine collector scripts** (`scripts/`). These are OS-level PowerShell run by Windows Task Scheduler, not by any agent. Harness-independent — deploy them exactly as the original `DEPLOY-SENTRY.md` steps 1–4 describe.
- **The Windows-side setup**: the `sentry-svc` account, process-command-line auditing, script-block logging, the grown Security log, the write-but-not-delete permissions on `C:\ProgramData\Sentry`, and the hourly + monthly collection tasks.
- **The persona**: detection-only behaviour, the defence-package format, the monthly hardening-report format, severity levels, and the rules.

## How the "no shell" guarantee is enforced in each port

| Harness | Enforcement mechanism | Strength |
|---|---|---|
| Claude Code | `.claude/settings.json` denies `Bash`/`Write`/`Edit`; subagent `tools:` lists only read tools | **Strong** — harness-enforced |
| Goose | recipe pins a single filesystem extension with `available_tools` read-only; `developer` extension disabled | **Strong** — harness-enforced |
| Mistral Vibe | `[tools.permissions]` sets `shell`/`write`/`edit` = `NEVER` | **Strong** — harness-enforced |
| M365 Copilot | SaaS: the agent has no code execution at all; reads evidence synced to SharePoint | **Strong** — structural, but adds sync latency and an 8k-char instruction cap |
| Mammoth | codergen agent *has* shell/write by default; contained by running under the low-privilege `sentry-svc` account + a human gate | **Weakest** — relies on the OS account, not the harness |

## Fit assessment

- **Best fit: Claude Code and Goose.** Both let you pin the exact tool surface and deny a shell at the config layer, which is precisely Sentry's requirement. Goose is also the closest to the original, since Buzz already used the Goose runtime.
- **Good fit with a caveat: Mistral Vibe.** Per-tool `NEVER` permissions give real enforcement; its config schema just moves quickly, so verify keys against your installed version.
- **Different but sound: M365 Copilot.** The SaaS boundary enforces read-only for free, but evidence must travel to SharePoint (or a remote MCP), and the persona is condensed to fit the 8,000-character instruction limit. Choose it only if you want Sentry inside M365 alongside your other Copilot agents.
- **Works, but requires an extra guardrail: Mammoth.** Built for shell-capable coding pipelines — the opposite of a read-only watcher. The port keeps it safe by running under `sentry-svc` (OS-enforced read-only) and gating output behind a human node. If you can't run it under a restricted account, use a different port.

## Common deployment shape

Whichever harness, the deployment is the same three parts:

1. **Windows-side (once):** original `DEPLOY-SENTRY.md` steps 1–4 — account, logging, permissions, collection tasks.
2. **Harness config:** drop in that folder's files; confirm the read-only lockdown is active.
3. **Scheduling:** a Task Scheduler job runs the agent hourly (and monthly), under an identity **separate** from `sentry-svc` so the collector's evidence trail stays out of the agent's reach.

Then test detection with the harmless encoded-command probe from the original guide before trusting any quiet report.

## Not yet ported

The request mentioned "etc." — these five are done. Other harnesses (e.g. Aider, Cline, OpenCode, Gemini CLI, Codex) follow the same recipe: put the persona in the harness's instruction file, add a read-only filesystem MCP, and deny shell/write at the config layer. Ask if you'd like any of them added.
