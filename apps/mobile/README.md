# Codev Assistant (Flutter)

This is the primary cross-platform Personal Tracker app. The former web dashboard is archived under `не трогать, теперь есть прога на flutter/web`; Flutter uses the existing TypeScript API contract and does not require the archive at runtime.

## Run

## Verified local environment

The current Windows verification environment has:

- Flutter stable `3.44.8` with Dart `3.12.2` at `C:\Users\Legion\Tools\flutter`.
- Android command-line SDK 36 at `C:\Users\Legion\Android\Sdk`, JDK 17, accepted licenses, NDK 28.2.13676358 and CMake 3.22.1.
- Visual Studio Community 2026 with the Windows SDK 10.0.26100.0.

If a terminal or IDE was open before installation, restart it so the user PATH and `ANDROID_HOME`/`ANDROID_SDK_ROOT` values are reloaded. Run:

```bash
flutter doctor -v
flutter pub get
flutter analyze
flutter test
flutter run -d windows --dart-define=PT_API_BASE_URL=http://localhost:4000 --dart-define=PT_API_TOKEN=...
```

The following checks passed on this host: `flutter doctor -v`, `flutter pub get`, `flutter analyze`, `flutter test`, `flutter build windows`, and `flutter build apk`. The Windows release executable also started successfully. This does not yet verify the complete interactive native E2E flow or an Android device runtime; see [`docs/VERIFICATION.md`](../../docs/VERIFICATION.md).

The API base URL and token are compile-time configuration only. For production, use the normal authenticated login/refresh flow rather than shipping a shared token.

## Implemented first slice

- Quick Capture is the first screen.
- Text input and system speech-to-text both feed the same `CommandParser`.
- `DeterministicParser` handles Russian expense, sales call, English and sports examples without AI credits.
- `AiParser` is an intentionally empty future adapter for a protected server endpoint.
- Every confirmed record is written to SQLite and a sync outbox before any REST request.
- A failed API call leaves the record pending for retry.
- On startup the app retries the persisted outbox; an empty/unconfigured API never marks records as synced.
- UUID-based records map to the existing `/api/v1/sync` contract; repeated batches are idempotent on the API.
- The Assistant tab has a daily snapshot and module entry points for English, Money, Sales and Sports.
- The Assistant panel now parses movie requests with a requested count and genre/mood, creates locally persisted tasks with date/time extraction, and runs phone/Telegram actions through the platform URL handlers without a redundant second confirmation.
- Contacts can be stored locally with `запомни контакт мама +998...`; later `позвони мама` and `напиши мама в Telegram ...` resolve the saved phone or username by name.
- Calendar actions open a prefilled Google Calendar event template after the task is stored in SQLite. When no contact is found by name, the Assistant explains how to save it instead of launching an incomplete action.
- English has a concrete offline 90-day foundation from mid-A2 to B1: 90 integrated lessons, each with Reading, Listening, Speaking and Writing. Lessons are normally 60 minutes; first sessions and checkpoints use 70 minutes where a new topic or assessment needs extra time.
- Every lesson has a detail screen, an actual writing response saved to SQLite, a YouTube listening link, and a local microphone recording with playback. A lesson is not complete until all four skill blocks are done.
- The B1 → B2 stage contains the next 84 lessons but stays locked until all 90 A2.5 → B1 lessons are completed. The roadmap exposes an `EnglishPlanAdvisor` seam. The deterministic advisor is the current baseline; a future protected AI service can revise lesson order, topics and difficulty, or append a post-B2 stage without changing the local storage/UI contract.
- Sports has a local-first 90-day strength path with A/B/C/D templates. The first three gym sessions are full-body baseline sessions so the following template already has personal movement history to work from.
- Sessions 1–3 require manual kg/repetitions/sets. From session 4, `SportLoadAdvisor` proposes a conservative load from completed personal sets; the current deterministic implementation never invents a first weight, while a future AI adapter can use recovery, RIR, technique and notes.
- Sport set logs and completed workouts are stored in SQLite, so a restart keeps the actual training history and the next load estimate.
- The toolbar imports the archived web JSON backup, validates structure, preserves raw rows in SQLite, creates event records where possible, deduplicates by stable source IDs and reports found/imported/skipped/warnings. The original JSON file is never deleted.

## Web data migration

If legacy data is needed, open the archived web dashboard at `не трогать, теперь есть прога на flutter/web` and use Settings → JSON export. In Flutter, use the file-upload action in the Assistant toolbar. Structural rows without a Quick Capture event mapping are retained as local raw migration rows and reported as warnings; the original backup remains untouched.

## Native integration templates

Templates are under `platforms/` for the platform-specific entry points requested in the product brief:

- Android: Quick Settings tile, app shortcut, notification action and Assistant/App Action handoff.
- iOS: App Intent/Siri and widget handoff.
- Windows: tray/hotkey/mini-window integration.
- macOS: menu bar/hotkey/Shortcut integration.

They are intentionally isolated from Dart so the Flutter shell remains portable. They still need to be wired into generated platform runners and verified on real devices; templates are not claimed as working features.
