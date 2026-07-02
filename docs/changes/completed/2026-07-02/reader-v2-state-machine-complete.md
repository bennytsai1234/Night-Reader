# Reader V2 state machine completion

## Before

The first state-machine pass centralized high-risk operation phase changes, but some session mutations still bypass the state-machine boundary:

- viewport progress/capture updates mutate visible/committed location directly
- navigation page movement and neighbor refresh mutate page windows directly
- restore progress is tracked by a raw runtime flag

## After

Finish the state-machine boundary by moving remaining session mutations behind semantic methods:

- visible location updates
- committed progress updates
- ready page-window updates
- restore-in-progress tracking
- notice-only notifications

The change keeps existing behavior and does not rewrite viewport lifecycle logic.

## Validation

- `flutter analyze`
- `flutter test test/features/reader_v2`

