# Release 0.2.118

## Before

- `main` was clean and aligned with `origin/main`.
- Latest release tag was `v0.2.117`.
- `HEAD` contained one post-release reader performance commit.
- `pubspec.yaml` still had `version: 0.2.117+131`.

## After

- Bumped `pubspec.yaml` to `0.2.118+132`.
- Ran release verification:
  - `flutter pub get` passed.
  - `flutter analyze` passed with no issues.
  - `flutter test` passed.

## Release Steps

- Commit version metadata.
- Push `main`.
- Tag `v0.2.118`.
- Push `v0.2.118`.
- Confirm Android Release workflow starts.
