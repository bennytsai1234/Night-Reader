# Technique: Debugging

A self-contained discipline for finding the **root cause** of a bug before
changing anything. The atlas adapter's change and investigate paths pull this in
on demand.

**Iron law: no fix without root-cause evidence first.** A fix that only removes
the nearest symptom is a failure — it leaves the real cause to resurface.

## Scale to the tier

- **T1 (clear bug):** if you can reproduce the bug and the root cause is obvious
  and confirmed, you may go straight to the fix and a regression test. Do not
  invent ceremony.
- **T2 (hard bug — intermittent, async, stateful, cache, lifecycle, perf, or a
  diagnosis you are not sure of):** run the full loop below. This is where
  guessing wastes the most time.

The output of this technique is the **diagnosis** that goes into the Before
statement, so the user can judge whether you understood the problem.

## 1. Build a feedback loop (the heart of it)

Everything else just consumes a fast, deterministic, repeatable pass/fail signal
for the bug. Without one, staring at code will not save you. Spend
disproportionate effort here; be aggressive and creative.

Construct one, roughly in this order of preference:

1. A **failing test** at whatever seam reaches the bug (unit / integration / e2e).
2. A **script** that drives the running system (HTTP request, CLI invocation
   against a fixture, headless-browser script asserting on the symptom).
3. **Replay a captured artifact** — save a real request / payload / event log and
   replay it through the code path in isolation.
4. A **throwaway harness** — a minimal subset of the system that exercises the
   bug path with a single call.
5. A **differential or bisection loop** — same input through old vs new
   (version, config, commit) and diff the outputs.

Treat the loop as a product: make it faster, sharper (assert on the exact
symptom, not "didn't crash"), and more deterministic (pin time, seed randomness,
isolate filesystem/network).

For **non-deterministic** bugs the goal is a higher reproduction rate, not a
clean repro: loop the trigger, parallelise, add stress, narrow timing windows
until it fails often enough to debug against.

If you genuinely cannot build a loop, **stop and say so** — list what you tried
and ask the user for access, a captured artifact, or permission to instrument.
Do not hypothesise without a loop.

## 2. Reproduce

Run the loop and watch the bug appear. Confirm it reproduces the failure mode
the **user** described — not a different nearby failure. Capture the exact
symptom so later steps can prove the fix addresses it.

## 3. Hypothesise

Generate **3–5 ranked, falsifiable hypotheses** before testing any of them. A
single hypothesis anchors you on the first plausible idea.

Each must state a prediction: *"If X is the cause, then changing Y makes the bug
disappear / changing Z makes it worse."* If you cannot state the prediction, it
is a vibe — sharpen or discard it.

For stateful/async bugs, explicitly list every writer/restorer of the affected
state and every async boundary (awaits, callbacks, timers, listeners, retries,
cache invalidation, restore paths). Identify which stale operation can overwrite
or restore the wrong state.

## 4. Instrument

Test one prediction at a time, changing **one variable**. Prefer a debugger or
REPL breakpoint over logs; if logging, log only at the boundaries that
distinguish hypotheses and tag every probe with a unique prefix (e.g.
`[DEBUG-a4f2]`) so cleanup is one search. Never "log everything and grep".

For performance regressions, logs are usually wrong — establish a baseline
measurement (timing, profiler, query plan), then bisect. Measure first.

## 5. Fix + regression test

Write the regression test **before** the fix — but only if a **correct seam**
exists, i.e. one that exercises the real bug pattern as it occurs at the call
site. If the only available seam is too shallow to replicate the chain that
triggered the bug, a test there gives false confidence: **note the absence of a
correct seam as a finding** rather than writing a misleading test.

If a correct seam exists: turn the repro into a failing test, watch it fail,
apply the minimal fix, watch it pass, then re-run the Phase 1 loop against the
original scenario.

## 6. Close out

- Confirm the original repro no longer reproduces (re-run the loop).
- Remove all tagged instrumentation and throwaway harnesses.
- State the confirmed root cause plainly — it becomes the **Before** diagnosis,
  and it tells the next person what actually happened.
- If preventing this bug would need an architectural change (no good seam,
  tangled callers, hidden coupling), say so **after** the fix is in — you know
  more now than when you started.
