import 'dart:convert';

/// Who owes you what. Pure data and maths; storage and sync live in data/ledger.dart.

class Friend {
  Friend({required this.id, required this.name, this.phone});
  final String id;
  String name;
  String? phone;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, if (phone != null && phone!.isNotEmpty) 'phone': phone};
  factory Friend.fromJson(Map<String, dynamic> j) => Friend(id: j['id'] as String, name: j['name'] as String, phone: j['phone'] as String?);
}

/// Money a friend owes you for one bill.
class Debt {
  Debt({required this.id, required this.friendId, required this.date, required this.title, required this.cents, this.items = const [], this.txnId});
  final String id;
  final String friendId;
  final String date; // YYYY-MM-DD of the bill
  final String title; // usually the shop
  final int cents;
  final List<String> items; // what they had, for the reminder message
  final String? txnId;

  Map<String, dynamic> toJson() => {'id': id, 'friend': friendId, 'date': date, 'title': title, 'cents': cents, 'items': items, if (txnId != null) 'txn': txnId};
  factory Debt.fromJson(Map<String, dynamic> j) => Debt(
        id: j['id'] as String,
        friendId: j['friend'] as String,
        date: j['date'] as String,
        title: j['title'] as String,
        cents: j['cents'] as int,
        items: [for (final i in (j['items'] as List<dynamic>? ?? const [])) '$i'],
        txnId: j['txn'] as String?,
      );
}

/// Money a friend paid you back.
class Payment {
  Payment({required this.id, required this.friendId, required this.date, required this.cents, this.note});
  final String id;
  final String friendId;
  final String date;
  final int cents;
  final String? note;

  Map<String, dynamic> toJson() => {'id': id, 'friend': friendId, 'date': date, 'cents': cents, if (note != null && note!.isNotEmpty) 'note': note};
  factory Payment.fromJson(Map<String, dynamic> j) => Payment(id: j['id'] as String, friendId: j['friend'] as String, date: j['date'] as String, cents: j['cents'] as int, note: j['note'] as String?);
}

/// One bill and how much of it is still unpaid, after payments are applied oldest first.
class OpenDebt {
  const OpenDebt(this.debt, this.leftCents);
  final Debt debt;
  final int leftCents;
  bool get settled => leftCents <= 0;
}

class Ledger {
  Ledger({List<Friend>? friends, List<Debt>? debts, List<Payment>? payments, Map<String, Map<String, dynamic>>? splits, this.updatedAt = ''})
      : friends = friends ?? [],
        debts = debts ?? [],
        payments = payments ?? [],
        splits = splits ?? {};

  final List<Friend> friends;
  final List<Debt> debts;
  final List<Payment> payments;

  /// How each shared receipt was divided, by transaction id, so editing the receipt later can redo what friends owe.
  /// Opaque to this file: the review screen writes and reads it.
  final Map<String, Map<String, dynamic>> splits;
  String updatedAt; // ISO time of the last change, used to decide which copy wins when syncing

  Friend? friend(String id) {
    for (final f in friends) {
      if (f.id == id) return f;
    }
    return null;
  }

  /// Positive: they owe you. Negative: they paid more than they owed (credit).
  int balanceOf(String friendId) {
    final owed = debts.where((d) => d.friendId == friendId).fold<int>(0, (s, d) => s + d.cents);
    final paid = payments.where((p) => p.friendId == friendId).fold<int>(0, (s, p) => s + p.cents);
    return owed - paid;
  }

  /// Everyone's positive balance added up.
  int get totalOwed => friends.fold<int>(0, (s, f) {
        final b = balanceOf(f.id);
        return b > 0 ? s + b : s;
      });

  /// Each bill with what is left of it. Payments go to the oldest bill first.
  List<OpenDebt> openDebts(String friendId) {
    final list = debts.where((d) => d.friendId == friendId).toList()..sort((a, b) => a.date.compareTo(b.date));
    var pool = payments.where((p) => p.friendId == friendId).fold<int>(0, (s, p) => s + p.cents);
    final out = <OpenDebt>[];
    for (final d in list) {
      final use = pool < d.cents ? pool : d.cents;
      pool -= use;
      out.add(OpenDebt(d, d.cents - use));
    }
    return out;
  }

  Map<String, dynamic> toJson() => {
        'v': 1,
        'friends': [for (final f in friends) f.toJson()],
        'debts': [for (final d in debts) d.toJson()],
        'payments': [for (final p in payments) p.toJson()],
        'splits': splits,
      };

  String encode() => jsonEncode(toJson());

  factory Ledger.decode(String? text, {String updatedAt = ''}) {
    if (text == null || text.isEmpty) return Ledger(updatedAt: updatedAt);
    try {
      final j = jsonDecode(text) as Map<String, dynamic>;
      return Ledger(
        friends: [for (final f in (j['friends'] as List<dynamic>? ?? const [])) Friend.fromJson(f as Map<String, dynamic>)],
        debts: [for (final d in (j['debts'] as List<dynamic>? ?? const [])) Debt.fromJson(d as Map<String, dynamic>)],
        payments: [for (final p in (j['payments'] as List<dynamic>? ?? const [])) Payment.fromJson(p as Map<String, dynamic>)],
        splits: {for (final e in ((j['splits'] as Map<String, dynamic>?) ?? const <String, dynamic>{}).entries) e.key: Map<String, dynamic>.from(e.value as Map)},
        updatedAt: updatedAt,
      );
    } catch (_) {
      return Ledger(updatedAt: updatedAt);
    }
  }
}

/// Malaysian mobile number to the digits WhatsApp wants: 012-345 6789 and +60 12 345 6789 both become 60123456789.
String? whatsappNumber(String? raw) {
  if (raw == null) return null;
  var d = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (d.isEmpty) return null;
  if (d.startsWith('00')) d = d.substring(2);
  if (d.startsWith('0')) d = '6$d';
  return d.length >= 9 ? d : null;
}

String _rm(int cents) => 'RM ${(cents / 100).toStringAsFixed(2)}';

String _shortDate(String ymd) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final p = ymd.split('-');
  if (p.length != 3) return ymd;
  final m = int.tryParse(p[1]) ?? 1;
  return '${int.parse(p[2])} ${months[(m - 1).clamp(0, 11)]}';
}

/// The message you paste into WhatsApp. Lists each unpaid bill and what they had, so there is nothing to argue about.
String reminderMessage({required String name, required List<OpenDebt> open, String? payLink}) {
  final unpaid = open.where((o) => !o.settled).toList();
  final total = unpaid.fold<int>(0, (s, o) => s + o.leftCents);
  final b = StringBuffer();
  if (unpaid.isEmpty) return 'Hi $name, all settled. Thanks!';
  b.writeln('Hi $name! ${_rm(total)} for:');
  for (final o in unpaid) {
    final partial = o.leftCents != o.debt.cents;
    b.write('• ${_shortDate(o.debt.date)} ${o.debt.title}: ${_rm(o.leftCents)}');
    if (partial) b.write(' (left of ${_rm(o.debt.cents)})');
    b.writeln();
    if (o.debt.items.isNotEmpty) b.writeln('   ${o.debt.items.join(', ')}');
  }
  b.writeln('Includes any service charge and tax.');
  if (unpaid.length > 1) b.writeln('Total ${_rm(total)}.');
  if (payLink != null && payLink.trim().isNotEmpty) b.writeln('Pay here: ${payLink.trim()}');
  b.write('Thanks!');
  return b.toString();
}
