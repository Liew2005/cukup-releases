package my.cukup.cukup

/**
 * Decides whether a notification from a payment app is money going out, and reads the amount.
 * Pure Kotlin, no Android classes. The same rules live in lib/core/pay_notif.dart (where they are unit tested):
 * change both together.
 */
object PaymentDetect {
    /** kind: wallet | bank | sms */
    data class Source(val name: String, val kind: String)

    private val smsPackages = setOf(
        "com.google.android.apps.messaging", "com.android.mms", "com.android.messaging", "com.samsung.android.messaging",
    )

    private val bankWords = Regex("\\b(uob|hsbc|cimb|gx ?bank|ryt|hong leong|hlb)\\b", RegexOption.IGNORE_CASE)

    /** Which payment app a notification came from, or null for every other app. */
    fun sourceFor(pkg: String, label: String): Source? {
        val p = pkg.lowercase()
        val l = label.lowercase().trim()
        if (p in smsPackages) return Source("SMS", "sms")
        return when {
            p.contains("tngdigital") || l.contains("touch 'n go") || l.contains("touch n go") || l.startsWith("tng") -> Source("TNG eWallet", "wallet")
            p.contains("shopee") || l.startsWith("shopee") -> Source("ShopeePay", "wallet")
            p.contains("grabtaxi") || l == "grab" -> Source("Grab", "wallet")
            p.contains("uob") || l.startsWith("uob") -> Source("UOB", "bank")
            p.contains("hsbc") || l.startsWith("hsbc") -> Source("HSBC", "bank")
            p.contains("cimb") || l.startsWith("cimb") -> Source("CIMB", "bank")
            p.contains("gxbank") || p.contains("gxb.") || l.startsWith("gxbank") || l.startsWith("gx bank") -> Source("GXBank", "bank")
            p.contains("rytbank") || p.endsWith(".ryt") || p.contains(".ryt.") || l.startsWith("ryt") -> Source("Ryt Bank", "bank")
            p.contains("hongleong") || p.contains("hlb") || l.contains("hong leong") || l.startsWith("hlb") -> Source("HLB", "bank")
            else -> null
        }
    }

    private val amount = Regex("(?:RM|MYR)\\s?([0-9]{1,3}(?:,[0-9]{3})+(?:\\.[0-9]{1,2})?|[0-9]+(?:\\.[0-9]{1,2})?)", RegexOption.IGNORE_CASE)

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

    /** Whole cents paid, or null when this is not a payment. */
    fun read(source: Source, title: String, text: String): Int? {
        val all = "$title\n$text"
        if (source.kind == "sms" && !bankWords.containsMatchIn(all)) return null
        if (notSpend.containsMatchIn(all) || !spend.containsMatchIn(all)) return null
        val m = amount.find(all) ?: return null
        val v = m.groupValues[1].replace(",", "").toDoubleOrNull() ?: return null
        val cents = Math.round(v * 100).toInt()
        return if (cents in 1..100_000_000) cents else null
    }

    /** Hides long numbers (account, card, reference, codes) before anything is written to the log. */
    fun mask(s: String, strict: Boolean): String = s.replace(Regex(if (strict) "\\d{4,}" else "\\d{6,}"), "#")
}
