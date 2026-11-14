// Payments noticed from wallet, bank and Google Wallet notifications. Pure Dart, no Flutter.
//
// The Android listener decides what is a payment and reads the amount, shop and card
// (PaymentDetect.kt, tested there). This file only reads the list it leaves behind.
import 'dart:convert';

/// A payment the listener noticed.
class Detected {
  Detected({required this.id, required this.at, required this.app, required this.kind, required this.title, required this.text, required this.cents, this.shop, this.card});
  final String id;
  final int at; // epoch milliseconds
  final String app; // "TNG eWallet", "CIMB", "Google Wallet", ...
  final String kind; // wallet | bank | sms | card
  final String title;
  final String text;
  final int cents;
  String? shop; // read from the wording; a second app reporting the same payment can fill it in
  String? card; // "AmBank BonusLink Visa", for Google Wallet taps
  final List<String> alsoSeenBy = []; // other apps that reported this same payment
  String? chosenPay; // credit_card | debit picked on the banner the first time a card was seen
  String via = 'app'; // where Save was tapped: banner | app

  DateTime get _kl => DateTime.fromMillisecondsSinceEpoch(at, isUtc: true).add(const Duration(hours: 8));
  static String _two(int n) => n.toString().padLeft(2, '0');

  /// YYYY-MM-DD in Malaysia time.
  String get date => '${_kl.year.toString().padLeft(4, '0')}-${_two(_kl.month)}-${_two(_kl.day)}';

  /// HH:mm in Malaysia time.
  String get time => '${_two(_kl.hour)}:${_two(_kl.minute)}';

  /// What to file it under when the notification names no shop.
  String get merchant => shop ?? app;

  /// cash | debit | ewallet | credit_card. [cards] remembers what each card is; null means this card is new, so ask.
  String? paymentType(Map<String, String> cards) => switch (kind) {
        'wallet' => 'ewallet',
        'card' => chosenPay ?? (card == null ? null : cards[card!.toLowerCase()]),
        _ => 'debit',
      };

  /// A fixed entry id, so saving the same detection twice can never make two entries.
  String get txnId => 'det-$id';
}

/// One line of the log shown in Settings.
class LogLine {
  const LogLine({required this.kind, required this.at, required this.app, required this.title, required this.text, this.cents});
  final String kind; // pay | skip | merge
  final int at;
  final String app;
  final String title;
  final String text;
  final int? cents;
}

class Inbox {
  const Inbox({required this.pending, required this.toSave, required this.renamed, required this.log});
  final List<Detected> pending; // waiting for Save or Delete, newest first
  final List<Detected> toSave; // Save was tapped on the banner while the app was closed
  final List<Detected> renamed; // already dealt with, but a second app has since supplied the shop name
  final List<LogLine> log; // everything seen, newest first
}

/// Reads the listener's file. [done] holds ids the app has already saved or dismissed.
Inbox readInbox(String content, Set<String> done) {
  final pays = <String, Detected>{};
  final acts = <String, String>{};
  final named = <String>{}; // ids whose shop came from a later merge
  final log = <LogLine>[];
  for (final raw in const LineSplitter().convert(content)) {
    if (raw.trim().isEmpty) continue;
    final Object? j;
    try {
      j = jsonDecode(raw);
    } catch (_) {
      continue; // a half-written line
    }
    if (j is! Map) continue;
    final Map<dynamic, dynamic> m = j;
    final k = j['k'];
    final t = j['t'] is int ? j['t'] as int : 0;
    String? str(String key) => m[key] is String && (m[key] as String).isNotEmpty ? m[key] as String : null;
    final id = str('id');
    if (k == 'act' && id != null && str('a') != null) {
      acts[id] = str('a')!;
      final d = pays[id];
      if (d != null) {
        d.chosenPay = str('pay') ?? d.chosenPay;
        d.via = str('via') ?? 'banner';
      }
    } else if (k == 'pay' && id != null && j['cents'] is int) {
      final d = Detected(id: id, at: t, app: str('app') ?? '', kind: str('kind') ?? 'bank', title: str('title') ?? '', text: str('text') ?? '', cents: j['cents'] as int, shop: str('shop'), card: str('card'));
      pays[id] = d;
      log.add(LogLine(kind: 'pay', at: t, app: d.app, title: d.title, text: d.text, cents: d.cents));
    } else if (k == 'merge' && id != null) {
      final d = pays[id];
      if (d == null) continue;
      final app = str('app') ?? '';
      if (app.isNotEmpty && !d.alsoSeenBy.contains(app)) d.alsoSeenBy.add(app);
      if (d.shop == null && str('shop') != null) {
        d.shop = str('shop');
        named.add(id);
      }
      d.card ??= str('card');
      log.add(LogLine(kind: 'merge', at: t, app: app, title: '', text: 'Same payment as the one from ${d.app}', cents: d.cents));
    } else if (k == 'skip') {
      log.add(LogLine(kind: 'skip', at: t, app: str('app') ?? '', title: str('title') ?? '', text: str('text') ?? ''));
    }
  }
  final open = pays.values.where((d) => !done.contains(d.id)).toList()..sort((a, b) => b.at.compareTo(a.at));
  return Inbox(
    pending: [for (final d in open) if (!acts.containsKey(d.id)) d],
    toSave: [for (final d in open) if (acts[d.id] == 'save') d],
    renamed: [for (final id in named) if (done.contains(id)) pays[id]!],
    log: log.reversed.toList(),
  );
}
