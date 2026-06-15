# Technique: Test-Driven Development

A self-contained discipline for writing the test first, watching it fail, then
writing the minimal code to pass. The atlas adapter's change path pulls this in
when a task adds or fixes behaviour and a cheap test seam exists.

**Iron law: no production code without a failing test first.** If you write the
code first, you never see the test fail, so you never learn whether it tests the
right thing. A test that passes the moment you write it proves nothing.

## Scale to the tier

- **T0 (trivial, no behaviour-logic change):** skip TDD. A one-line Before/After
  plus the single most relevant check is enough.
- **T1 (contained behaviour change, cheap seam exists):** add one focused test
  for the happy path, plus one for the most important failure path.
- **T2 (hard/risky behaviour change):** drive the whole change test-first.
- **No correct seam at any tier:** if testing the real behaviour would require a
  disproportionate harness, say so honestly as a finding instead of writing a
  shallow test that gives false confidence.

## Red → Green → Refactor

### RED — write one failing test

Write **one** minimal test that asserts **one** observable behaviour through the
**public interface**, named so it reads like a specification ("retries a failed
operation three times"). Use real code paths; avoid mocks unless unavoidable —
mocking internal collaborators tests the shape of the code, not its behaviour.

### Verify RED — watch it fail

Run the test. Confirm it **fails** (not errors), and fails for the expected
reason (the behaviour is missing), not a typo. A test that passes here is
testing existing behaviour — fix the test.

### GREEN — minimal code

Write the simplest code that makes the test pass. No speculative options, no
extra features, no "while I'm here" refactoring. Just enough to go green.

### Verify GREEN — watch it pass

Run the test. Confirm it passes, the rest of the suite still passes, and the
output is clean (no new errors or warnings). If the test fails, fix the code,
not the test.

### REFACTOR — clean up while green

Only after green: remove duplication, improve names, move complexity behind
small interfaces. Keep the tests green; add no new behaviour. Never refactor
while red.

## Work in vertical slices

Do **one** test → its implementation → the next test. Do **not** write all the
tests first and then all the implementation ("horizontal slicing") — bulk tests
describe imagined behaviour and end up testing data shapes rather than what the
system does. Each cycle should respond to what you learned from the last.

## Fixing a bug with TDD

Write a failing test that reproduces the bug, watch it fail, fix, watch it pass.
The test proves the fix and prevents the regression. Never fix a bug without a
test capturing it — unless no correct seam exists, which is itself a finding.

## When a test is hard to write

A hard-to-test unit is usually a design signal, not a testing problem: a
too-large interface, too much coupling, or unclear responsibility. Simplify the
interface or inject dependencies rather than contorting the test.
