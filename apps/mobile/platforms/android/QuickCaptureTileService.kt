package uz.personaltracker.assistant

import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.content.Intent

/** Template to copy into the generated Android runner. */
class QuickCaptureTileService : TileService() {
    override fun onClick() {
        super.onClick()
        qsTile?.state = Tile.STATE_ACTIVE
        qsTile?.updateTile()
        val intent = Intent(this, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            .putExtra("quick_capture_mode", "general")
        startActivityAndCollapse(intent)
    }
}
