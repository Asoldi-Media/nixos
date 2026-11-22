---
name: model-routing
description: How to pick the model, effort level and provider (Claude Haiku, Sonnet or Opus, or Grok through Cursor) for a piece of work, to stretch the shared Claude limit. Load before delegating to sub-agents, writing a workflow (also under ultracode), handing code to Grok, or choosing an effort level.
---
# Model routing

One Claude subscription is shared by every machine: the Windows laptop, nix32-main and nix32. Send each piece of work to the cheapest tier that does it well, and move up one tier when that tier fails. The full system description is the doc "Asoldi development system: machines, models and routing" on claude.ai (private to the owner).

## Tiers

| Tier | Work | Model | Effort | Use |
| --- | --- | --- | --- | --- |
| mechanical | Lookups and summaries with one right answer: list or count files, grep sweeps, excerpts, boil down a log or test output | Haiku 5.5 | low | `scout` agent, or `TIER.mechanical` |
| wait | Run a long job and report: test suites, builds, Docker, Grok runs | Haiku 5.5 | low | `runner` agent, or `TIER.mechanical` |
| search | Find and explain code across files | Sonnet 5.5 | medium | `Explore` agent, or `TIER.search` |
| work | Medium work with a clear spec: tests, small fixes, docs, subsystem analysis, drafting Grok task files | Sonnet 5.5 | high | `general-purpose` with `model: "sonnet"`, or `TIER.work` |
| code | Writing code from a task file | Grok 4.7 via Cursor | high | `runner` starts `grok.mjs` on nix32-main |
| judge | Plans, task breakdown, architecture, triage, hard debugging | Opus 5.5 | high | the manager session itself, or `TIER.judge` |
| review | Code review (Grok output included), security review, push and publish gates, final verification | Opus 5.5 | xhigh | `reviewer` agent, or `TIER.review` |

## Hard rules
- Judgment never goes below Sonnet: reviews, deciding whether code is correct, security calls, data-handling decisions, plans.
- Haiku never writes production code, reviews, or decides. If a Haiku result needs judgment, hand it up.
- Reviews and push or publish gates run on Opus at `xhigh`. Opus's default effort is `high`.
- Code-writing goes to Grok on nix32-main through `runner`. Claude reviews Grok's output, and writes hidden tests, before any merge. Edits under about 20 lines are done in place, since the handoff costs more than the edit.
- Escalate one step at a time: Haiku, then Sonnet, then Opus; low, then medium, high, `xhigh`. A Grok track that fails review twice moves to Claude: Sonnet at high, or Opus when the cause is unclear.
- Fast mode stays off. On the plan it bills paid usage credits.

## Delegating with the Agent tool
- `scout`: mechanical lookups (Haiku, low).
- `runner`: long jobs and Grok runs; it waits and reports (Haiku, low).
- `Explore`: code search (Sonnet, medium). It overrides the built-in Explore, which ran on Opus.
- `reviewer`: reviews and gates (Opus, `xhigh`).
- Medium work: `general-purpose` with `model: "sonnet"`.
- When an Agent call has an effort field and the agent has no effort of its own, set the effort from the tier table. This skill is the instruction that asks for it.

## Workflows, also under ultracode
Ultracode does not override this: the owner wants the plan's limit to last. Every `agent()` call names a tier. A stage with no tier inherits the session model (Opus), which is the expensive default.

```js
const TIER = {
  mechanical: { model: 'haiku',  effort: 'low' },
  search:     { model: 'sonnet', effort: 'medium' },
  work:       { model: 'sonnet', effort: 'high' },
  judge:      { model: 'opus',   effort: 'high' },
  review:     { model: 'opus',   effort: 'xhigh' },
}
// agent(prompt, { ...TIER.mechanical, label: 'scan:routes', phase: 'Scan', schema: LIST })
```

- Finders and sweepers: `mechanical` or `search`. Fixers: `work`, or Grok through a `mechanical` stage that runs `grok.mjs` and returns `result`.
- Verifiers: `work` (Sonnet). Only the final gate, or a finding the verifiers disagree on, gets `judge` or `review`.
- Size: stay within the session's workflow size guideline. Use 3 verifier votes, not 5, unless it is a publish gate.
- Long waits inside a stage are fine, because sub-agents keep a 1-hour cache. Let a Haiku stage do the waiting, not an Opus one.

## Cache and context hygiene
- Pick the model when a session starts. `/model` mid-session re-reads the whole history uncached. Changing `/effort` mid-session is free on Opus 5.5, Sonnet 5.5 and Haiku 5.5 on the plan.
- Don't give a skill or command a `model:` different from the session's: that is two cache misses.
- Keep tool output short with `tail`, `grep -c` and line ranges, and let `scout` or `runner` digest long logs.
- Manager sessions keep their live state in the status file (`~/.asoldi-waves-backup/WAVES-STATUS-*.md` or the wave notes), so compaction loses nothing. Opus auto-compacts at 400k tokens. At a natural stage boundary, a fresh session that reads the status file beats dragging a 400k context along.
- Don't poll with short loops or wake-ups. Wait on notifications, or let `runner` wait.

## Settings this relies on (user settings on all three machines)
- `"subagentPromptCacheTtl": "1h"`
- `"modelSettings": { "claude-opus-5-5": { "effortLevel": "high", "autoCompactWindow": 400000 } }`
- Agents in `~/.claude/agents/`: `scout`, `runner`, `Explore`, `reviewer`.

## Measuring
- `/usage`, then `w`, shows the 7-day breakdown by sub-agent and skill.
- `node ~/.claude/usage-tools/usage-scan.mjs <since-date>` prints token totals by model, day and session from local logs. `cache-miss-scan.mjs` shows why the cache was rewritten, and `context-scan.mjs` shows manager context sizes. All three print numbers only, never conversation content.
