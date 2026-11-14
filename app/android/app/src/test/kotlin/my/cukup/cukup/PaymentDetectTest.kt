package my.cukup.cukup

import my.cukup.cukup.PaymentDetect.Seen
import my.cukup.cukup.PaymentDetect.Source
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

class PaymentDetectTest {
    private val wallet = Source("TNG eWallet", "wallet")
    private val bank = Source("CIMB", "bank")
    private val sms = Source("SMS", "sms")
    private val gwallet = Source("Google Wallet", "card")

    @Test
    fun readsMoneyGoingOut() {
        assertEquals(1250, PaymentDetect.read(wallet, "Payment Successful", "You have paid RM 12.50 to Mixue Kajang.")?.cents)
        assertEquals(123400, PaymentDetect.read(bank, "Transaction alert", "RM1,234.00 was spent at AEON BIG on your card ending 1234")?.cents)
        assertEquals(800, PaymentDetect.read(bank, "DuitNow", "You transferred MYR 8 to KEDAI MAKAN ALI")?.cents)
        assertEquals(790, PaymentDetect.read(wallet, "Pembayaran berjaya", "Pembayaran RM7.90 kepada 99 Speedmart")?.cents)
    }

    @Test
    fun ignoresMoneyComingInCodesAdvertsAndFailures() {
        assertNull(PaymentDetect.read(wallet, "Money received", "You received RM 20.00 from Ali"))
        assertNull(PaymentDetect.read(wallet, "Reload", "Reload of RM 50.00 successful"))
        assertNull(PaymentDetect.read(bank, "OTP", "Your TAC for payment of RM 50.00 is 123456"))
        assertNull(PaymentDetect.read(wallet, "Cashback", "You earned RM 0.50 cashback on your payment"))
        assertNull(PaymentDetect.read(wallet, "Vouchers", "Pay with ShopeePay and get RM 5 off"))
        assertNull(PaymentDetect.read(bank, "Declined", "Your payment of RM 30.00 was declined"))
        assertNull(PaymentDetect.read(bank, "Hello", "Thanks for using our app"))
        assertNull(PaymentDetect.read(wallet, "Paid", "Your payment went through")) // no amount
    }

    @Test
    fun textMessagesCountOnlyFromABank() {
        assertNull(PaymentDetect.read(sms, "Ali", "I paid RM 10 for lunch"))
        assertEquals(4500, PaymentDetect.read(sms, "CIMB", "CIMB: RM 45.00 spent at SHELL on card 4321")?.cents)
        assertEquals(1500, PaymentDetect.read(sms, "62666", "AmBank: RM15.00 charged at GRAB on your card")?.cents)
    }

    @Test
    fun googleWalletTap() {
        // the notification from the phone: title is the shop, text is the amount and the card
        val hit = PaymentDetect.read(gwallet, "WENG HOE AUTO CAR SERVICE", "MYR28.00 with AmBank BonusLink Visa")
        assertNotNull(hit)
        assertEquals(2800, hit!!.cents)
        assertEquals("WENG HOE AUTO CAR SERVICE", hit.shop)
        assertEquals("AmBank BonusLink Visa", hit.card)
        assertEquals(1234567, PaymentDetect.read(gwallet, "Harvey Norman", "RM 12,345.67 with Visa 1234")?.cents)
        assertNull(PaymentDetect.read(gwallet, "Shell", "MYR50.00 with AmBank Visa was declined"))
        assertNull(PaymentDetect.read(gwallet, "Google Wallet", "Add a card to pay faster"))
    }

    @Test
    fun findsTheShop() {
        assertEquals("Mixue Kajang", PaymentDetect.merchantFrom("Payment Successful", "You have paid RM 12.50 to Mixue Kajang."))
        assertEquals("AEON BIG", PaymentDetect.merchantFrom("Transaction alert", "RM1,234.00 was spent at AEON BIG on your card ending 1234"))
        assertEquals("KK Mart", PaymentDetect.merchantFrom("", "Payment of RM5.00 to KK Mart via DuitNow QR"))
        assertEquals("99 Speedmart", PaymentDetect.merchantFrom("", "Pembayaran RM7.90 kepada 99 Speedmart berjaya"))
        assertNull(PaymentDetect.merchantFrom("Payment Successful", "RM 12.50 has been deducted"))
        assertNull(PaymentDetect.merchantFrom("", "You paid RM 3.00 to your account"))
    }

    @Test
    fun samePurchaseFromTwoAppsIsOnePayment() {
        val t = 1_000_000_000L
        val seen = listOf(Seen("a", t, "AmBank", "bank", 2800, null, null))
        assertEquals("a", PaymentDetect.mergeTarget(seen, "Google Wallet", 2800, t + 60_000)?.id) // other app, same amount, a minute later
        assertNull(PaymentDetect.mergeTarget(seen, "AmBank", 2800, t + 60_000)) // same app twice is two payments
        assertNull(PaymentDetect.mergeTarget(seen, "Google Wallet", 2900, t + 60_000)) // different amount
        assertNull(PaymentDetect.mergeTarget(seen, "Google Wallet", 2800, t + 31 * 60_000)) // too long after
    }

    @Test
    fun paymentTypeAndCards() {
        assertEquals("ewallet", PaymentDetect.payType("wallet", null, emptyMap()))
        assertEquals("debit", PaymentDetect.payType("bank", null, emptyMap()))
        assertNull(PaymentDetect.payType("card", "AmBank BonusLink Visa", emptyMap())) // not told yet: ask
        assertEquals("credit_card", PaymentDetect.payType("card", "AmBank BonusLink Visa", mapOf("ambank bonuslink visa" to "credit_card")))
        assertEquals("mixue kajang", PaymentDetect.shopKey("  Mixue   KAJANG "))
    }

    @Test
    fun hidesLongNumbers() {
        assertEquals("Ref # paid RM 12.50", PaymentDetect.mask("Ref 12345678 paid RM 12.50", false))
        assertEquals("Code # card 1234", PaymentDetect.mask("Code 123456 card 1234", false))
        assertEquals("Code # card #", PaymentDetect.mask("Code 123456 card 1234", true))
    }

    @Test
    fun knowsTheApps() {
        assertEquals("Google Wallet", PaymentDetect.sourceFor("com.google.android.apps.walletnfcrel", "Wallet")?.name)
        assertEquals("TNG eWallet", PaymentDetect.sourceFor("my.com.tngdigital.ewallet", "Touch 'n Go eWallet")?.name)
        assertEquals("AmBank", PaymentDetect.sourceFor("com.ambank.ambankonline", "AmOnline")?.name)
        assertEquals("sms", PaymentDetect.sourceFor("com.google.android.apps.messaging", "Messages")?.kind)
        assertNull(PaymentDetect.sourceFor("com.whatsapp", "WhatsApp"))
        assertNull(PaymentDetect.sourceFor("com.everything.app", "Everything")) // "ryt" inside another word must not match
    }
}
