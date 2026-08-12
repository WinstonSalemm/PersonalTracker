# Windows wiring template

Use a small native runner/plugin around the generated Flutter Windows host to register `Ctrl+Alt+Space`, create a tray icon and open a compact Quick Capture window. Keep the global hook opt-in and release it on exit. Voice capture continues through the Dart speech-to-text adapter. Startup should be a user preference, not an unconditional registry write.
