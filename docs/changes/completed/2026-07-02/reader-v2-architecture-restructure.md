# Reader V2 architecture restructure

## Before

Reader V2 uses `shell / application / runtime / content / layout / render / viewport / features`.
The names mix UI assembly, application coordination, state machine internals, and content pipeline concerns.
`runtime` is especially broad and currently contains state, navigation, progress, preload, resolver, viewport bridge, and performance support.

## After

Restructure the top-level Reader V2 folders toward domain-oriented names while keeping behavior unchanged in the first pass:

- `screen/` for Flutter page entry, shell widgets, controller host, and dependency assembly.
- `session/` for reader state, location, open target, runtime facade, navigation, progress, preload, resolver, and session-oriented support objects.
- `use_cases/` for page/application coordinators and user-intent orchestration.
- `chapter/` for chapter repository, processed content, and content transformation pipeline.
- Keep `layout/`, `render/`, `viewport/`, and `features/` as existing technical subdomains.

First pass intentionally avoids rewriting the runtime state machine. The goal is to make ownership visible and make later extraction safer.

## Validation

- `flutter analyze`
- `flutter test test/features/reader_v2`

