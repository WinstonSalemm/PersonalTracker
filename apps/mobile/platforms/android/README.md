# Android wiring template

Register `QuickCaptureTileService` with `android.permission.BIND_QUICK_SETTINGS_TILE`, add a static app shortcut and route notification actions to `QuickCaptureShortcutReceiver`. The Dart side should read `quick_capture_mode` through a platform channel and preselect expense, call, English or Sports. Add an Assistant App Action only after the Android project has a verified App Actions manifest and fulfillment mapping.
