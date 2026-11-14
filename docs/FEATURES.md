# Features

## Capture

**Receipt scan.** Photograph a receipt; text is read on the phone and structured by the server (or by offline rules when there is no connection). The review screen shows every line as quantity x unit price, lets you edit names, quantities and prices, and lets you edit or add tax and service charge. A red warning appears when items plus charges differ from the receipt total by more than 10 sen. A duplicate check asks before saving something that looks like an entry you already have (same reference, or same amount at the same shop within 36 hours).

**Payment detection.** Turn on Settings > Detect payments and Cukup notices when TNG eWallet, ShopeePay, Grab, Google Wallet or a bank app (AmBank, UOB, HSBC, CIMB, GXBank, Ryt Bank, HLB) reports a payment, including bank text messages. A banner drops from the top of the screen with the amount and shop, the category Cukup would use, how it was paid, and two buttons: Save and Delete. **Nothing is recorded until you tap Save.** Tapping the banner itself opens a Confirm sheet where the amount, shop, category, payment type and the weekly-cap switch can be changed first. Anything not answered waits in a "Did you pay this?" card on Home.

- **Google Wallet taps** carry the shop name and the card. The first time a card appears the banner asks Credit or Debit and remembers the answer for that card.
- **One purchase, one prompt.** A card payment is often reported by both the bank and Google Wallet. A second app reporting the same amount within 30 minutes is merged into the first, and fills in the shop name if the first one had none.
- **Ignored:** money coming in, top-ups, codes, adverts and failed payments.
- **Saved straight away.** Tapping Save on the banner creates the entry in the background, updates the home-screen widget, re-checks the cap alert and syncs, without opening the app. If Android will not run the background step, the entry is created the next time the app opens instead.
- **No doubles:** a saved entry uses a fixed id, so the same detection can never be saved twice.
- **Transparent:** Settings shows exactly what was read, merged and skipped, with long numbers hidden, and can share that list to help tune the rules.

**Screenshot import.** Share a Touch 'n Go or bank payment screenshot to Cukup from the Android share sheet. Amount, payee, reference and date are filled in on the Review screen. This works without the server.

**Quick add.** Tap one of your most-used shops (or type one), key in the amount, pick a category and save. The category is learned from what you chose last time at that shop.

**Manual entry.** Add or edit an entry by hand, with category, payment type and note.

**Counts toward weekly cap.** Add, Quick add, Check and save and the Confirm sheet have a switch for whether an entry counts toward the weekly cap. Its starting position comes from the category (off for Bills by default), and your own choice is kept when you edit. SPayLater purchases never count, because they are repaid through the bill schedule.

**Custom categories.** Settings > Categories lists spending and income categories. Add your own, rename, drag to reorder, and set whether each one counts toward the weekly cap. Deleting a category moves its entries, repeating items and shop rules to Other (or Other income), so nothing is lost. Categories live on the server, so changes need a connection.

## Plan

**Weekly cap.** A weekly limit with a progress view, an even-pace line (cap / 7) and a "safe to spend per day" figure. Overspending carries forward into later weeks, at most a fixed share of the base cap per week; the switch is in Settings.

**Savings sweep.** When a week finishes under the cap, Cukup offers to move the difference toward a savings goal. Goals and progress show on the Bills screen.

**Bills.** SPayLater and other bills with due dates. Purchases on SPayLater fall due on the 1st of the following month.

**Recurring.** Rent, salary and subscriptions that add themselves each month. After the app has been closed for a while it posts every missed month (up to 12) exactly once, and an entry you delete stays deleted.

**Insights.** Income and spending for a chosen period, a donut by category, an 8-week trend and the entries behind each number.

**Month in review.** One screen per month, reachable from Insights: what you spent and how that compares with the month before, money in, what you kept, the top categories with their share, the biggest purchase, how many weeks finished at or under the cap, what was set aside for your goal, and what friends still owe. A reminder on the 1st at 9am opens it on the month that just ended; it has its own switch in Settings.

**Search and filters.** Activity has a search box (shop, note or category), chips for spent / income and category, and a Filters sheet for period (this week, this month, last month or picked dates), payment type and "only outside the weekly cap". When anything is narrowed, a line shows how many entries match and their totals.

## Friends and shared bills

**Split a receipt.** For each item, tap the people who had it. Several people on one item share it evenly. Quantities are split per unit (three plates of rice can go to three different people). Mark a line as a treat and the friend owes nothing, while it counts toward your own spending.

**Split without a receipt.** On Quick add, pick friends and split evenly, with the same Treat option.

**Fair charges.** Tax, service charge and rounding are shared in proportion to what each person had, so all shares add up to the receipt total exactly.

**Only your share counts.** Your transaction amount, and the weekly cap, use only your share.

**Ledger.** Each friend has a balance, a list of open debts, and recorded payments (applied to the oldest debt first). A friend's WhatsApp number can be saved, picked from the phone contacts or typed.

**Bound to the receipt.** Editing a saved receipt restores who had what and recalculates the debts when you save. Deleting a transaction removes its debts, and Undo restores both.

**Collect.** One tap builds a reminder message with the amount, the bills it covers and your pay link, shares your payment QR, and opens the friend's WhatsApp chat. If a friend pays you and you import their payment screenshot, "A friend paid me" records it against them.

**Sync.** The ledger syncs to your server as one document, so a reinstall or a new phone keeps it.

## Phone integration

- Home-screen widget showing the cap and this week's spend
- Quick add from a Quick Settings tile (swipe down, one tap) or the launcher shortcut
- Local notifications: bills due, daily nudge, weekly summary, cap alerts (scheduled on the device, so they work offline)
- Fingerprint or PIN app lock
- CSV export through the share sheet
- In-app updates from a public release feed

## Offline behaviour

**What survives a new phone.** Entries, bills, repeating items, categories and the friends ledger always synced. The savings goal and sweeps, shop-to-category rules, remembered cards, reminder switches, the carry-over switch and the pay link now sync too. App lock, notification access and the detection log stay on the phone on purpose.

Everything except server sync and AI receipt parsing works without a connection. Receipts fall back to the on-device parser, and changes sync when the phone is next online.
