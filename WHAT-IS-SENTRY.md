# What is Sentry?

Sentry is a security agent that watches one Windows machine and tells you, in plain English, when something looks wrong.

It is not antivirus. It does not replace the security software you already run, and it never competes with it. Think of it as a careful colleague who reads your machine's logs every hour — logs you would never read yourself — and taps you on the shoulder when something deserves a look.

---

## The one-sentence version

**Sentry reads. You decide. You act.**

Everything else in this document follows from that.

---

## What it actually does

**Every hour**, a scheduled task collects six kinds of evidence from Windows: what processes started and with what command lines, what PowerShell ran, what changed in the machine's autostart configuration, what network connections exist, and the health of whatever antivirus you have installed. Sentry reads those files and looks for patterns that suggest something is wrong.

Most hours, nothing is. You get a one-line all-clear, or nothing at all.

**When something looks wrong**, Sentry writes what it calls a defence package:

- What happened, in language that assumes no security background
- Why it is a concern — what an attacker would actually achieve
- The raw evidence, with timestamps and event IDs so you can verify independently
- How confident it is, and what would change that confidence
- Numbered steps to respond, with the exact commands ready to paste
- What happens if you do nothing

Then it stops and waits for you.

**Once a month**, it produces a different kind of report: not "something is wrong" but "here is what could be tightened." Ranked by benefit against disruption, with a rollback for every suggestion.

---

## What it deliberately cannot do

Sentry has no shell. It cannot run arbitrary commands. It has six read-only scripts and nothing else, and it is explicitly forbidden from constructing its own PowerShell.

That constraint is not caution for its own sake — it follows from what the agent is for. An agent whose job is to detect malicious PowerShell, while itself able to execute PowerShell, is a contradiction. It would also be an extremely attractive target: a process with a security remit, running continuously, trusted by its owner.

It also cannot:

- Quarantine, delete, or kill anything
- Change firewall rules, registry keys, or system settings
- Disable, weaken, or add exclusions to your antivirus
- Clear or modify any log
- See anything on the machine outside its own data folder

**The failure modes are asymmetric.** A missed detection costs you one incident. An agent that quarantines the wrong process can take your machine down, destroy work, or be manipulated into doing so — and log data is, by definition, partly written by whoever you are worried about. An agent that acts automatically on attacker-influenced input is a weapon pointing the wrong way.

---

## How it stays honest

**The collection is out of its reach.** A scheduled task runs the collectors under a separate low-privilege account. Sentry reads the output; it cannot stop the collection, change what is gathered, or alter what was written. If Sentry were compromised, the evidence trail would continue regardless.

**It cannot delete history.** The output folder's permissions let the collection account create files but not remove them. Evidence you cannot trust is worse than no evidence.

**It admits its own limits.** If a collector fails, that gap appears in the report — because silence from a broken script looks exactly like silence from a clean machine. And if Sentry ever suspects the machine is genuinely compromised, it is instructed to say plainly that its own findings may be unreliable, since an attacker with administrator rights can shape everything it reads.

That last point is why the setup guide recommends copying evidence off the machine.

---

## Working with your antivirus

Sentry reads the Windows Security Center, which is where every antivirus product on Windows registers itself. Norton, Bitdefender, ESET, Sophos, CrowdStrike, Malwarebytes, Defender — all of them report product name, real-time protection status, and signature freshness through the same interface.

So Sentry knows what you are running and whether it is healthy, without caring which vendor it is. If Defender happens to be your active product, it reads a little more: threat detections and, importantly, the exclusion list, since quietly adding an exclusion is a common early move by an attacker.

The two do different jobs. Your antivirus asks "is this specific file malicious?" Sentry asks "does this sequence of ordinary-looking events add up to something?" — a signed binary launched by Word, which then made an outbound connection, after which a new scheduled task appeared. Nothing there triggers a signature. The pattern is the signal.

---

## What it looks like in practice

A quiet hour:

> **Sentry** — Nothing of note. 47 process creations, all signed and expected. No new persistence. AV healthy, signatures 4 hours old.

Something worth knowing about:

> **Sentry** — `[MEDIUM] SENTRY-2026-0804-03`
>
> **What happened:** A PowerShell command ran with its window hidden and its instructions encoded in base64, started by Outlook at 14:22. The decoded command downloaded and ran a file from a web address.
>
> **Why this is a concern:** Legitimate software does not usually hide its window or disguise its instructions. Starting from a mail client is the classic shape of someone opening an attachment they should not have.
>
> **How confident I am:** Medium. This pattern is also produced by some corporate software deployment tools, and the destination is a Microsoft address, which argues for innocent. I would want to know whether you opened an attachment around 14:22.

Note what it did not do: it did not kill the process, and it did not pretend to be certain.

---

## Is this right for you?

**Good fit if** you own the machine, you would like to know when something odd happens, and you are willing to read a short report occasionally and act on it yourself.

**Not a fit if** you want automated protection with no involvement — that is what your antivirus is for, and it is better at it. Sentry adds context and explanation on top; it does not replace the thing that blocks files.

**Worth knowing:** it needs about twenty minutes of setup, including turning on Windows logging that is off by default. Without that logging most of the detection is guesswork, so the setup is not optional decoration.

---

## Next

`DEPLOY-SENTRY.md` walks through installation end to end — the account, the logging, the scheduled tasks, the Buzz agent, and where to store evidence off the machine.
