# Sentry on Microsoft 365 Copilot

This is Sentry ported to a **Microsoft 365 Copilot declarative agent**. Read this section first, because the architecture is genuinely different from every other port.

## The honest architecture caveat

A declarative agent is **cloud-hosted SaaS**. It runs inside Microsoft 365, not on your machine. It therefore **cannot read `C:\ProgramData\Sentry` directly** and cannot run PowerShell locally — which, for a "reads-only, never-acts" agent, is a feature, not a bug: the SaaS boundary enforces the "no shell" invariant for free.

But it means the evidence has to travel to somewhere Microsoft's cloud can read. There are two supported paths, and this port ships the first as the recommended default:

1. **SharePoint (recommended).** The endpoint syncs the collector output to a SharePoint document library; the agent reads it through the built-in `OneDriveAndSharePoint` capability. Simple, no server to run, and it doubles as the "get evidence off the machine" step the original DEPLOY already recommended — if the machine is compromised, the off-box copy is what you trust.
2. **Remote MCP (advanced).** Self-host the read-only filesystem MCP behind an HTTPS endpoint with OAuth, and register it as an MCP action. `mcp-action.json` is the template. Only do this if you specifically need live reads rather than synced copies; it reintroduces a server you must secure.

Whichever you choose, Sentry stays read-only. The declarative agent cannot write, and neither the SharePoint capability nor the read-only MCP functions expose a way to change the machine.

## What maps to what

| Buzz concept | M365 Copilot equivalent |
|---|---|
| `sentry.persona.md` (system prompt) | `instructions.txt`, referenced by `declarativeAgent.json` (8,000-char cap — the persona is condensed to fit) |
| "one MCP: filesystem, scoped" | `OneDriveAndSharePoint` capability scoped to one library **or** `mcp-action.json` (read-only functions) |
| "no shell" | enforced by the SaaS boundary — a declarative agent has no code execution |
| hourly/monthly wrappers | Windows scheduled tasks still run the collectors; a sync step uploads output to SharePoint |
| `#watch`, "Only me" | agent shared only to you (or a security group) at publish time |

## Files in this folder

```
copilot/
  manifest.json           Teams/M365 app package manifest (wraps the agent)
  declarativeAgent.json   the agent definition (name, instructions, capabilities, actions)
  instructions.txt        the condensed persona (<8,000 chars)
  mcp-action.json         optional remote-MCP action template (advanced path)
  scripts/                the nine collectors (unchanged from Buzz)
  color.png / outline.png  app icons — ADD THESE (192x192 color, 32x32 outline)
  DEPLOY.md               this file
```

## Prerequisites

- A Microsoft 365 tenant with Copilot licensing and declarative-agent (agent) support enabled
- Rights to sideload/upload a custom agent, or an admin to publish it
- The Microsoft 365 Agents Toolkit in VS Code (easiest) **or** the Teams Developer Portal
- The Windows-side setup from the original **DEPLOY-SENTRY.md steps 1–4** already done (the `sentry-svc` account, audit logging, `C:\ProgramData\Sentry` with restrictive permissions, and the collection + monthly scheduled tasks)

## Setup

### 1. Get evidence into SharePoint

Create a document library, e.g. `https://CONTOSO.sharepoint.com/sites/Sentry/Shared Documents/SentryEvidence`, and give **read** access to whoever will use Sentry. Then add a nightly (or hourly) sync from the endpoint. Simplest is to point the existing archive step at a OneDrive/SharePoint-synced folder:

```powershell
Compress-Archive -Path "$env:ProgramData\Sentry\collections\*" `
  -DestinationPath "$env:OneDrive\SentryEvidence\collections\$(Get-Date -f yyyyMMdd-HHmm).zip"
```

Prefer syncing the JSON files uncompressed if you want the agent to read individual collectors rather than archives — the agent reads files, not zips. The account that writes to SharePoint should not be able to delete from it (append-only), for the same reason the local folder is write-but-not-delete.

### 2. Point the agent at your library

In `declarativeAgent.json`, replace the placeholder URL in the `OneDriveAndSharePoint` capability with your library URL. If you are not using the remote-MCP path, delete the `actions` block and `mcp-action.json`.

### 3. Fill in the manifest

In `manifest.json` set a fresh GUID for `id`, and real developer/privacy/terms URLs. Add `color.png` (192×192) and `outline.png` (32×32, transparent) icons.

### 4. Package and sideload

With the Agents Toolkit: open this folder, **Provision**, then **Preview in Copilot**. Manually: zip `manifest.json`, `declarativeAgent.json`, `instructions.txt`, the two icons (and `mcp-action.json` if used) into an app package and upload it in the Teams admin center or via *Copilot → Agents → Upload custom agent*.

### 5. Restrict who can use it

Publish to yourself or a small security group only — the equivalent of the original's "Only me". A security watch agent should not be broadly discoverable.

## Test it

Open Sentry in Copilot and use the **Hourly pass** conversation starter. It should summarise the log sources it read from SharePoint, or produce a defence package. Then try **Monthly hardening report**. If it says it can't find evidence, the sync in step 1 isn't landing files where the capability URL points.

## What this port can and can't preserve

- **Preserved:** the persona, the defence-package and hardening-report formats, the read-only boundary, the "never acts" rule (enforced structurally by SaaS), working with any AV.
- **Changed:** evidence is read from an off-box copy in SharePoint, not from `C:\ProgramData\Sentry` live. There is inherent sync latency — an hourly sync means the agent is up to an hour behind, which is fine for this workload.
- **Weaker fit than Claude Code / Goose:** the 8,000-character instruction cap forced condensing the persona, and you depend on a sync pipeline. It's the right choice only if you specifically want Sentry inside M365 Copilot alongside your other Copilot agents.
