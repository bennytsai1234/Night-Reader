# Reader centered text frame

## Branch

`fix/reader-centered-text-frame`

Base: latest `main` at `f4ebd53b3b5818e6f8c3c96f2ab29ad5c76d0608` (`v0.2.153+168` release line).

This branch is intentionally not merged. It exists to isolate and review the horizontal text-frame correction before any PR or release decision.

## Problem

Night Reader 153 keeps the configured outer reader padding symmetric, but the visible body text can look asymmetric.

The outer geometry is still:

```text
viewport
  left user padding
  physical content width
  right user padding
```

The regression is inside that physical content width.

In 152, the reader reduced the drawable width to an integer number of measured full-width CJK advances and split the leftover width between the two sides. In 153, commit `5c66a413` correctly moved physical content-width ownership back to the viewport and removed that em-grid mutation. After that change, start-aligned body text consumed the full physical width directly. When the width was not an exact multiple of the shaped full-width advance, the unused remainder stayed on the right.

That made these two facts diverge:

- configured outer padding: symmetric;
- visible full CJK line edges: potentially asymmetric.

English and mixed-language lines may still be ragged on the right because Night Reader intentionally prefers native Unicode word boundaries. That behavior is separate from the CJK frame-centering regression.

## Why this branch does not restore the 152 architecture

The 152 mechanism made typography rewrite `ReaderV2LayoutSpec.contentWidth` and effective horizontal padding. That mixed two responsibilities:

1. viewport geometry: how much physical space the reader has;
2. typography geometry: how text should occupy that physical space.

153's ownership rule is retained:

```text
viewport + user padding
        ↓
physical content width
```

Typography is not allowed to mutate that value.

Instead this branch introduces a separate inner frame:

```text
physical content frame
        ↓
centered text layout frame
        ↓
VisualLineLayoutEngine
        ↓
ReaderParagraphLayout
        ↓
paint / highlight geometry
```

## Invariants

1. `ReaderV2LayoutSpec.contentWidth` remains the full physical drawable width after user padding.
2. `ReaderV2TextLayoutFrame` is derived inside that width and never changes user padding.
3. When a valid measured full-width advance exists, the text frame uses the largest integer-cell width that fits, plus only the small native-layout float slack.
4. Any residual width is split equally into left/right text-frame insets.
5. `VisualLineLayoutEngine` and `ReaderParagraphLayout` use the exact same text-frame width.
6. The rendered block padding and TTS overlay use the exact same text-frame insets.
7. Metrics/cache identity is based on the effective drawable text geometry, so pre-change measurements are not reused.
8. Punctuation remains ordinary shaped content. This branch does not restore kinsoku or punctuation-specific line vetoes.
9. English/mixed text keeps the current Unicode word-boundary policy; this branch does not force justified English lines.

## Files changed

- `lib/features/reader_v2/layout/reader_v2_layout_spec.dart`
  - adds `ReaderV2TextLayoutFrame`;
  - keeps physical `contentWidth` unchanged;
  - exposes effective text paddings without mutating `ReaderV2LayoutStyle`.

- `lib/features/reader_v2/hybrid/core/hybrid_types.dart`
  - fingerprints the drawable text width and effective text paddings.

- `lib/features/reader_v2/hybrid/hybrid_reader_screen.dart`
  - plans visual lines with text-frame width;
  - builds drawable paragraphs with the same width;
  - paints blocks and TTS overlay with the same centered insets.

- `lib/features/reader_v2/layout/reader_v2_typography.dart`
  - versions the geometry contract so persisted metrics from the previous layout are not reused.

- `docs/night_reader/reader.md`
  - records the new ownership boundary.

## Explicitly not done

- No rollback to 152.
- No revert of the entire `5c66a413` physical-width ownership change.
- No PR.
- No merge to `main`.
- No release.
- No punctuation special cases.
- No new justification policy.

## Expected visible result

For normal CJK body text whose glyph advance is stable, full lines should again sit inside a horizontally centered drawable frame, so the residual width introduced by viewport dimensions is not accumulated entirely on the right.

The first line of a paragraph may still begin farther from the left because paragraph indentation is semantic text layout, not outer margin. Final lines and word-boundary-broken English/mixed lines may also remain ragged by design.
