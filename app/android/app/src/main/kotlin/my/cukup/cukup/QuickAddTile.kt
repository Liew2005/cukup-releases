package my.cukup.cukup

import android.app.PendingIntent
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

/** Quick Settings tile: swipe down, tap, and Quick add opens. */
class QuickAddTile : TileService() {
    override fun onStartListening() {
        qsTile?.apply {
            state = Tile.STATE_INACTIVE
            updateTile()
        }
    }

    @Suppress("DEPRECATION", "StartActivityAndCollapseDeprecated")
    override fun onClick() {
        val i = Intent(Intent.ACTION_VIEW, Uri.parse("cukup:///quick"), this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (Build.VERSION.SDK_INT >= 34) {
            startActivityAndCollapse(PendingIntent.getActivity(this, 1, i, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
        } else {
            startActivityAndCollapse(i)
        }
    }
}
