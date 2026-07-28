# Infrastructure

## Responsibility

Shared framework code and cross-cutting infrastructure that every feature and core module depends on. Owns the Provider base class, global config mirror, dependency injection wiring, preference key catalog, app exceptions, utility functions, shared widgets, and the design system (theme/tokens/navigation). When changing any of these, expect every module that uses them to need re-verification.

## Scope

- `lib/core/base/base_provider.dart` — abstract `BaseProvider(ChangeNotifier)` with loading/error/cancelToken lifecycle. Every ViewModel in the app extends this.
- `lib/core/config/app_config.dart` — static mirror (`AppConfig`) of user-facing settings, synced from `SettingsProvider` / `ReaderSettingsMixin` so model-layer code can read defaults without a BuildContext.
- `lib/core/constant/` — `PreferKey` (229 shared_preferences keys), `BookType`, `SourceType`, `AppPattern`.
- `lib/core/di/injection.dart` — GetIt setup wiring DAOs, services, DB, SharedPreferences.
- `lib/core/exception/app_exception.dart` — typed exception hierarchy.
- `lib/core/utils/` — encoder_utils, html_formatter, lru_map, network_utils, string_utils, ttf_parser.
- `lib/core/widgets/book_cover_widget.dart` — shared cover widget used by bookshelf, search, explore, book_detail.
- `lib/shared/theme/` — `app_tokens.dart` (design tokens), `app_theme.dart` (ThemeData), `app_text_styles.dart`, `context_ext.dart`.
- `lib/shared/navigation/book_open_route.dart` — route data class for opening a book (used by bookshelf → reader).
- `lib/shared/widgets/` — `app_bottom_sheet.dart`, `source_option_tile.dart`.

## Dependencies & Impact

- **Upstream:** Depends on `shared_preferences` (key definitions), `provider` (base provider base), `get_it` (DI container). Theme depends on Flutter Material.
- **Downstream:** Every feature module imports `base_provider.dart` (all ViewModels), `prefer_key.dart` (settings access), `app_config.dart` (model defaults), `injection.dart` (service/DAO resolution), theme tokens (UI consistency). A change to `BaseProvider` alters the error-handling contract for all ViewModels. A new `PreferKey` entry must be mirrored in `AppConfig` and the corresponding `SettingsProvider`.

## Key Flows

- **App startup:** `main.dart` → `injection.dart` initialises DB, DAOs, services → `SplashPage` creates `AppProviders` → navigation shell boots. Every Provider resolved via `GetIt` after injection.
- **Settings flow:** `SettingsProvider` mutates `shared_preferences` → writes the new value into `AppConfig` static field → model-layer code reads `AppConfig` for defaults → reader layout engine queries `AppConfig` for typography parameters.
- **Error flow:** feature Provider calls `BaseProvider.setLoading/setError` → UI layer listens via `context.watch/select`. `AppException` subclasses let callers branch on error type.

## Change Entry Points & Routes

- **New preference key:** add key in `PreferKey` → add field in `AppConfig` → add UI toggle in settings feature → sync in `SettingsProvider`. For reader-specific prefs, also register in `ReaderSettingsMixin`.
- **Change to `BaseProvider`:** verify every subclass handles the new contract (loading state, error shape, cancellation). 27+ ViewModels extend it.
- **Theme change:** `app_tokens.dart` is the token source → `app_theme.dart` builds `ThemeData` from tokens → verify against every feature page.
- **DI wiring change:** `injection.dart` is the single registration point. Verify that background isolate (`main.dart` callbackDispatcher) also registers the services it needs, because `GetIt` state is not shared across isolates.

## Known Risks

- `AppConfig` is a static mutable singleton with no synchronisation. Two Providers writing conflicting values in the same frame can silently overwrite each other.
- Background isolate (`Workmanager` callback) cannot access the main isolate's `GetIt` container. Any new service that a background task needs must also be registered inside the callback's DI setup — easy to forget.
- The 229-entry `PreferKey` file has no namespacing; naming collisions across features are only caught at review.
- `BaseProvider` ties every ViewModel to `ChangeNotifier` — migrating to a different state management approach would affect the entire app.

## Do Not Do

- Do not add mutable static state outside `AppConfig` — there is no synchronisation story for it.
- Do not add a new `shared_preferences` key without adding its mirror field in `AppConfig`.
- Do not import `dart:io` or platform-specific code in `shared/theme/` — it must stay platform-agnostic.
- Do not add business logic to utility functions in `utils/` — they are stateless transformations.
