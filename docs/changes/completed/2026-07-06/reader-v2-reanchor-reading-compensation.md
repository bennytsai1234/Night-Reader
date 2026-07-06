# Reader V2 reanchor reading compensation

## Context

`docs/analysis/analysis_results.md` points to a visible jump during decelerating scroll: strip world coordinates can move while `readingY` stays unchanged. The relevant paths are:

- Background layout growth calls `_handleChapterCacheUpdated` and `_reanchorGrownChapter`.
- Window shifts call `ensureWindowAround` and `placeWindowInStrip`, replaying chapter coordinates with live extents.

## Plan

1. Add a viewport-side compensation helper that records the currently visible anchor chapter top before a strip re-placement, then shifts `readingY` by the same top delta after placement.
2. Let background content updates report the changed chapter and its top delta so the viewport can compensate when the current visual anchor is that chapter.
3. Rebase motion state through `ScrollReaderV2MotionController` so `scrollOffset` and active fling state stay consistent after compensation.
4. Run focused Reader V2 viewport tests and `flutter analyze`.

## Verification

- `flutter test test/features/reader_v2/reader_v2_viewport_window_stress_test.dart` — passed
- `flutter analyze` — passed
