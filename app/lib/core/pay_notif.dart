// Payments noticed from wallet and bank notifications. Pure Dart, no Flutter.
//
// The Android listener (PaymentDetect.kt) decides what is a payment while the app is closed.
// The same rules are kept here so they can be unit tested: change both together.
import 'dart:convert';

/// A payment the listener noticed and has not been dealt with yet.
class Detected {
  const Detected({required this.id, required this.at, required this.app, required this.kind, required this.title, required this.text, required this.cents});
  final String id;
  final int at; // epoch milliseconds
  final String app; // "TNG eWallet", "CIMB", ...
  final String kind; // wallet | bank | sms
  final String title;
  final String text;
  final int cents;

  /// Shop name read from the wording, or null when it does not say.
  String? get merchant => merchantFrom(title, text);

  /// YYYY-MM-DD in Malaysia time.
  String get date {
    final d = DateTime.fromMillisecondsSinceEpoch(at, isUtc: true).add(const Duration(hours: 8));
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  /// HH:mm in Malaysia time.
  String get time {
    final d = DateTime.fromMillisecondsSinceEpoch(at, isUtc: true).add(const Duration(hours: 8));
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  /// Wallet payments are e-wallet; anything from a bank is treated as debit until you change it.
  String get paymentType => kind == 'wallet' ? 'ewallet' : 'debit';

  /// A fixed entry id, so saving the same detection twice can never make two entries.
  String get txnId => 'det-$id';
}

/// One line of the log shown in Settings.
class LogLine {
  const LogLine({required this.kind, required this.at, required this.app, required this.title, required this.text, this.cents});
  final String kind; // pay | skip
  final int at;
  final String app;
  final String title;
  final String text;
  final int? cents;
}

class Inbox {
  const Inbox({required this.pending, required this.toSave, required this.log});
  final List<Detected> pending; // waiting for Save or Ignore, newest first
  final List<Detected> toSave; // Save was tapped on the notification while the app was closed
  final List<LogLine> log; // everything seen, newest first
}

/// Reads the listener's file. [done] holds ids the app has already saved or dismissed.
Inbox readInbox(String content, Set<String> done) {
  final pays = <String, Detected>{};
  final acts = <String, String>{};
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
    final k = j['k'];
    final t = j['t'] is int ? j['t'] as int : 0;
    if (k == 'act' && j['id'] is String && j['a'] is String) {
      acts[j['id'] as String] = j['a'] as String;
    } else if (k == 'pay' && j['id'] is String && j['cents'] is int) {
      final d = Detected(id: j['id'] as String, at: t, app: '${j['app'] ?? ''}', kind: '${j['kind'] ?? 'bank'}', title: '${j['title'] ?? ''}', text: '${j['text'] ?? ''}', cents: j['cents'] as int);
      pays[d.id] = d;
      log.add(LogLine(kind: 'pay', at: t, app: d.app, title: d.title, text: d.text, cents: d.cents));
    } else if (k == 'skip') {
      log.add(LogLine(kind: 'skip', at: t, app: '${j['app'] ?? ''}', title: '${j['title'] ?? ''}', text: '${j['text'] ?? ''}'));
    }
  }
  final open = pays.values.where((d) => !done.contains(d.id)).toList()..sort((a, b) => b.at.compareTo(a.at));
  return Inbox(
    pending: [for (final d in open) if (!acts.containsKey(d.id)) d],
    toSave: [for (final d in open) if (acts[d.id] == 'save') d],
    log: log.reversed.toList(),
  );
}

final _amount = RegExp(r'(?:RM|MYR)\s?([0-9]{1,3}(?:,[0-9]{3})+(?:\.[0-9]{1,2})?|[0-9]+(?:\.[0-9]{1,2})?)', caseSensitive: false);
final _bankWords = RegExp(r'\b(uob|hsbc|cimb|gx ?bank|ryt|hong leong|hlb)\b', caseSensitive: false);
final _notSpend = RegExp(
  r'\b(received|receive|credited|cash ?back|refund(ed)?|reversal|reversed|rewards?|vouchers?|otp|tac|verification code|'
  r'top(ped)?[- ]?up|reload(ed)?|promo(tion)?s?|discounts?|% off|sale|win|earn(ed)?|claim(ed)?|statement|due|reminder|'
  r'fail(ed)?|unsuccessful|declined|rejected|request(ed|ing)?|limit|login|log in|diterima|gagal)\b',
  caseSensitive: false,
);
final _spend = RegExp(
  r'\b(paid|payment|pay|spent|purchase(d)?|debited|deducted|charged|transaction|transfer(red)?|sent|withdraw(n|al)?|'
  r'pembayaran|bayaran|dibayar|ditolak|pindahan)\b',
  caseSensitive: false,
);

/// Whole cents paid, or null when the notification is not money going out. [kind] is wallet, bank or sms.
int? readPayment(String kind, String title, String text) {
  final all = '$title\n$text';
  if (kind == 'sms' && !_bankWords.hasMatch(all)) return null;
  if (_notSpend.hasMatch(all) || !_spend.hasMatch(all)) return null;
  final m = _amount.firstMatch(all);
  if (m == null) return null;
  final v = double.tryParse(m.group(1)!.replaceAll(',', ''));
  if (v == null) return null;
  final cents = (v * 100).round();
  return cents >= 1 && cents <= 100000000 ? cents : null;
}

final _toShop = RegExp(
  r'\b(?:paid|payment|pay|spent|purchase|purchased|transaction|transfer|transferred|sent|charged|pembayaran|bayaran|dibayar)\b[^\n]{0,60}?\b(?:to|at|kepada|di)\s+(.+)',
  caseSensitive: false,
);
final _atShop = RegExp(r'(?:\bat\b|@)\s+(.+)', caseSensitive: false);
final _stop = RegExp(r'\s+(?:on|via|using|with|from|for|ref|reference|is|was|has|have|dated|at|pada|melalui|telah|berjaya)\b|\s+\d{1,2}[/:-]\d|[.,;!?(\n]|\s+(?:RM|MYR)\s?\d', caseSensitive: false);

/// The shop a payment went to, read from wording like "paid RM 5.00 to Mixue Kajang". Null when it is not said.
String? merchantFrom(String title, String text) {
  for (final src in [text, '$title $text']) {
    for (final re in [_toShop, _atShop]) {
      final m = re.firstMatch(src);
      if (m == null) continue;
      var s = m.group(1)!;
      final cut = _stop.firstMatch(s);
      if (cut != null) s = s.substring(0, cut.start);
      s = s.replaceAll(RegExp(r'\s+'), ' ').replaceAll(RegExp(r'''^["'*\s]+|["'*\s]+$'''), '');
      if (s.length > 40) s = s.substring(0, 40).trim();
      if (s.length >= 2 && RegExp(r'[A-Za-z]').hasMatch(s) && !_amount.hasMatch(s) && !RegExp(r'^(your|you|the|a|an|my|account|card|wallet)\b', caseSensitive: false).hasMatch(s)) return s;
    }
  }
  return null;
}
