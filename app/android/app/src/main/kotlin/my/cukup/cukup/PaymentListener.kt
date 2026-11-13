package my.cukup.cukup

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import org.json.JSONObject
import java.io.File
import java.util.Locale

/**
 * Append-only list of what the listener saw, one JSON object per line, in the app's private files folder.
 * Flutter only reads it (lib/data/detected.dart). Kinds: pay (a payment), skip (ignored, kept for tuning), act (Save / Ignore tapped).
 */
object PaymentInbox {
    private const val NAME = "detected.jsonl"
    private const val MAX_BYTES = 300_000L
    private const val KEEP_LINES = 500
    private var lastKey = ""
    private var lastAt = 0L

    private fun file(c: Context) = File(c.filesDir, NAME)

    @Synchronized
    fun append(c: Context, o: JSONObject) {
        val f = file(c)
        f.appendText(o.toString() + "\n")
        if (f.length() > MAX_BYTES) f.writeText(f.readLines().takeLast(KEEP_LINES).joinToString("\n") + "\n")
    }

    /** Apps often post the same notification twice (an update). True when this exact one was just seen. */
    @Synchronized
    fun seenJustNow(key: String, now: Long): Boolean {
        val same = key == lastKey && now - lastAt < 120_000
        lastKey = key
        lastAt = now
        return same
    }
}

/** Reads payment notifications from the wallet and bank apps and offers to save each one. Nothing leaves the phone. */
class PaymentListener : NotificationListenerService() {
    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        try {
            if (sbn != null) handle(sbn)
        } catch (e: Exception) {
            // never let a strange notification crash the listener
        }
    }

    private fun label(pkg: String): String = try {
        packageManager.getApplicationLabel(packageManager.getApplicationInfo(pkg, 0)).toString()
    } catch (e: Exception) {
        ""
    }

    private fun handle(sbn: StatusBarNotification) {
        if (sbn.packageName == packageName) return
        val n = sbn.notification ?: return
        if (n.flags and Notification.FLAG_GROUP_SUMMARY != 0) return
        val appLabel = label(sbn.packageName)
        val source = PaymentDetect.sourceFor(sbn.packageName, appLabel) ?: return
        val ex = n.extras ?: return
        val title = ex.getCharSequence(Notification.EXTRA_TITLE)?.toString()?.trim() ?: ""
        val text = (ex.getCharSequence(Notification.EXTRA_BIG_TEXT) ?: ex.getCharSequence(Notification.EXTRA_TEXT))?.toString()?.trim() ?: ""
        if (title.isEmpty() && text.isEmpty()) return
        val now = System.currentTimeMillis()
        if (PaymentInbox.seenJustNow(sbn.key + "|" + title + "|" + text, now)) return

        val cents = PaymentDetect.read(source, title, text)
        if (cents == null) {
            // Private messages are never logged. For wallet and bank apps the skipped text helps tune the rules.
            if (source.kind != "sms") {
                PaymentInbox.append(this, JSONObject().apply {
                    put("k", "skip"); put("t", now); put("pkg", sbn.packageName); put("app", source.name); put("kind", source.kind)
                    put("title", PaymentDetect.mask(title, true)); put("text", PaymentDetect.mask(text, true))
                })
            }
            return
        }
        val id = "n" + now.toString(36) + Integer.toString((sbn.key + text).hashCode() and 0xffff, 36)
        PaymentInbox.append(this, JSONObject().apply {
            put("k", "pay"); put("id", id); put("t", now); put("pkg", sbn.packageName); put("app", source.name); put("kind", source.kind)
            put("title", PaymentDetect.mask(title, false)); put("text", PaymentDetect.mask(text, false)); put("cents", cents)
        })
        PaymentPrompt.show(this, id, cents, source.name, if (title.isEmpty()) text else "$title: $text")
    }
}

/** The "RM 12.50 · TNG eWallet. Save?" notification. */
object PaymentPrompt {
    private const val CHANNEL = "detected_payments"
    const val ACTION_SAVE = "my.cukup.cukup.DETECTED_SAVE"
    const val ACTION_IGNORE = "my.cukup.cukup.DETECTED_IGNORE"

    fun notifId(id: String) = 7000 + (id.hashCode() and 0xfffff)

    fun show(c: Context, id: String, cents: Int, app: String, body: String) {
        if (android.os.Build.VERSION.SDK_INT < 26) return
        val nm = c.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.createNotificationChannel(NotificationChannel(CHANNEL, "Detected payments", NotificationManager.IMPORTANCE_DEFAULT).apply {
            description = "Asks whether to save a payment Cukup noticed"
        })
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        val code = notifId(id)
        val open = PendingIntent.getActivity(c, code, Intent(c, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP), flags)
        fun action(a: String) = PendingIntent.getBroadcast(c, code, Intent(c, PaymentActionReceiver::class.java).setAction(a).putExtra("id", id), flags)
        val amount = String.format(Locale.US, "RM %,.2f", cents / 100.0)
        val n = Notification.Builder(c, CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_cukup)
            .setContentTitle("$amount · $app")
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setContentIntent(open)
            .setAutoCancel(true)
            .addAction(Notification.Action.Builder(null, "Save", action(ACTION_SAVE)).build())
            .addAction(Notification.Action.Builder(null, "Ignore", action(ACTION_IGNORE)).build())
            .build()
        try {
            nm.notify(code, n)
        } catch (e: SecurityException) {
            // notifications are off for Cukup: the payment still waits on the Home screen
        }
    }

    fun cancel(c: Context, id: String) {
        if (android.os.Build.VERSION.SDK_INT < 26) return
        (c.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancel(notifId(id))
    }
}

/** Save / Ignore tapped on the prompt. The choice is written down; Flutter acts on it the next time the app is open. */
class PaymentActionReceiver : BroadcastReceiver() {
    override fun onReceive(c: Context, i: Intent) {
        val id = i.getStringExtra("id") ?: return
        val a = when (i.action) {
            PaymentPrompt.ACTION_SAVE -> "save"
            PaymentPrompt.ACTION_IGNORE -> "ignore"
            else -> return
        }
        PaymentInbox.append(c, JSONObject().apply { put("k", "act"); put("id", id); put("a", a); put("t", System.currentTimeMillis()) })
        PaymentPrompt.cancel(c, id)
    }
}
