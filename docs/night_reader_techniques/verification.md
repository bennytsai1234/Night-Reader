# Technique: Verification Before Completion

A self-contained discipline for proving work is done before claiming it is. The
atlas adapter's change path pulls this in after edits, before reporting
completion.

**Iron law: no completion claim without fresh verification evidence.** If you
have not run the verifying command in this round of work, you cannot say it
passes. Claiming completion without evidence is dishonesty, not efficiency.

## Scale to the tier

- **T0 (trivial):** run the single most relevant check (the one build, lint, or
  test that the change could plausibly break) and report its result.
- **T1 (normal):** run the type-appropriate subset — the tests covering the
  changed path, plus build/lint as relevant.
- **T2 (hard/risky):** run the full verification the change demands, including
  the red-green check on any regression test and a re-run of the original repro.

## The gate

Before stating any status or expressing satisfaction:

1. **Identify** the command that would prove the claim.
2. **Run** it fresh and in full.
3. **Read** the full output — exit code, failure count, warnings.
4. **Compare** the output against the claim.
5. **Only then** state the claim, *with* the evidence — or state the actual
   status honestly if it does not pass.

Skipping any step turns "verifying" into guessing.

## What each claim actually requires

| Claim | Evidence that proves it | Not sufficient |
|---|---|---|
| Tests pass | Test command output: 0 failures | A previous run; "should pass" |
| Build succeeds | Build command: exit 0 | Linter passed; logs look fine |
| Linter clean | Linter output: 0 errors | A partial check |
| Bug fixed | The original symptom no longer reproduces | Code changed, assumed fixed |
| Regression test works | Failing before the fix, passing after | Passes once after the fix |
| Requirements met | Line-by-line check against the plan | Tests pass, so "done" |

## Red flags — stop and verify

- The words "should", "probably", "seems to".
- Expressing satisfaction ("Done!", "Perfect!") before running anything.
- About to report completion, commit, or hand off without fresh output.
- Trusting a delegated agent's "success" without checking the actual diff.
- "Just this once" / "I'm confident" / "I'm tired." Confidence is not evidence.

## Reporting

The verification result is part of the user-facing report regardless of
reporting level: state plainly whether checks passed, were skipped, or failed.
If verification fails, do not claim completion — fix and re-verify, or report
the failure honestly and ask how to proceed. This result also fills the "how it
was verified" half of the After statement.
