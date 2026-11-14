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
 * Flutter only reads it (lib/data/detected.dart). Kinds:
 *   pay   a payment            skip  ignored, kept for tuning
 *   merge a second app reporting a payment already listed
 *   act   Save / Delete tapped on the banner
 */
object PaymentInbox {
    private const val NAME = "detected.jsonl"
    private const val MAX_BYTES = 300_000L
    private const val KEEP_LINES = 500
    private var lastKey = ""
    private var lastAt = 0L
    private var loaded = false
    private val recent = ArrayList<PaymentDetect.Seen>()
    private val answered = HashSet<String>()

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

    /** After the app process restarts, rebuild what was recently seen from the end of the file. */
    private fun load(c: Context) {
        if (loaded) return
        loaded = true
        try {
            val f = file(c)
            if (!f.exists()) return
            for (line in f.readLines().takeLast(80)) {
                val j = try { JSONObject(line) } catch (e: Exception) { continue }
                when (j.optString("k")) {
                    "pay" -> recent.add(PaymentDetect.Seen(j.optString("id"), j.optLong("t"), j.optString("app"), j.optString("kind"), j.optInt("cents"), j.optString("shop").ifEmpty { null }, j.optString("card").ifEmpty { null }))
                    "act" -> answered.add(j.optString("id"))
                }
            }
        } catch (e: Exception) {
            // unreadable file: start with an empty memory
        }
    }

    @Synchronized
    fun recent(c: Context): List<PaymentDetect.Seen> {
        load(c)
        return recent.toList()
    }

    @Synchronized
    fun remember(c: Context, s: PaymentDetect.Seen) {
        load(c)
        recent.removeAll { it.id == s.id }
        recent.add(s)
        while (recent.size > 40) recent.removeAt(0)
    }

    @Synchronized
    fun markAnswered(c: Context, id: String) {
        load(c)
        answered.add(id)
    }

    @Synchronized
    fun isAnswered(c: Context, id: String): Boolean {
        load(c)
        return id in answered
    }
}

/**
 * What the banner needs to guess a category and a payment type. Flutter writes detect_ctx.json whenever
 * categories, shop rules or remembered cards change; this side only reads it.
 */
class DetectCtx(val cats: Map<Int, String>, val rules: Map<String, Int>, val cards: Map<String, String>) {
    fun categoryFor(shop: String?): String {
        val id = shop?.let { rules[PaymentDetect.shopKey(it)] }
        return id?.let { cats[it] } ?: "Other"
    }

    companion object {
        fun load(c: Context): DetectCtx {
            val cats = HashMap<Int, String>()
            val rules = HashMap<String, Int>()
            val cards = HashMap<String, String>()
            try {
                val f = File(c.filesDir, "detect_ctx.json")
                if (f.exists()) {
                    val j = JSONObject(f.readText())
                    j.optJSONObject("cats")?.let { o -> for (k in o.keys()) k.toIntOrNull()?.let { cats[it] = o.optString(k) } }
                    j.optJSONObject("rules")?.let { o -> for (k in o.keys()) rules[k] = o.optInt(k) }
                    j.optJSONObject("cards")?.let { o -> for (k in o.keys()) cards[k] = o.optString(k) }
                }
            } catch (e: Exception) {
                // missing or half-written: guess without it
            }
            return DetectCtx(cats, rules, cards)
        }
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
        val source = PaymentDetect.sourceFor(sbn.packageName, label(sbn.packageName)) ?: return
        val ex = n.extras ?: return
        val title = ex.getCharSequence(Notification.EXTRA_TITLE)?.toString()?.trim() ?: ""
        val text = (ex.getCharSequence(Notification.EXTRA_BIG_TEXT) ?: ex.getCharSequence(Notification.EXTRA_TEXT))?.toString()?.trim() ?: ""
        if (title.isEmpty() && text.isEmpty()) return
        val now = System.currentTimeMillis()
        if (PaymentInbox.seenJustNow(sbn.key + "|" + title + "|" + text, now)) return

        val hit = PaymentDetect.read(source, title, text)
        if (hit == null) {
            // Private messages are never logged. For wallet and bank apps the skipped text helps tune the rules.
            if (source.kind != "sms") {
                PaymentInbox.append(this, JSONObject().apply {
                    put("k", "skip"); put("t", now); put("pkg", sbn.packageName); put("app", source.name); put("kind", source.kind)
                    put("title", PaymentDetect.mask(title, true)); put("text", PaymentDetect.mask(text, true))
                })
            }
            return
        }

        // The same purchase reported by a second app: one payment, not two.
        val earlier = PaymentDetect.mergeTarget(PaymentInbox.recent(this), source.name, hit.cents, now)
        if (earlier != null) {
            PaymentInbox.append(this, JSONObject().apply {
                put("k", "merge"); put("id", earlier.id); put("t", now); put("app", source.name)
                hit.shop?.let { put("shop", it) }
                hit.card?.let { put("card", it) }
            })
            val better = earlier.copy(shop = earlier.shop ?: hit.shop, card = earlier.card ?: hit.card, kind = if (earlier.card == null && hit.card != null) "card" else earlier.kind)
            if (better != earlier) {
                PaymentInbox.remember(this, better)
                if (!PaymentInbox.isAnswered(this, earlier.id)) PaymentPrompt.show(this, better, quiet = true)
            }
            return
        }

        val id = "n" + now.toString(36) + Integer.toString((sbn.key + text).hashCode() and 0xffff, 36)
        PaymentInbox.append(this, JSONObject().apply {
            put("k", "pay"); put("id", id); put("t", now); put("pkg", sbn.packageName); put("app", source.name); put("kind", source.kind)
            put("title", PaymentDetect.mask(title, false)); put("text", PaymentDetect.mask(text, false)); put("cents", hit.cents)
            hit.shop?.let { put("shop", it) }
            hit.card?.let { put("card", it) }
        })
        val seen = PaymentDetect.Seen(id, now, source.name, source.kind, hit.cents, hit.shop, hit.card)
        PaymentInbox.remember(this, seen)
        PaymentPrompt.show(this, seen, quiet = false)
    }
}

/**
 * The banner that drops from the top of the screen: "RM 28.00 · Weng Hoe Auto" with the guessed category and how it
 * was paid, and Save / Delete. Nothing is recorded until Save. Tapping the banner opens the Confirm sheet in the app.
 */
object PaymentPrompt {
    private const val CHANNEL = "detected_v2"
    private const val OLD_CHANNEL = "detected_payments"
    const val ACTION_SAVE = "my.cukup.cukup.DETECTED_SAVE"
    const val ACTION_IGNORE = "my.cukup.cukup.DETECTED_IGNORE"
    const val EXTRA_CONFIRM = "confirm_detected_id"

    fun notifId(id: String) = 7000 + (id.hashCode() and 0xfffff)

    fun show(c: Context, s: PaymentDetect.Seen, quiet: Boolean) {
        if (android.os.Build.VERSION.SDK_INT < 26) return
        val nm = c.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.deleteNotificationChannel(OLD_CHANNEL)
        nm.createNotificationChannel(NotificationChannel(CHANNEL, "Detected payments", NotificationManager.IMPORTANCE_HIGH).apply {
            description = "Pops up when Cukup notices a payment, so you can save or delete it"
        })
        val ctx = DetectCtx.load(c)
        val pay = PaymentDetect.payType(s.kind, s.card, ctx.cards)
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        val code = notifId(s.id)
        val open = PendingIntent.getActivity(
            c, code,
            Intent(c, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP).putExtra(EXTRA_CONFIRM, s.id),
            flags,
        )
        // Each button needs its own request code, or Android hands back the same PendingIntent for all of them.
        fun action(label: String, a: String, payType: String?, slot: Int): Notification.Action {
            val i = Intent(c, PaymentActionReceiver::class.java).setAction(a).putExtra("id", s.id)
            if (payType != null) i.putExtra("pay", payType)
            return Notification.Action.Builder(null, label, PendingIntent.getBroadcast(c, code * 4 + slot, i, flags)).build()
        }
        val amount = String.format(Locale.US, "RM %,.2f", s.cents / 100.0)
        val body = listOfNotNull(ctx.categoryFor(s.shop), PaymentDetect.payLabel(pay) ?: s.card, s.app).joinToString(" · ")
        val b = Notification.Builder(c, CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_cukup)
            .setContentTitle("$amount · ${s.shop ?: s.app}")
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(if (s.kind == "card" && pay == null) "$body\nIs this card credit or debit? Cukup will remember." else body))
            .setContentIntent(open)
            .setAutoCancel(true)
            .setOnlyAlertOnce(quiet)
            .setCategory(Notification.CATEGORY_STATUS)
        if (s.kind == "card" && pay == null) {
            b.addAction(action("Credit", ACTION_SAVE, "credit_card", 0))
            b.addAction(action("Debit", ACTION_SAVE, "debit", 1))
        } else {
            b.addAction(action("Save", ACTION_SAVE, null, 0))
        }
        b.addAction(action("Delete", ACTION_IGNORE, null, 2))
        try {
            nm.notify(code, b.build())
        } catch (e: SecurityException) {
            // notifications are off for Cukup: the payment still waits on the Home screen
        }
    }

    fun cancel(c: Context, id: String) {
        if (android.os.Build.VERSION.SDK_INT < 26) return
        (c.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancel(notifId(id))
    }
}

/** Save / Delete tapped on the banner. The choice is written down; Flutter acts on it the next time the app is open. */
class PaymentActionReceiver : BroadcastReceiver() {
    override fun onReceive(c: Context, i: Intent) {
        val id = i.getStringExtra("id") ?: return
        val a = when (i.action) {
            PaymentPrompt.ACTION_SAVE -> "save"
            PaymentPrompt.ACTION_IGNORE -> "ignore"
            else -> return
        }
        PaymentInbox.append(c, JSONObject().apply {
            put("k", "act"); put("id", id); put("a", a); put("via", "banner"); put("t", System.currentTimeMillis())
            i.getStringExtra("pay")?.let { put("pay", it) }
        })
        PaymentInbox.markAnswered(c, id)
        PaymentPrompt.cancel(c, id)
    }
}
