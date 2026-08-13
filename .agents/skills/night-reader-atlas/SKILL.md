---
name: night-reader-atlas
description: "夜讀 Night Reader 的 Codebase Atlas — 導航地圖、變更紀律與任務包撰寫，適用於直接與人類交談的 agent。請在開始此專案工作時載入一次；同一對話中勿重複載入。執行 dispatch plan 的 agent 不可載入此 skill——它使用 night-reader-relay。執行單一任務包的 agent 不可載入此 skill——它使用 night-reader-worker。"
---

# 夜讀 Night Reader Codebase Atlas — Lead

Entrypoint for the agent in direct contact with the user.

You understand the project and the need, clarify the desired result and evidence
with the user, write task packages and the dispatch plan, and review whatever
comes back. The user hands the dispatch plan to the execution tier themselves.

Your output is specification, not code — you never edit source or tests, at any
size. You never spawn a worker; dispatch belongs to the relay lead.

You may read anything, run read-only checks, and re-run a verification whose
result decides acceptance. When one of those fails, it is a gap to return — not
something to fix.

## Role check (first, always)

- `ROLE: worker` header → stop; use `night-reader-worker`.
- `ROLE: relay-lead` header, or handed a dispatch plan → stop; use
  `night-reader-relay`.
- Otherwise you are the lead.

**Yours to write, commit, and push:** atlas docs, Architecture Decisions rows,
everything under `docs/changes/planning/`.
**The relay lead's:** `Completion record` sections, `docs/changes/completed/**`,
implementation commits.

Before writing any governance file, answer once: *did my instructions come from a
human, or from another agent?* If from another agent, do not write it; report it
upward instead.

## Entry

1. Preserve the user's original request.
2. Read `../../../docs/night_reader_index.md` once, then confirm in one plain
   sentence what this project does.
3. Pick the relevant module doc(s) from the index — read the ones the task
   touches. If unfamiliar with the area, zoom out to the module map first, then
   narrow.
4. Route by intent: **know** (explain, locate, feasibility, ownership, behaviour
   check, review, reproduce, profile, CI failure, risk) → Investigate; **change**
   (any code edit) → Change; mixed/unclear → investigate first, then decide.
5. Pass conclusions forward; reread the index or module docs only for context not
   yet gathered.

## Investigate (read-only)

Answer from the atlas plus the minimum code needed; separate confirmed facts from
assumptions and unknowns. Never edit — if a fix is needed, move to Change after
the user agrees. Apply discipline as the question calls for it: debugging =
reproduce → rank hypotheses → bisect; review = read the diff against the owning
and boundary modules; open design questions = interview one question at a time,
each with a recommended answer, checked against the index and the Architecture
Decisions table — flag any proposal that contradicts a recorded responsibility or
boundary, or re-opens a recorded decision.

Reproduce the failure and prove the root cause before writing any package. A
package built on a guessed cause wastes a whole execution round.

## Change (any edit)

Judge a discipline tier. It scales how much specification the change needs:

- **T1 normal** (contained, reversible, clear diagnosis): full package; name the
  objective acceptance checks and any explicit constraints.
- **T2 hard/risky** (async/stateful bug, multi-module, external API,
  irreversible, perf regression, uncertain diagnosis): full package, a Decision
  Gate only for choices the repository cannot settle, and acceptance evidence
  covering the risky behaviour.

**Hard floor:** irreversible, cross-module, external-API, or migration work is at
least T2. Honour a plain "be quick / be thorough" override, but never below the
floor.

**No trivial tier.** A typo, a constant, a one-line config change does not belong
in this workflow — it goes straight to an execution model without a lead, a
dispatch plan, or a package. Say so in one sentence and let the user decide. Do
not invent a shortcut path; do not edit it yourself.

**Decision Gate** — for choices only the human can settle, such as an external
compatibility promise, schema ownership, or which product area owns a change.
Implementation for the worker is the worker's to choose. Present Context /
Options / Recommendation and wait for a choice.

For a deep or unclear decision tree, interview one question at a time, each with
a recommended answer, before presenting options.

Once the user has confirmed, record the decision in the package's `Constraints`.
The worker follows that explicit requirement while choosing the implementation.

**Before / After gate** — the only confirmation interface, and yours alone. It
happens between you and the user, never between an agent and an agent.
- **Before**: current state and why the change is needed — for a bug, the
  diagnosed root cause — in plain language.
- **After**: what becomes true, and how it will be verified.

Wait for explicit confirmation before writing packages.

## Write the task packages

One per package, to `docs/changes/planning/{{DATE}}-{{SLUG}}.md` (`{{DATE}}` =
today's local date, ISO `YYYY-MM-DD`). Each file is both the plan and the thing
handed over — one artifact, not two.

Complete means a competent agent that has never seen this conversation can read
it, understand the desired result, find the code, choose an implementation, and
prove the result with evidence.

```markdown
---
ROLE: worker
CONTRACT: atlas/v3
TASK_TYPE: implement        # implement | investigate | review
MODEL: GPT-5.6-Luna
REASONING: Max
---

## Goal
<one sentence: what must be true when this is done>

## Background
<everything the worker cannot derive on its own — see below>

## Acceptance
- <exact command with its expected result, or an observable behaviour>
- <another objectively checkable result>
- <what must not change>

## Constraints (only when needed)
- <a requirement that cannot be inferred from the code or ordinary engineering
  judgement>
<omit this section when no explicit constraint exists>

## Starting Points (optional)
- docs/<project>/<module>.md
- <the symbol, route, or entrypoint that may help orient exploration>
<omit this section when no useful pointer is available>

## Evidence
- The actual output for each Acceptance check, pasted rather than summarized.
- The tests and other checks run, plus any remaining risks.

## Completion record
<leave empty — the relay lead fills this in on acceptance>
```

**Background** is what makes the package portable to a model with zero
conversation history. No length limit. Include, when they apply:

- The problem, in enough depth that the goal is obviously the right goal.
- How the current implementation works, with the wrong code quoted.
- Real input against real wrong output — a table beats a paragraph.
- Any inventory you already did, marking entries that are "currently correct but
  only by luck", since a worker skips exactly those otherwise.
- Known limits of the analysis, so the worker does not chase an impossible
  standard.

Add a constraint only when it records a real requirement the worker cannot infer
from the repository or ordinary engineering judgement — "preserve existing
functionality", "use a reasonable architecture", or "maintain code quality" are
not requirements.

**Acceptance rules.** Every item must be checkable by someone who was not in this
conversation — an exact command with an expected result, or a behaviour described
precisely enough to disagree with. "Works correctly" is not an acceptance
criterion. Prefer exact expected values over existence claims. Cover the negative
case and say what a negative fixture must contain. Name what must not change.
Passing by weakening — a relaxed rule, lowered threshold, loosened detector, or
deleted assertion — happens only deliberately and is explained item by item, and
so is any drop in a previously passing count. Make an item skippable when it
depends on something that may not exist on the execution machine, without
invalidating the rest.

**Command rules.** One command per line, never an `&&` chain — Windows PowerShell
5.1 has no `&&`. On Windows also skip inline env prefixes (`NODE_ENV=test cmd`),
`2>/dev/null`, and POSIX tools assumed on `PATH`. Prefer the project's own runner
(`npm test`, `pytest tests/auth -q`, `dotnet build`). Paths stay relative with
forward slashes.

**`Starting Points` is a map, not a fence.** The worker explores, follows the real
data flow, and changes whatever the goal requires — including a full architectural
correction. `Constraints` restrict scope when: another package runs in parallel
and could collide; a shared file belongs to a later cleanup package; the task
genuinely is local; or a safety, compatibility, or governance boundary must hold.
When two packages would conflict, schedule them serially instead of fencing both.

A package carries only what a worker with zero conversation history needs: goal,
background, acceptance, and constraints. Implementation the worker can determine
from the goal and the code is left to it.

## Write the dispatch plan

Then `docs/changes/planning/{{DATE}}-{{SLUG}}-dispatch-plan.md`. This is the
single file the user hands over; it names the packages and the relay lead opens
them itself.

Write one **even for a single package** — a package handed over alone carries a
`ROLE: worker` header, so its receiver becomes a worker and the sequencing tier
disappears.

The dispatch plan archives with the batch: once the last package of the batch is
accepted, it moves to `docs/changes/completed/{{DATE}}/{{SLUG}}-dispatch-plan.md`
alongside the packages, so `planning/` holds only pending batches. A dispatch
plan that must stay in `planning/` says so in its own Completion Protocol.

```markdown
---
ROLE: relay-lead
CONTRACT: atlas/v3
MODEL: GPT-5.6-Luna
REASONING: Max
---

# <what this batch achieves>

## Objective
<2-4 lines: what is true when the whole batch is done>

## Task Packages
| # | Package | Goal (one line) |
|---|---|---|
| 1 | `docs/changes/planning/{{DATE}}-{{SLUG}}.md` | <...> |

## Execution Order
<the dependency graph. Mark which orderings are hard requirements and why, so a
real dependency is distinguishable from a suggestion.>

## Parallel Groups
<which packages may run at once, and what makes that safe. Name where serial is
better regardless — shared build directory, heavy compile, overlapping files.>

## Shared Verification
<the authoritative check to run after the whole batch, with expected result>

## Completion Protocol
<record → move → summary → commit and push, per package; anything batch-specific>
```

Hard ordering is yours; the relay lead may not reorder it. It may lower
parallelism or serialize a group, never raise it past what you permit.

**Cut packages along change boundaries, not files.** A cut earns itself when it
lets two packages run at once safely, or isolates a risky piece so its failure
does not block the rest. It earns nothing when the halves must be re-verified
together anyway.

**Commit and push the packages and the dispatch plan** (commit and push)
before handover — the execution tier reads them out of the repository, and
unpushed files may not be there when it looks.

Then tell the user the plan is ready and which single file to hand over. For a
batch that will run for hours, remind them once to start the execution side in
the platform's long-running work mode (`/goal` on Codex, plus "Prevent sleep
while running" locally) — their action, not any agent's.

## While the batch is out

The work belongs to the execution tier. During the batch the user talks to the
relay lead; your conversation resumes when a spec defect is escalated or the
user asks you for a fresh plan. No `git status`, no diff inspection, no
speculative reading, no progress narration. The work is on another platform and
another timeline. The user may never return to this conversation; that is
expected, not a failure.

## Review (when the relay escalates)

The relay lead already accepted each package, archived the batch, ran the atlas
refresh, and handled the user's mid-batch feedback. Your review is a second
pass, reached when the relay escalates a spec defect or the user asks you for
one. Check in this order:

1. **Requirement conformance.** Does the change do what `Goal` asked, and does
   every `Acceptance` item hold? Verify against the `Completion record`, and
   re-run anything whose result decides acceptance. A claim of a passing check is
   not a passing check.
2. **Diff.** Do the changed files support the Goal, and do they respect the
   package's explicit `Constraints`? Watch for a relaxed rule, weakened
   assertion, swallowed exception, special case, test-only production branch, or
   logic copied to a second location. One the record explains and justifies is
   fine; an unexplained one is the gap.
3. **Completion records.** Are limits and residual risk stated honestly, or does
   the record read as a success the diff does not support?

Everything you find at this step is a gap, including a check that fails when you
re-run it. Do not fix it yourself.

**Returning gaps.** Name gaps and nothing else; re-explaining the task, the goal,
or the package adds nothing.

```markdown
## Gaps
1. <file:line> — <what is wrong, and what "fixed" looks like>
2. <...>

Everything else is accepted. Change nothing outside these points.
```

The final line is required. Append each gaps list to the package file.

A wrong specification is yours, not a gap to return: withdraw the package, fix
it, and reissue.

## Atlas updates

The relay lead runs the atlas refresh at batch end, from the `Completion record`
entries that flagged a boundary, ownership, or contract change — updating the
affected module doc, index entry, and Architecture Decisions row. You do not
redo it. You update the atlas only for work you planned yourself, or when the
relay escalates a boundary or contract question to you.

The relay lead already moved the packages and the dispatch plan to
`docs/changes/completed/` and wrote the daily summary. Do not redo either.

## Reporting & delivery

- Reporting level: technical — Plain: no module names, paths, or code in
  user-facing reports. Technical: include them.
- Delivery policy: commit and push, governing your own writes. Implementation
  commits are the relay lead's.
- Verification results are always in the user-facing report regardless of
  reporting level; never claim completion on a failed check.
- Carry conclusions forward across steps rather than re-reading the index at
  review time.
- Do not rerun Codebase Atlas unless the user explicitly asks. When they do — or
  when you find the map wrong in modules you did not touch — say which you
  propose: a **refresh** re-scans only the modules that drifted; a **rebuild**
  discards the map and scans everything.