package my.cukup.cukup

/**
 * The rules for payment notifications: which apps count, whether the text is money going out,
 * how much, where to, and with which card. Pure Kotlin with no Android classes, so it is unit tested
 * on the computer (src/test/.../PaymentDetectTest.kt). This is the only copy of these rules.
 */
object PaymentDetect {
    /** kind: wallet | bank | sms | card */
    data class Source(val name: String, val kind: String)

    /** A payment read from one notification. */
    data class Hit(val cents: Int, val shop: String?, val card: String?)

    /** A payment already noticed, kept to spot the same purchase reported by a second app. */
    data class Seen(val id: String, val at: Long, val app: String, val kind: String, val cents: Int, val shop: String?, val card: String?)

    private val smsPackages = setOf(
        "com.google.android.apps.messaging", "com.android.mms", "com.android.messaging", "com.samsung.android.messaging",
    )

    private val bankWords = Regex("\\b(uob|hsbc|cimb|gx ?bank|ryt|hong leong|hlb|ambank|am ?online)\\b", RegexOption.IGNORE_CASE)

    /** Which payment app a notification came from, or null for every other app. */
    fun sourceFor(pkg: String, label: String): Source? {
        val p = pkg.lowercase()
        val l = label.lowercase().trim()
        if (p in smsPackages) return Source("SMS", "sms")
        return when {
            p == "com.google.android.apps.walletnfcrel" || l == "google wallet" || (l == "wallet" && p.startsWith("com.google.")) -> Source("Google Wallet", "card")
            p.contains("tngdigital") || l.contains("touch 'n go") || l.contains("touch n go") || l.startsWith("tng") -> Source("TNG eWallet", "wallet")
            p.contains("shopee") || l.startsWith("shopee") -> Source("ShopeePay", "wallet")
            p.contains("grabtaxi") || l == "grab" -> Source("Grab", "wallet")
            p.contains("ambank") || p.contains("amonline") || l.startsWith("ambank") || l.startsWith("amonline") -> Source("AmBank", "bank")
            p.contains("uob") || l.startsWith("uob") -> Source("UOB", "bank")
            p.contains("hsbc") || l.startsWith("hsbc") -> Source("HSBC", "bank")
            p.contains("cimb") || l.startsWith("cimb") -> Source("CIMB", "bank")
            p.contains("gxbank") || p.contains("gxb.") || l.startsWith("gxbank") || l.startsWith("gx bank") -> Source("GXBank", "bank")
            p.contains("rytbank") || p.endsWith(".ryt") || p.contains(".ryt.") || l.startsWith("ryt") -> Source("Ryt Bank", "bank")
            p.contains("hongleong") || p.contains("hlb") || l.contains("hong leong") || l.startsWith("hlb") -> Source("HLB", "bank")
            else -> null
        }
    }

    private const val NUM = "([0-9]{1,3}(?:,[0-9]{3})+(?:\\.[0-9]{1,2})?|[0-9]+(?:\\.[0-9]{1,2})?)"
    private val amount = Regex("(?:RM|MYR)\\s?$NUM", RegexOption.IGNORE_CASE)

    // Money coming in, codes, adverts and failures: never a spend.
    private val notSpend = Regex(
        "\\b(received|receive|credited|cash ?back|refund(ed)?|reversal|reversed|rewards?|vouchers?|otp|tac|verification code|" +
            "top(ped)?[- ]?up|reload(ed)?|promo(tion)?s?|discounts?|% off|sale|win|earn(ed)?|claim(ed)?|statement|due|reminder|" +
            "fail(ed)?|unsuccessful|declined|rejected|request(ed|ing)?|limit|login|log in|diterima|gagal)\\b",
        RegexOption.IGNORE_CASE,
    )

    private val spend = Regex(
        "\\b(paid|payment|pay|spent|purchase(d)?|debited|deducted|charged|transaction|transfer(red)?|sent|withdraw(n|al)?|" +
            "pembayaran|bayaran|dibayar|ditolak|pindahan)\\b",
        RegexOption.IGNORE_CASE,
    )

    // Google Wallet after a tap: the title is the shop and the text is "MYR28.00 with AmBank BonusLink Visa".
    private val tap = Regex("^\\s*(?:RM|MYR)\\s?$NUM\\s+with\\s+(.+?)\\s*$", RegexOption.IGNORE_CASE)
    private val tapNotSpend = Regex("\\b(refund(ed)?|declined|fail(ed)?|unsuccessful|reversed|reversal|cancel(l)?ed)\\b", RegexOption.IGNORE_CASE)

    private fun cents(num: String): Int? {
        val v = num.replace(",", "").toDoubleOrNull() ?: return null
        val c = Math.round(v * 100)
        return if (c in 1..100_000_000) c.toInt() else null
    }

    /** The payment in this notification, or null when it is not money going out. */
    fun read(source: Source, title: String, text: String): Hit? {
        val all = "$title\n$text"
        if (source.kind == "card") {
            if (tapNotSpend.containsMatchIn(all)) return null
            val m = tap.find(text)
            if (m != null) {
                val c = cents(m.groupValues[1]) ?: return null
                return Hit(c, clean(title), m.groupValues[2].trim().trimEnd('.', '…').trim().ifEmpty { null })
            }
            // any other wording falls through to the general rules
        }
        if (source.kind == "sms" && !bankWords.containsMatchIn(all)) return null
        if (notSpend.containsMatchIn(all) || !spend.containsMatchIn(all)) return null
        val m = amount.find(all) ?: return null
        val c = cents(m.groupValues[1]) ?: return null
        return Hit(c, merchantFrom(title, text), null)
    }

    private val toShop = Regex(
        "\\b(?:paid|payment|pay|spent|purchase|purchased|transaction|transfer|transferred|sent|charged|pembayaran|bayaran|dibayar)\\b[^\\n]{0,60}?\\b(?:to|at|kepada|di)\\s+(.+)",
        RegexOption.IGNORE_CASE,
    )
    private val atShop = Regex("(?:\\bat\\b|@)\\s+(.+)", RegexOption.IGNORE_CASE)
    private val stop = Regex(
        "\\s+(?:on|via|using|with|from|for|ref|reference|is|was|has|have|dated|at|pada|melalui|telah|berjaya)\\b|\\s+\\d{1,2}[/:-]\\d|[.,;!?(\\n]|\\s+(?:RM|MYR)\\s?\\d",
        RegexOption.IGNORE_CASE,
    )
    private val notAShop = Regex("^(your|you|the|a|an|my|account|card|wallet)\\b", RegexOption.IGNORE_CASE)
    private val spaces = Regex("\\s+")

    private fun clean(raw: String): String? {
        var s = raw.replace(spaces, " ").trim().trim('"', '\'', '*', ' ')
        if (s.length > 40) s = s.substring(0, 40).trim()
        return if (s.length >= 2 && s.any { it.isLetter() } && !amount.containsMatchIn(s) && !notAShop.containsMatchIn(s)) s else null
    }

    /** The shop a payment went to, read from wording like "paid RM 5.00 to Mixue Kajang". Null when it is not said. */
    fun merchantFrom(title: String, text: String): String? {
        for (src in listOf(text, "$title $text")) {
            for (re in listOf(toShop, atShop)) {
                val m = re.find(src) ?: continue
                var s = m.groupValues[1]
                val cut = stop.find(s)
                if (cut != null) s = s.substring(0, cut.range.first)
                clean(s)?.let { return it }
            }
        }
        return null
    }

    const val MERGE_WINDOW_MS = 30 * 60 * 1000L

    /**
     * One purchase is often reported twice (the bank and Google Wallet, say). Returns the earlier sighting
     * when [app] is a different app reporting the same amount within [windowMs]. The same app twice is two payments.
     */
    fun mergeTarget(recent: List<Seen>, app: String, cents: Int, now: Long, windowMs: Long = MERGE_WINDOW_MS): Seen? =
        recent.lastOrNull { it.cents == cents && it.app != app && now - it.at in 0..windowMs }

    /** The key shop rules are stored under: lower case, single spaces. Must match AppDatabase.ruleKey in the Flutter app. */
    fun shopKey(shop: String): String = shop.lowercase().replace(spaces, " ").trim()

    /** cash | debit | ewallet | credit_card, or null when it is a card we have not been told about yet. */
    fun payType(kind: String, card: String?, cards: Map<String, String>): String? = when (kind) {
        "wallet" -> "ewallet"
        "card" -> card?.let { cards[it.lowercase()] }
        else -> "debit"
    }

    fun payLabel(type: String?): String? = when (type) {
        "ewallet" -> "E-wallet"
        "debit" -> "Debit"
        "credit_card" -> "Credit card"
        "cash" -> "Cash"
        else -> null
    }

    /** Hides long numbers (account, card, reference, codes) before anything is written to the log. */
    fun mask(s: String, strict: Boolean): String = s.replace(Regex(if (strict) "\\d{4,}" else "\\d{6,}"), "#")
}
