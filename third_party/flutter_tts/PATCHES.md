# Night Reader patches for `flutter_tts`

## Source

- Package: [`flutter_tts` 4.2.5](https://pub.dev/packages/flutter_tts/versions/4.2.5)
- Archive: `https://pub.dev/api/archives/flutter_tts-4.2.5.tar.gz`
- Archive SHA-256: `ce5eb209b40e95f2f4a1397116c87ab2fcdff32257d04ed7a764e75894c03775`
- Upstream repository: <https://github.com/dlutton/flutter_tts>
- Vendored version: `4.2.5+nightreader.6`
- License: MIT; the upstream [`LICENSE`](LICENSE) is retained unchanged.

## Local patch

- `android/build.gradle` applies only `com.android.library`, relying on AGP 9's
  built-in Kotlin support instead of applying `kotlin-android`.
- The Android DSL uses `compileSdk = 37`, `minSdk = 24`, the public `lint {}`
  block, and `kotlin.compilerOptions` with JVM 11.
- The plugin-local AGP/KGP buildscript and explicit Kotlin standard-library
  dependency were removed; the consuming Android build supplies AGP and its
  built-in Kotlin toolchain.
- `pubspec.yaml` adds Night Reader build metadata so dependency reports identify
  the patched package.
- This first patch touches build configuration only; later patches below change
  the Dart API and the Android runtime.

## Reason and tracking

The published 4.2.5 Android script applies `kotlin-android` and uses the legacy
`android.kotlinOptions` and `lintOptions` DSLs. Those declarations are not
compatible with AGP 9's default built-in Kotlin and new public DSL.

- Migration guide: <https://developer.android.com/build/migrate-to-built-in-kotlin>
- Related Flutter tooling issue: <https://github.com/flutter/flutter/issues/189133>
- Upstream `flutter_tts` issue/PR: none filed for this package-specific patch as
  of 2026-08-13.

## Patch `nightreader.2`: Android only

- Removed the iOS, macOS, Windows and Web implementations and their plugin
  registrations; `pubspec.yaml` declares Android only and drops
  `flutter_web_plugins`.
- Dart sources follow Night Reader's `flutter_lints` and `dart format` rules.

## Maintenance

Night Reader maintains this package in-tree and no longer tracks upstream.

## Patch `nightreader.3`: engine display names

- `getEngines` returns `{name, label}` maps instead of bare package names, so
  the app can show 「Google 語音服務」 instead of `com.google.android.tts`
  while still passing `name` to `setEngine`.

## Patch `nightreader.4`: iOS restored

- Restored the upstream 4.2.5 iOS implementation (`ios/`) and its plugin
  registration. The podspec's deployment target is raised from 8.0 to 13.0;
  the sources are otherwise unchanged.

## Patch `nightreader.5`: Android engine work off the main thread

- Every method call, the `onInit` follow-up (default voice locale, pending
  calls), `TextToSpeech` creation and the utterance progress callbacks run in
  order on the plugin's own `HandlerThread` (`flutter_tts`); all plugin state is
  read and written only there. Each call is a binder round trip to the TTS
  service, and voice lists are large parcels read several times while the app
  sets up the engine; on Android the main thread also draws Flutter frames, so
  this work stalled launch animations. Results and events are posted back to
  the main thread (`MainThreadResult`, `invokeMethod`).
- Work on that thread catches its own exceptions (Flutter only catches them
  for handlers running on the main thread): a failing call replies with an
  error instead of ending the app. `MainThreadResult` forwards only the first
  reply.
- `onInit` applies the default voice locale before running calls queued while
  connecting, so a queued `setLanguage` is no longer reverted to the default.
- Each engine is tagged with a generation; `onInit` and progress callbacks of a
  replaced engine are ignored. `setEngine`'s reply belongs to the engine being
  connected and is answered before queued calls replay; a superseded
  `setEngine`, and a pending awaited `speak` or `synthesizeToFile`, reply `0`
  when their engine is replaced.
- `setEngine` with the engine the current instance was created for (the
  requested one, or the system default at creation) replies at once instead of
  binding the TTS service again; switching engines shuts the replaced engine
  down.
- Failures reply instead of hanging: `speak` the connected engine rejects
  replies `0` (only a lost connection reconnects and retries); utterance errors
  complete an awaited `speak`/`synthesizeToFile` with `0`; `setSilence` replies.
  On Android 24–25, `onStart` for silence and synthesis utterances no longer
  dereferences a missing text.

## Patch `nightreader.6`: bounded reconnect and current-utterance callbacks

- A `speak` whose engine connection is gone reconnects at most once. The call
  is replayed after that one engine reports `onInit`; if the connection is
  still unusable, or the engine rejects the sentence, it replies `0` instead of
  starting another engine and queueing itself again. Before this, a phone with
  no working TTS service kept replacing the engine forever: every failed
  `onInit` replayed the queued `speak`, which reconnected again, so Dart never
  got a reply.
- Calls still queue while an engine has not answered `onInit` at all. The app
  bounds that wait with its own timeouts (`TTSService.engineReplyWait`); the
  plugin cannot tell a slow engine from a dead one.
- Utterance callbacks belong to the sentence that is current when they arrive:
  `onDone`, `onStop` and `onError` for an utterance replaced by a newer `speak`
  are ignored. The late completion of the previous sentence no longer reads as
  the end of the new one (which made the reader skip a sentence) and no longer
  releases audio focus while the new sentence is speaking.
- The current utterance id is recorded before `speak` is handed to the engine
  (and restored if the engine rejects it), so a very short sentence that
  finishes before `speak` returns still reports its own completion.
