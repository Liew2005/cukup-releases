package my.cukup.cukup

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
import java.time.LocalDate
import java.time.ZoneId
import java.util.Locale
import kotlin.math.abs

/** Home-screen widget: money left this week, days to go, and Quick add / Scan buttons. */
class CukupWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val cap = widgetData.getString("cap_cents", null)?.toLongOrNull() ?: 25000L
        val spentSaved = widgetData.getString("spent_cents", null)?.toLongOrNull() ?: 0L
        val weekEnd = widgetData.getString("week_end", null)?.let { runCatching { LocalDate.parse(it) }.getOrNull() }
        val today = LocalDate.now(ZoneId.of("Asia/Kuala_Lumpur"))

        // If a new week started since the app last saved, nothing has been spent in it yet.
        val newWeek = weekEnd != null && today.isAfter(weekEnd)
        val spent = if (newWeek) 0L else spentSaved
        val left = cap - spent
        val daysToGo = 7 - today.dayOfWeek.value // Monday = 1 ... Sunday = 7

        val title = if (left < 0) "Over the cap by" else "Left this week"
        val amount = "RM " + String.format(Locale.US, "%,.2f", abs(left) / 100.0)
        val sub = when {
            weekEnd == null -> "Open Cukup to start"
            daysToGo == 0 -> "of RM " + String.format(Locale.US, "%,.0f", cap / 100.0) + " · last day"
            else -> "of RM " + String.format(Locale.US, "%,.0f", cap / 100.0) + " · $daysToGo ${if (daysToGo == 1) "day" else "days"} to go"
        }

        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.cukup_widget)
            views.setTextViewText(R.id.widget_title, title)
            views.setTextViewText(R.id.widget_amount, amount)
            views.setTextViewText(R.id.widget_sub, sub)
            views.setTextColor(R.id.widget_amount, if (left < 0) 0xFFB4432B.toInt() else 0xFF0E3B32.toInt())
            views.setOnClickPendingIntent(R.id.widget_root, open(context, "cukup:///", 1))
            views.setOnClickPendingIntent(R.id.widget_add, open(context, "cukup:///quick", 2))
            views.setOnClickPendingIntent(R.id.widget_scan, open(context, "cukup:///scan", 3))
            appWidgetManager.updateAppWidget(id, views)
        }
    }

    private fun open(context: Context, uri: String, code: Int): PendingIntent {
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(uri)).setClass(context, MainActivity::class.java)
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        return PendingIntent.getActivity(context, code, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }
}
