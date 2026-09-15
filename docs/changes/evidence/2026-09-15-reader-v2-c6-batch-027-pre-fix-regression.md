# C6 batch-027 pre-fix regression evidence

角色：C6 worker / atlas/v4  
分類：`production-bottleneck`（待 post-fix regression；不是 environment invalid、不是 visual/semantic violation）  
固定裝置：`emulator-5556`，Android 17 / 120Hz，debug correctness workload  
測量邊界：C6 的 `_settleTimeout = 20s` 與既有 `_settle()` assertions 未修改

## 結論

同一個 `veryLongChapter` mixed journey case 在原始 run 與一次 bounded replay
都在 operation-1 `navigation_jump_current-settling` 觸發同一個 fail-closed
settle failure。兩次 run 的 app heartbeat 都持續，`pumpQueueDepth` 從高點持續
下降，約 25 秒後才觀察到 `ready` 且 queue 為 0；沒有 ADB daemon、activity、
process crash、ANR、OOM 或 `FATAL EXCEPTION` 證據。這不是 random flake，也不是
可以藉由放寬 timeout 變成綠燈的合法 idle。

目前證據支持的 root-cause hypothesis 是：Android hybrid reader 在已經位於
long chapter 章首的情況下再次執行 `navigation_jump_current`，
`HybridReaderScreen._restoreCore` 會把整個 current chapter 的 layout groups
投入 `LayoutPump`。anchor 最終可 ready，但大量非可見 prefetch 留在 queue，令
真實 frame scheduling 持續承受數百毫秒 frame work，超過 C6 既有 20 秒 bounded
settle。下一步是以 production 最小變更限制 restore 初期的投放，先完成
anchor/viewport 所需的實際 window；不改 timeout、case 清單、invariant 或
aggregate 判定。

## Exact case and commands

Case id（兩次完全相同）：

```text
C-mixed_journey-navigation_jump_current__drag_pause_then_release__fling_forward_medium__ballistic_interrupt_early__navigation_backward_n__natural_forward_slow_cross__navigation_jump_last__drag_forward_short__navigation_jump_first-veryLongChapter-journey-5-8-restore_ownership_acquired-9132052
```

Original batch-027 was part of the bounded continuation:

```text
pwsh -NoProfile -File tool/run_reader_correctness_android_subset.ps1 -DeviceId emulator-5556 -Seed 9132052 -MaxCasesPerBatch 20 -MaxEstimatedOperationsPerBatch 36 -ReportRoot artifacts/android-reader/c6-subset-seed-9132052-final-r18-max36-complete -StartBatchIndex 21 -ResumeFromReportRoot artifacts/android-reader/c6-subset-seed-9132052-final-r18-max36-retry-b020 -AllowCompatiblePrefixResume
```

The one-case-scope replay was bounded to batch-027 only and retained the original
failed prefix:

```text
pwsh -NoProfile -File tool/run_reader_correctness_android_subset.ps1 -DeviceId emulator-5556 -Seed 9132052 -MaxCasesPerBatch 20 -MaxEstimatedOperationsPerBatch 36 -ReportRoot artifacts/android-reader/c6-subset-seed-9132052-final-r18-max36-retry-b027 -StartBatchIndex 27 -StopAfterBatchIndex 28 -ResumeFromReportRoot artifacts/android-reader/c6-subset-seed-9132052-final-r18-max36-complete -AllowCompatiblePrefixResume
```

No command in this evidence used a 7200-second or unbounded timeout. Both commands
used the existing per-batch 300-second workload cap.

## Pre-fix batch results

| run | cases | completed | exit observed | actual duration | workload duration | result |
|---|---:|---:|---|---:|---:|---|
| `final-r18-max36-complete/batch-027` | 4 | 3 | `exitCode=1` | 226.5210091s | 95.7456685s | `failed_or_invalid` |
| `final-r18-max36-retry-b027/batch-027` | 4 | 3 | `exitCode=1` | 235.0234484s | 95.4317093s | `failed_or_invalid` |

Both metadata files have `caseSummaryCount=4` only because the bounded outer
fallback records the expected case list; `caseSummaryComplete=false` and
`allCaseSummariesPassed=false`, so neither batch is counted as pass. The first
three cases in the batch completed; the exact long-chapter case above failed.

## Failure and environment classification

The failure is the same in both `batch-result.json` files:

```text
C6 在 operation-1-navigation_jump_current-settling 後沒有進入 settled：null
```

The operation trace has the before anchor at the long chapter start. The app-owned
failed-case metadata reports `phase=ready` before the operation, a long chapter,
`runtimeFrameCount=0` for the failure operation (the operation did not reach the
after trace), and no Android crash marker. The failure bundle contains the retained
failure screenshot/video/logcat/evidence and is preserved under both report roots.

The relevant progress observations are:

| run | max observed queue | observed queue drain | heartbeat / frame evidence |
|---|---:|---|---|
| original | 931 | `931, 857, 800, ... 27, 4` | heartbeat continued; `frames` grew to at least 626; worst frame `811244us`; layout task count grew to about 4963 |
| replay | 874 | `874, 800, 711, ... 41, 9` | heartbeat continued; `frames` grew to at least 580; worst frame `756579us`; layout task count grew to about 5133 |

The post-detection snapshots eventually show `ready`, `queue=0`, contiguous visible
keys and no missing paragraph keys, but they occur after the 20-second settle
predicate has already failed. They prove eventual drain, not that the case was
settled within the existing bound.

ADB readiness was independently present before replay (`emulator-5556 get-state`
was `device`, boot completed, the debug app had focus and a live PID). The logcats
contain no actual `FATAL EXCEPTION`, ANR, SIG, or OOM record. Therefore this is not
an environment invalid attempt and must not be silently excluded as one.

## Source-level attribution before fix

The current path is:

```text
navigation_jump_current
  -> ReaderV2Runtime._jumpHybridToChapter
  -> viewport restore
  -> HybridReaderScreen._restoreCore
  -> _ensureWindowTasks(anchorKey)
  -> _enqueueChapterTasks(current long chapter)
  -> LayoutPump queue contains non-visible groups
```

`_restoreCore` needs only the anchor plus the bounded guaranteed viewport window
before it can publish `_initialRestoreCompleted=true`. The existing
`_enqueueChapterTasks` path scans and submits every missing group on the current
chapter (and can also submit neighboring loaded chapters), while
`_pumpUntilAnchorReady` checks readiness but does not cancel already submitted
non-visible work. The observed queue counts match this behavior. A healthy but
over-admitted background task queue is still production scheduling work here: it
causes real frame starvation and is not an oracle-only artifact.

No timeout, settle assertion, case selection, or invariant rule was changed to
produce this record. The post-fix plan is one minimal bounded restore scheduling
change, a focused regression test, then one new batch-027 replay. Existing failed
artifacts remain excluded from any aggregate.

## Remaining pre-fix trigger: pending-owned ScrollEnd can reopen full lead

The first bounded restore patch also left a second, independently reachable
production path. The source-level chain is:

```text
ReaderV2Runtime._jumpHybridToChapter
  -> pendingChapterJumpTarget = location
  -> _positionHybridViewport awaits viewportBridge.restore
  -> HybridReaderScreen._restoreCore completes bounded anchor/window restore
  -> _applyScrollOffset(target) may dispatch ScrollStart/Update/End
  -> a delayed ScrollEnd callback can run after restoreLocked is released
  -> pendingChapterJumpTarget is still non-null until _jumpHybridToChapter.finally
  -> _handleScrollSettled currently treats it as an ordinary settle
  -> _restorePrefetchBarrierActive = false
  -> unbounded _ensureWindowTasks()
```

`_jumpHybridToChapter` deliberately keeps `pendingChapterJumpTarget` set across
the whole awaited restore and clears it only in its `finally`.  Therefore the
condition `!restoreLocked && initialRestoreCompleted && pendingChapterJumpTarget
!= null` is a real intermediate state, not an invented test state.  A
ScrollEnd inherited from the previous ballistic/drag stream can enter
`_settleUserScrollAndFlushEnsures` in that interval.  The existing
`_handleScrollSettled` did not inspect the pending ownership, so it could turn
the bounded restore barrier off before the explicit jump had finished.

This explains why the previous queue evidence must not be attributed only to the
initial `_restoreCore` enqueue: the original and replay artifacts show a healthy
app whose long-chapter queue drains from 931/874 while the settle contract waits;
the source chain above identifies the later full-window re-enqueue as the
remaining trigger to close.  This section is pre-fix evidence for that trigger;
the fix must keep the barrier bounded while pending ownership is present and
allow full lead only after an ordinary user-owned settle.  No timeout or
`_settle()` assertion is changed.

## Acceptance status for this evidence

| question | status | evidence |
|---|---|---|
| Same case fails twice under bounded run | observed | original and `retry-b027` batch metadata/logcat |
| Environment/ADB/process failure | not observed | readiness snapshot and failure logcat |
| Visual or semantic oracle violation | not observed | four violation counters are zero, but summaries are incomplete; this is not a pass |
| Real queue/scheduling bottleneck | observed | app progress markers, queue drain, heartbeat and frame timing |
| C6 acceptance for seed 9132052 | not verified | batch-027 incomplete; no aggregate pass claim |

## Post-fix bounded verification: case did not start

The pending-owned `ScrollEnd` guard and its focused regression test are present
in the source tree.  The first post-fix Android attempt was not a valid replay
of the long-chapter case: it failed during initial workload setup with one
`READER_C6_PROGRESS` marker (`phase=error`) and no case marker.  The preserved
root is:

```text
artifacts/android-reader/c6-single-case-seed-9132052-postfix-pending-settle-b027-20260915-0302
```

The log contains `Reader hybrid viewport restore done op=1 restored=false
current=true phase=ReaderV2Phase.loading`, followed by `Hybrid viewport restore
failed`, the C6 six-dimension watchdog error, and the Flutter test binding
assertion caused by the unhandled test error.  It never reached the planned
`veryLongChapter` case operation.  The root metadata records
`effectiveTimeoutSeconds=300`, `workloadDurationSeconds=130.8374739`,
`c6ProgressMarkers=1`, and `c6FailureMarkers=0`; it is therefore preserved as
`runner/app-startup invalid`, excluded from any case aggregate, and cannot be
used either to pass or to reject the production patch.

After confirming `emulator-5556` was `device`, boot-complete, focused on
`com.inkpage.reader.debug/MainActivity`, and had a live app PID, the same
`CaseId` was retried exactly once with the current source.  The retry used a
fresh root:

```text
artifacts/android-reader/c6-single-case-seed-9132052-postfix-pending-settle-b027-retry-20260915-0302
```

The bounded command was:

```powershell
pwsh -NoProfile -File tool/run_android_reader_workload.ps1 -DeviceId emulator-5556 -Scenario correctness-subset -BuildMode debug -Seed 9132052 -CaseId "C-mixed_journey-navigation_jump_current__drag_pause_then_release__fling_forward_medium__ballistic_interrupt_early__navigation_backward_n__natural_forward_slow_cross__navigation_jump_last__drag_forward_short__navigation_jump_first-veryLongChapter-journey-5-8-restore_ownership_acquired-9132052" -ManifestHostPath "docs/changes/evidence/2026-09-14-reader-v2-c5-manifest-seed-9132052.json" -ReportDir "artifacts/android-reader/c6-single-case-seed-9132052-postfix-pending-settle-b027-retry-20260915-0302" -TimeoutSeconds 300 -SampleIntervalSeconds 30
```

This build reported `effectiveBuildNumber=4112`, so the replay used the
post-fix source.  It again stopped before the case started: the root metadata
has `effectiveTimeoutSeconds=300`, `workloadDurationSeconds=133.0561065`,
`actualDurationSeconds=301.7468372` (the wrapper duration includes bounded
setup/recovery), `c6ProgressMarkers=1`, `c6FailureMarkers=0`, and no case
result marker.  `evidence-drain.json` records `markerCaseCount=0`,
`completeCaseCount=0`, `status=incomplete`, and the expected case as missing;
the finite drain made 33 polls over 20 seconds and did not fabricate a pass.
The log repeats the initial `Hybrid viewport restore failed`/six-dimension
watchdog path and contains no target-case `CASE_RESULT` or `C6_RESULT`.

The two post-fix attempts are thus the same class of invalid startup/workload
runner failure, not a second occurrence of the original 20-second
long-chapter settle failure.  No Android case-level post-fix result exists yet.
No additional Android retry or batch was started after this one bounded retry.

## Post-fix local evidence and current classification

The following local checks passed after the source change:

```text
flutter analyze lib/features/reader_v2/hybrid/hybrid_reader_screen.dart test/features/reader_v2/hybrid/hybrid_reader_screen_test.dart
flutter test test/features/reader_v2/hybrid/hybrid_reader_screen_test.dart --plain-name "pending jump-owned settle 不會解除 restore prefetch barrier"
flutter test test/features/reader_v2/hybrid/hybrid_reader_screen_test.dart --plain-name "long chapter restore drains only the bounded viewport batches"
```

The focused test and the existing bounded long-chapter test passed, and the
analyzer reported no issues.  These are source/unit-level proofs only: they do
not replace the missing Android case replay.  The current production status is
therefore `patch applied; Android post-fix case not verified`, not `fixed`
and not `regressed`.

| post-fix question | status | evidence |
|---|---|---|
| Current source contains pending-owned settle guard | observed | `lib/features/reader_v2/hybrid/hybrid_reader_screen.dart`, focused test |
| Android replay used fixed serial and post-fix build | observed | both roots; retry metadata `avdDeviceId=emulator-5556`, `effectiveBuildNumber=4112` |
| Original long-chapter settle behavior after patch | not verified | both attempts stopped in initial workload setup; no target-case result |
| New Android visual/semantic violation | not observed, but not a pass | no case result; generated fallback bundle is incomplete |
| Seed 9132052 C6 aggregate | not verified | batch-027 remains incomplete; no batch-028 started |
