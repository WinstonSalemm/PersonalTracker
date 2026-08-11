import AppIntents

@available(iOS 16.0, *)
struct QuickCaptureAppIntent: AppIntent {
    static var title: LocalizedStringResource = "Quick Capture"
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        // The generated Flutter runner should consume this handoff and open
        // the Quick Capture route. No financial record is created here.
        return .result()
    }
}
