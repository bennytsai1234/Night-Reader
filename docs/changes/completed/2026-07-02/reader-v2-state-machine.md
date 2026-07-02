# Reader V2 state machine

## Before

`ReaderV2Runtime`, `ReaderV2NavigationController`, and `ReaderV2ViewportBridge` can all mutate `ReaderV2State` directly. Async operation freshness is guarded by separate fields such as `jumpRequestId`, `presentationRequestId`, `layoutGeneration`, and `restoreInProgress`.

## After

Introduce an explicit state machine and operation token for the high-risk session flows:

- open book
- jump
- restore
- presentation change
- content reload

The first pass keeps existing phases and behavior, but centralizes phase changes and current-operation checks. Viewport bridge progress saving remains behaviorally unchanged.

## Validation

- `flutter analyze`
- `flutter test test/features/reader_v2`

