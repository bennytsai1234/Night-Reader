# Reader 153 backward-scroll investigation reserve

Status: **OPEN / confirmed logic fixes implemented / performance hypothesis still open / not merged**

Branch: `investigate/reader-153-backward-scroll`  
Base: `main@f4ebd53b3b5818e6f8c3c96f2ab29ad5c76d0608` (v0.2.153 release state)  
Purpose: Preserve the investigation and carry repairs for the confirmed demand-priority, line-break-policy, whitespace, and passive-download-intent defects. The broader planner/readiness performance hypothesis remains intentionally unresolved. Keep this branch unmerged until the user chooses to validate or merge it.

## User-visible symptom observed

One Reader session showed this behavior after jumping chapters:

- After a chapter jump, scrolling upward toward the previous chapter felt briefly blocked / stuck.
- v0.2.152 had felt smooth in the same general usage pattern.
- After switching to another book, the problem disappeared.

The last observation materially weakens the claim that v0.2.153 has a universal scrolling-throughput regression. At this point the real root cause is **not confirmed**.

## Current decision

A candidate repair is now implemented for one **confirmed scheduler ownership defect**:

> Chapter planning priority must follow current demand, not the priority the work had when it was first created.

Before this branch, a chapter could enter visual-line planning as `prefetch` and remain `prefetch` even after the viewport/frontier needed that same in-flight work. The branch now makes the existing work reusable and promotable:

```text
prefetch -> visible -> anchor
```

Promotion is monotonic. It reuses the existing in-flight work and its progress; it does not cancel, restart, or duplicate the chapter plan. The screen-side in-flight materialization object owns both the future and its current highest demand priority, so there is no second priority ledger.

Viewport/frontier requests now use `visible`; explicit restore / location targeting uses `anchor`; speculative loading remains `prefetch`.

This is an architecture-correct fix for the confirmed ownership defect, but it is **not proof** that this defect caused the one observed backward-scroll stall.

Validation added:

- a LayoutPump contract test that starts two prefetch chapter plans;
- promotes the newer one to anchor;
- verifies the same Future/work is reused;
- verifies the next frame continues the promoted work before the older prefetch work.

CI / Flutter execution has not been run in this session because the available environment has no Flutter/Dart runtime, GitHub Actions dispatch is not exposed through the current connector, and the local container has no outbound GitHub DNS. Do not report this branch as runtime-validated yet.

Do not rewrite the line-layout pipeline merely because of this single observation.

The earlier hypothesis that the new v0.2.153 visual-line planner can starve the backward frontier remains technically plausible beyond the repaired demand-priority defect. The whole-chapter readiness / planner-cost portion is still only a hypothesis until the behavior can be reproduced.

When this issue is seen again, resume work on this branch and first determine whether the failure is:

1. session/lifecycle state specific;
2. book/chapter/content specific;
3. chapter-jump / in-flight-demand transition specific; or
4. a general v0.2.153 visual-line planning / frontier-supply problem.

No further planner/readiness architecture change should be made before that distinction is established.

---

## Why v0.2.152 felt good

v0.2.152 got an important part of the Reader architecture right: **content/layout supply was cheap and demand-oriented**.

For normal short paragraphs it had a fast path similar to:

```dart
if (head.isTitle || text.length <= maxBlockChars) {
  // Build the block without preplanning every visual line.
}
```

That meant the Reader generally did not solve visual-line geometry earlier than necessary.

Its effective behavior was close to:

```text
viewport demand
    -> nearby blocks become available
    -> DocumentIndex grows
    -> scroll can continue
```

This aligns well with Hybrid B's streaming nature.

Another advantage was that native Flutter / SkParagraph retained most visual soft-wrap responsibility. Night Reader did not have to reimplement all of Unicode line-breaking policy, word boundaries, whitespace handling, mixed scripts, grapheme behavior, etc.

### The important v0.2.152 invariant worth preserving

The valuable part is **not "restore all 152 code"**.

The valuable invariant is:

> Layout work should become available at the granularity and time required by the viewport, instead of forcing unrelated whole-chapter work to finish first.

---

## Why v0.2.153 changed the line-layout architecture

v0.2.152 also had a real ownership limitation.

SkParagraph still owned the final soft-wrap decision. That meant Night Reader could not fully enforce the product requirement:

> If a Chinese character physically fits on the current line, do not move it merely because native CJK punctuation / kinsoku policy prefers a different break.

The architecture therefore moved toward:

```text
Native paragraph:
- shaping
- glyph geometry
- measurement / painting

Reader:
- final visual-line break policy
```

This is why v0.2.153 introduced a Reader-owned visual-line plan, including:

- `ReaderParagraphLayout`
- `VisualLineLayoutEngine`
- persisted visual-line break offsets
- Reader-owned line-plan enforcement at the drawable boundary

The motivation was legitimate: **line-break policy ownership**.

The problem under investigation is whether the migration accidentally coupled that ownership change to a heavier readiness/scheduling model.

---

## Confirmed v0.2.153 code characteristics

These are code-review findings, not proof of the observed runtime symptom:

1. Normal non-empty paragraphs now go through Reader-owned visual-line planning.
2. Planning performs native shaping plus per-grapheme geometry / boundary work.
3. Chapter publication currently waits for the chapter-level visual-line planning result before `_blocks` / Admission can expose that chapter.
4. In v0.2.153 main, existing chapter work can be born as prefetch work and retain that priority even after it becomes imminent viewport/frontier demand. This branch fixes that ownership defect by promoting the same in-flight work.
5. A pump budget cannot necessarily preempt a large synchronous planning operation in the middle of that operation.

These facts make backward-frontier starvation plausible, but **not proven as the user's observed bug**. The confirmed priority defect is repaired here; the whole-chapter readiness / planner-cost hypothesis remains open.

---

## Confirmed v0.2.153 defects repaired on this branch

### Demand priority ownership

A chapter plan is no longer stuck forever at the priority it had when it was created. The same in-flight chapter work can be promoted monotonically:

```text
prefetch -> visible -> anchor
```

Promotion reuses the same work and progress; it does not cancel, restart, or duplicate the plan.

### Visual line-break policy

Native word boundaries are now treated as facts, not universal line-break authority.

- Latin-style tokens may prefer native word boundaries.
- CJK and other non-Latin scripts remain grapheme-placeable, so a glyph that physically fits is not moved merely because ICU grouped it into a linguistic word.
- Whitespace is a separator and does not become the owner of a new visual line.
- Source text is not trimmed or rewritten to hide the issue; the repair stays in the line-break decision layer.

Contracts were added for the CJK word-grouping case and a real Paragraph-shaped `aaaaa aaaaa` boundary that previously could create an empty visual line.

### Passive download intent

Reader auto-fill now uses a passive `ensureDownloadTask()` operation.

- waiting/downloading tasks remain untouched;
- paused tasks are not resumed or replaced;
- failed tasks are not retried automatically;
- explicit user `addDownloadTask()` keeps its previous authority to replace stopped/completed tasks.

This keeps "content should be available" separate from "the user asked to resume/retry a download".

### Validation status

The production paths and added contracts have been code-reviewed, but Flutter/Dart tests have not been executed in this session because the available environment has no Flutter/Dart runtime, GitHub Actions dispatch is not exposed through the current connector, and the local container has no outbound GitHub DNS. Do not report this branch as runtime-validated yet.

---

## Separate correctness issues that should not be confused with this investigation

There are line-break policy concerns in v0.2.153 that are independent of the intermittent backward-scroll symptom:

### CJK word-boundary rollback

On v0.2.153 main, native Unicode word boundaries are used as a preferred break signal more broadly than is safe for CJK. **Repaired on this branch.** A Chinese linguistic word boundary is not the same thing as the product's desired visual line-break rule.

Product requirement remains:

> For CJK, if the grapheme physically fits, keep it on the current line; do not create an artificial visible gap merely to preserve a word / punctuation grouping policy.

### Whitespace ownership

Whitespace must behave as a separator, not become a visible leading-only line or standalone visual line as a side effect of rollback. **Repaired on this branch.**

They are repaired here at the line-break policy ownership level rather than as one-off text cases.

---

## What must NOT be done when resuming this branch

Do not jump straight to any of the following:

- increase layout budgets;
- increase preload/window radius;
- add `if (scrollingUp)` special cases;
- add `if (isChinese)` as the final architecture;
- rewrite BlockKey / DocumentIndex identity without first proving it is required;
- convert chapter planning to paragraph planning merely because it sounds cleaner;
- revert all of v0.2.153;
- treat a single successful or failed reproduction as proof of a universal performance problem.

The next change must follow an established root cause.

---

## Reproduction decision tree

If the symptom occurs again with book A:

```text
A shows backward-scroll stall
        |
        v
switch to B
        |
        +-- B also stalls -> general/runtime path becomes more likely
        |
        +-- B is normal
              |
              v
          switch back to A
              |
              +-- A is now normal
              |     -> session/lifecycle/cache/in-flight state becomes the main suspect
              |
              +-- A stalls again
                    -> book/chapter/content-specific path becomes the main suspect
```

Record:

- source book and chapter;
- jump origin and target chapter;
- whether the stall occurs only when scrolling upward;
- whether switching books clears it;
- whether switching back restores it;
- whether the same chapter can reproduce after reopening the app.

Only after reproduction should code instrumentation be added, and then only at the smallest ownership boundary needed.

---

## If the planner/frontier hypothesis is eventually proven

The candidate architecture is **not** "go back to 152 wholesale".

Preserve the good v0.2.153 ownership work while recovering the good v0.2.152 supply behavior:

```text
Semantic paragraph
    -> demand arrives
    -> native shaping facts
    -> Reader LineBreakPolicy
    -> bounded local layout plan
    -> immediate admission
    -> DocumentIndex
    -> viewport
```

Potential invariants to validate before implementation:

1. Line-break policy ownership is separate from word-boundary facts. **Implemented on this branch.**
2. Readiness should be no coarser than required by the viewport.
3. Work priority belongs to current demand, not only task birth. **Implemented on this branch.** **Implemented on this branch.**
4. Long planning work must be genuinely resumable at budget boundaries.
5. Native shaping/painting should remain native; Reader should own only product-specific policy.

The remaining unimplemented items are **candidate invariants**, not an approved rewrite plan.

---

## Resume instruction

When the user reports this problem again:

1. Continue on `investigate/reader-153-backward-scroll`.
2. Rebase/merge the then-current `main` only after inspecting what changed in the relevant Reader paths.
3. Reproduce or derive the exact failing state before changing production code.
4. Trace symptom -> first wrong state -> broken invariant -> owner -> root cause.
5. Implement only the architecture change required by the established root cause.
6. Keep this branch open until the user explicitly decides the issue is resolved.
