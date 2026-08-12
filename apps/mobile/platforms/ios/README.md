# iOS wiring template

Add `QuickCaptureAppIntent` to the generated iOS runner, expose it through an App Shortcuts provider and build a WidgetKit lock-screen widget that opens the app with `quick_capture_mode`. Siri Shortcut and Action Button flows should only open Quick Capture; confirmation remains in Dart. Control Center availability depends on the target iOS version and entitlements.
