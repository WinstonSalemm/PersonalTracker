package uz.personaltracker.assistant

import android.content.Intent
import android.content.BroadcastReceiver
import android.content.Context

/** Handles an Android App Shortcut/notification action handoff. */
class QuickCaptureShortcutReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val launch = Intent(context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            .putExtra("quick_capture_mode", intent.getStringExtra("mode") ?: "general")
        context.startActivity(launch)
    }
}
