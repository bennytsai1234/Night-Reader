# Technique: Code Review

A self-contained discipline for two situations: **reviewing** a change (the
adapter's investigate review question) and **receiving** review feedback before
acting on it. Both demand technical evaluation, not performative agreement.

## Reviewing a change

Goal: catch real problems against the surrounding code and the atlas, not
restyle to taste.

1. **Establish the diff.** Know exactly what changed (the commit range or the
   working diff) and what it was supposed to do.
2. **Read against context.** Read the diff against the owning module's doc and
   any boundary modules. A change that looks fine in isolation can break a
   contract one layer out.
3. **Look for the things that actually bite:**
   - Correctness and edge cases the change introduces or forgets.
   - Missing or shallow tests for the new behaviour.
   - Contract drift — a public interface, return shape, or invariant changed
     without updating callers.
   - Hidden coupling or shared state touched without the other writers in mind.
   - Irreversible or risky steps with no rollback.
4. **Rank findings by severity** so the reader knows what blocks:
   - **Critical** — must fix before proceeding (breaks behaviour, data loss,
     security).
   - **Important** — should fix before merge.
   - **Minor** — note for later; do not block.
5. **Report as findings, not vibes.** Each finding names the location, the
   concrete problem, and why it matters. End with a plain verdict: ready, or
   what must change first.

## Receiving review feedback

Feedback is a set of suggestions to evaluate, not orders to follow blindly.

1. **Read all of it before reacting.** Items can be related; partial
   understanding produces a wrong implementation.
2. **Restate each requirement** in your own words; if any item is unclear, stop
   and ask before implementing anything.
3. **Verify against the codebase** before accepting a suggestion:
   - Is it technically correct for *this* stack and these constraints?
   - Would it break existing behaviour?
   - Is there a load-bearing reason the current code is the way it is?
   - YAGNI: if it asks for an unused capability, confirm it is actually needed
     before adding it.
4. **Push back with technical reasoning** when a suggestion is wrong — reference
   the code or tests that prove it, rather than complying for comfort. If you
   cannot verify a claim, say so and ask how to proceed.
5. **Implement in order:** clarify everything first, then blocking issues, then
   simple fixes, then complex ones — testing each individually.

## Voice

Skip performative agreement ("you're absolutely right", "great point",
gratitude). State the fix or the disagreement. Actions and corrected code show
the feedback was heard. If you pushed back and were wrong, say so factually in
one line and move on — no long apology.
