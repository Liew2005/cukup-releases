import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../core/config.dart';
import '../core/ledger.dart';
import '../core/time.dart';
import 'api.dart';
import 'db.dart';
import 'providers.dart';

const _docKey = 'ledger.doc';
const _stampKey = 'ledger.updated';
const _dirtyKey = 'ledger.dirty';
const _payLinkKey = 'ledger.paylink';

Future<Ledger> loadLedger(AppDatabase db) async => Ledger.decode(await db.getKv(_docKey), updatedAt: await db.getKv(_stampKey) ?? '');

Future<void> _saveLocal(AppDatabase db, Ledger l, {required bool dirty}) async {
  await db.setKv(_docKey, l.encode());
  await db.setKv(_stampKey, l.updatedAt);
  await db.setKv(_dirtyKey, dirty ? '1' : '0');
}

/// Two-way sync of the friends ledger. The phone is the only writer, so the newest copy wins:
/// push when this phone changed it, pull when the server has a newer one. Returns true if the local copy changed.
Future<bool> syncLedger(AppDatabase db, ApiClient api) async {
  final local = await loadLedger(db);
  final dirty = await db.getKv(_dirtyKey) == '1';
  final remote = await api.ledger();
  final remoteDoc = remote['doc'] as String?;
  final remoteAt = remote['updated_at'] as String?;

  if (dirty || (remoteDoc == null && local.updatedAt.isNotEmpty)) {
    if (local.updatedAt.isEmpty) return false;
    final res = await api.putLedger(local.encode(), local.updatedAt);
    if (res['stored'] == true) {
      await db.setKv(_dirtyKey, '0');
      return false;
    }
    final newerDoc = res['doc'] as String?;
    if (newerDoc == null) return false;
    await _saveLocal(db, Ledger.decode(newerDoc, updatedAt: res['updated_at'] as String? ?? ''), dirty: false);
    return true;
  }
  if (remoteDoc != null && remoteAt != null && remoteAt.compareTo(local.updatedAt) > 0) {
    await _saveLocal(db, Ledger.decode(remoteDoc, updatedAt: remoteAt), dirty: false);
    return true;
  }
  return false;
}

/// Pay link added to reminder messages. Set in Settings; starts as the link given when the app was built.
Future<String> loadPayLink(AppDatabase db) async => await db.getKv(_payLinkKey) ?? defaultPayLink;
Future<void> savePayLink(AppDatabase db, String link) => db.setKv(_payLinkKey, link.trim());

/// What a deleted receipt took out of the ledger, so Undo can put it back.
class LedgerSnapshot {
  LedgerSnapshot(this.txnId, this.debts, this.split);
  final String txnId;
  final List<Debt> debts;
  final Map<String, dynamic>? split;
}

class LedgerController extends Notifier<Ledger> {
  static const _uuid = Uuid();

  @override
  Ledger build() {
    // A sync may have brought a newer copy from the server.
    ref.listen(syncProvider, (prev, next) {
      if (prev?.lastSyncAt != next.lastSyncAt) reload();
    });
    reload();
    return Ledger();
  }

  Future<void> reload() async => state = await loadLedger(ref.read(dbProvider));

  Future<void> _commit(Ledger l) async {
    l.updatedAt = nowIso();
    state = l;
    await _saveLocal(ref.read(dbProvider), l, dirty: true);
    ref.read(syncProvider.notifier).run();
  }

  Ledger _copy() => Ledger(friends: [...state.friends], debts: [...state.debts], payments: [...state.payments], splits: {...state.splits});

  /// A shared receipt was saved or edited: replace what friends owe for it, and remember how it was split.
  /// Pass no [debts] and a null [split] to clear it (everyone dropped off the bill).
  Future<void> saveSplit(String txnId, Map<String, dynamic>? split, List<Debt> debts) async {
    final had = state.debts.any((d) => d.txnId == txnId) || state.splits.containsKey(txnId);
    if (!had && debts.isEmpty && split == null) return; // a receipt that was never shared: nothing to do
    final l = _copy()..debts.removeWhere((d) => d.txnId == txnId);
    l.debts.addAll(debts);
    if (split == null) {
      l.splits.remove(txnId);
    } else {
      l.splits[txnId] = split;
    }
    await _commit(l);
  }

  /// The receipt was deleted: what friends owe for it goes too. Returns what was removed so Undo can bring it back.
  Future<LedgerSnapshot?> removeForTxn(String txnId) async {
    final gone = state.debts.where((d) => d.txnId == txnId).toList();
    final split = state.splits[txnId];
    if (gone.isEmpty && split == null) return null;
    final l = _copy()
      ..debts.removeWhere((d) => d.txnId == txnId)
      ..splits.remove(txnId);
    await _commit(l);
    return LedgerSnapshot(txnId, gone, split);
  }

  Future<void> restoreSnapshot(LedgerSnapshot s) async {
    final l = _copy()..debts.addAll(s.debts);
    if (s.split != null) l.splits[s.txnId] = s.split!;
    await _commit(l);
  }

  Future<Friend> addFriend(String name, {String? phone}) async {
    final f = Friend(id: _uuid.v4(), name: name.trim(), phone: phone?.trim());
    await _commit(_copy()..friends.add(f));
    return f;
  }

  Future<void> updateFriend(String id, {required String name, String? phone}) async {
    final l = _copy();
    final i = l.friends.indexWhere((f) => f.id == id);
    if (i < 0) return;
    l.friends[i] = Friend(id: id, name: name.trim(), phone: phone?.trim());
    await _commit(l);
  }

  /// Removes the friend and everything they owe or paid.
  Future<void> deleteFriend(String id) async {
    final l = _copy();
    l.friends.removeWhere((f) => f.id == id);
    l.debts.removeWhere((d) => d.friendId == id);
    l.payments.removeWhere((p) => p.friendId == id);
    await _commit(l);
  }

  Future<void> addDebts(List<Debt> debts) async {
    if (debts.isEmpty) return;
    await _commit(_copy()..debts.addAll(debts));
  }

  Future<void> deleteDebt(String id) async => _commit(_copy()..debts.removeWhere((d) => d.id == id));

  Future<void> addPayment(String friendId, int cents, {String? date, String? note}) async {
    if (cents <= 0) return;
    await _commit(_copy()..payments.add(Payment(id: _uuid.v4(), friendId: friendId, date: date ?? todayKL(), cents: cents, note: note)));
  }

  Future<void> deletePayment(String id) async => _commit(_copy()..payments.removeWhere((p) => p.id == id));
}

final ledgerProvider = NotifierProvider<LedgerController, Ledger>(LedgerController.new);
