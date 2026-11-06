import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api.dart';
import 'ledger.dart' show syncLedger;
import 'notifications.dart';
import 'recurring_poster.dart';
import 'scan_service.dart';
import 'db.dart';
import '../core/time.dart';

final dbProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final authStoreProvider = Provider<AuthStore>((ref) => AuthStore());

enum AuthStatus { unknown, signedOut, signedIn }

class AuthController extends Notifier<AuthStatus> {
  @override
  AuthStatus build() {
    _init();
    return AuthStatus.unknown;
  }

  Future<void> _init() async {
    final t = await ref.read(authStoreProvider).load();
    state = t == null ? AuthStatus.signedOut : AuthStatus.signedIn;
  }

  Future<void> login(String password, {String? code}) async {
    final token = await ref.read(apiProvider).login(password, code: code);
    await ref.read(authStoreProvider).save(token);
    state = AuthStatus.signedIn;
  }

  Future<void> logout() async {
    await ref.read(authStoreProvider).clear();
    state = AuthStatus.signedOut;
  }
}

final authProvider = NotifierProvider<AuthController, AuthStatus>(AuthController.new);

final apiProvider = Provider<ApiClient>((ref) {
  return ApiClient(ref.read(authStoreProvider), onUnauthorized: () => ref.read(authProvider.notifier).logout());
});

final scanServiceProvider = Provider<ScanService>((ref) => ScanService(ref.read(apiProvider)));

// ---- sync ----

class SyncState {
  const SyncState({this.running = false, this.lastSyncAt, this.error});
  final bool running;
  final DateTime? lastSyncAt;
  final String? error;
  SyncState copyWith({bool? running, DateTime? lastSyncAt, String? error, bool clearError = false}) =>
      SyncState(running: running ?? this.running, lastSyncAt: lastSyncAt ?? this.lastSyncAt, error: clearError ? null : (error ?? this.error));
}

class SyncController extends Notifier<SyncState> {
  bool _busy = false;
  bool _again = false;

  @override
  SyncState build() {
    final sub = Connectivity().onConnectivityChanged.listen((results) {
      if (results.any((r) => r != ConnectivityResult.none) && ref.read(authProvider) == AuthStatus.signedIn) run();
    });
    ref.onDispose(sub.cancel);
    return const SyncState();
  }

  /// Push local changes, then pull. Safe to call often; overlapping calls are merged.
  Future<void> run() async {
    if (_busy) {
      _again = true;
      return;
    }
    _busy = true;
    state = state.copyWith(running: true, clearError: true);
    try {
      do {
        _again = false;
        await _pushAll();
        await _pull();
        if (await postDueRecurring(ref.read(dbProvider)) > 0) _again = true; // push what was just posted
      } while (_again);
      state = state.copyWith(running: false, lastSyncAt: DateTime.now(), clearError: true);
    } on ApiException catch (e) {
      state = state.copyWith(running: false, error: e.isNetwork ? 'Offline' : e.message);
    } catch (e) {
      state = state.copyWith(running: false, error: 'Sync failed');
    } finally {
      _busy = false;
    }
  }

  Future<void> _pushAll() async {
    final db = ref.read(dbProvider);
    final api = ref.read(apiProvider);
    for (final op in await db.pendingOpsInOrder()) {
      try {
        if (op.entityId.startsWith(AppDatabase.billOpPrefix)) {
          final id = op.entityId.substring(AppDatabase.billOpPrefix.length);
          if (op.op == 'delete') {
            await api.deleteBill(id);
          } else {
            final b = await db.getBill(id);
            if (b != null) {
              await api.putBill(id, {'name': b.name, 'kind': b.kind, 'due_date': b.dueDate, 'amount_cents': b.amountCents, 'paid_at': b.paidAt});
            }
          }
        } else if (op.entityId.startsWith(AppDatabase.recurringOpPrefix)) {
          final id = op.entityId.substring(AppDatabase.recurringOpPrefix.length);
          if (op.op == 'delete') {
            await api.deleteRecurring(id);
          } else {
            final r = await db.getRecurring(id);
            if (r != null) {
              await api.putRecurring(id, {
                'title': r.title,
                'direction': r.direction,
                'amount_cents': r.amountCents,
                'category_id': r.categoryId,
                'payment_type': r.paymentType,
                'day_of_month': r.dayOfMonth,
                'counts_toward_cap': r.countsTowardCap ? 1 : 0,
                'active': r.active ? 1 : 0,
                'last_posted': r.lastPosted,
              });
            }
          }
        } else if (op.op == 'delete') {
          await api.deleteTransaction(op.entityId);
        } else {
          final t = await db.getTxn(op.entityId);
          if (t != null) await api.putTransaction(t.id, _body(t, await db.getItems(t.id)));
        }
        await db.clearOp(op.seq);
      } on ApiException catch (e) {
        if (e.isNetwork || e.status == 401) rethrow; // try again later
        // The server says this change is invalid. Retrying forever would block everything behind it.
        await db.clearOp(op.seq);
        state = state.copyWith(error: 'One change was rejected: ${e.message}');
      }
    }
  }

  Map<String, dynamic> _body(Txn t, List<TxnItem> items) => {
        'spent_at': t.spentAt,
        'merchant': t.merchant,
        'amount_cents': t.amountCents,
        'receipt_total_cents': t.receiptTotalCents,
        'tax_cents': t.taxCents,
        'direction': t.direction,
        'category_id': t.categoryId,
        'payment_type': t.paymentType,
        'counts_toward_cap': t.countsTowardCap ? 1 : 0,
        'note': t.note,
        'source': t.source,
        'reference': t.reference,
        'confidence': t.confidence,
        'created_at': t.createdAt,
        'updated_at': t.updatedAt,
        'deleted_at': t.deletedAt,
        'items': [for (final i in items) {'id': i.id, 'name': i.name, 'price_cents': i.priceCents, 'included': i.included}],
      };

  Future<void> _pull() async {
    final db = ref.read(dbProvider);
    final api = ref.read(apiProvider);

    final cats = await api.categories();
    await db.replaceCategories([
      for (final c in cats)
        CategoriesCompanion.insert(id: Value((c as Map)['id'] as int), name: c['name'] as String, kind: c['kind'] as String, sortOrder: Value((c['sort_order'] ?? 0) as int)),
    ]);
    final settings = await api.settings();
    for (final e in settings.entries) {
      await db.setKv('setting.${e.key}', '${e.value}');
    }

    // Overlap the cursor by a minute: re-applying a row is harmless, missing one is not.
    final cursor = await db.getKv('meta.pull_cursor');
    final since = cursor == null ? null : DateTime.parse(cursor).subtract(const Duration(minutes: 1)).toUtc().toIso8601String();
    final remote = await api.transactionsSince(since);
    var newest = cursor;
    for (final r in remote) {
      final m = r as Map<String, dynamic>;
      final id = m['id'] as String;
      final updatedAt = m['updated_at'] as String;
      if (newest == null || updatedAt.compareTo(newest) > 0) newest = updatedAt;
      if (await db.hasPending(id)) continue; // a local edit is waiting; the server will sort out the winner
      final local = await db.getTxn(id);
      if (local != null && local.updatedAt.compareTo(updatedAt) >= 0) continue;
      final capFlag = m['counts_toward_cap'];
      await db.saveTxnFromServer(
        TxnsCompanion(
          id: Value(id),
          spentAt: Value(m['spent_at'] as String),
          merchant: Value(m['merchant'] as String),
          amountCents: Value(m['amount_cents'] as int),
          receiptTotalCents: Value(m['receipt_total_cents'] as int?),
          taxCents: Value((m['tax_cents'] ?? 0) as int),
          direction: Value(m['direction'] as String),
          categoryId: Value(m['category_id'] as int),
          paymentType: Value(m['payment_type'] as String),
          countsTowardCap: Value(capFlag == true || capFlag == 1),
          note: Value(m['note'] as String?),
          source: Value(m['source'] as String),
          reference: Value(m['reference'] as String?),
          confidence: Value((m['confidence'] as num?)?.toDouble()),
          createdAt: Value(m['created_at'] as String),
          updatedAt: Value(updatedAt),
          deletedAt: Value(m['deleted_at'] as String?),
        ),
        [
          for (final i in (m['items'] as List<dynamic>? ?? const []))
            TxnItemsCompanion.insert(id: (i as Map)['id'] as String, txnId: id, name: i['name'] as String, priceCents: i['price_cents'] as int, included: Value(i['included'] == true || i['included'] == 1)),
        ],
      );
    }
    final remoteBills = await api.bills();
    final billIds = <String>{};
    for (final raw in remoteBills) {
      final b = raw as Map<String, dynamic>;
      final id = b['id'] as String;
      billIds.add(id);
      if (await db.hasPending('${AppDatabase.billOpPrefix}$id')) continue;
      await db.saveBillFromServer(BillsCompanion(
        id: Value(id),
        name: Value(b['name'] as String),
        kind: Value(b['kind'] as String),
        dueDate: Value(b['due_date'] as String),
        amountCents: Value(b['amount_cents'] as int),
        paidAt: Value(b['paid_at'] as String?),
      ));
    }
    await db.removeBillsNotIn(billIds);

    final remoteRecurring = await api.recurring();
    final recurringIds = <String>{};
    for (final raw in remoteRecurring) {
      final r = raw as Map<String, dynamic>;
      final id = r['id'] as String;
      recurringIds.add(id);
      if (await db.hasPending('${AppDatabase.recurringOpPrefix}$id')) continue;
      await db.saveRecurringFromServer(RecurringItemsCompanion(
        id: Value(id),
        title: Value(r['title'] as String),
        direction: Value(r['direction'] as String),
        amountCents: Value(r['amount_cents'] as int),
        categoryId: Value(r['category_id'] as int),
        paymentType: Value(r['payment_type'] as String),
        dayOfMonth: Value(r['day_of_month'] as int),
        countsTowardCap: Value(r['counts_toward_cap'] == true || r['counts_toward_cap'] == 1),
        active: Value(r['active'] == true || r['active'] == 1),
        lastPosted: Value(r['last_posted'] as String?),
      ));
    }
    await db.removeRecurringNotIn(recurringIds);
    try {
      await syncLedger(db, api);
    } on ApiException catch (e) {
      if (e.status != 404) rethrow; // an older server without the friends ledger: nothing to sync
    }
    if (newest != null) await db.setKv('meta.pull_cursor', newest);
    await db.setKv('meta.last_sync', nowIso());
  }
}

final syncProvider = NotifierProvider<SyncController, SyncState>(SyncController.new);

// ---- data streams for the UI ----
final txnsProvider = StreamProvider<List<Txn>>((ref) => ref.watch(dbProvider).watchTxns());
final recentTxnsProvider = StreamProvider<List<Txn>>((ref) => ref.watch(dbProvider).watchTxns(limit: 6));
final txnProvider = StreamProvider.family<Txn?, String>((ref, id) => ref.watch(dbProvider).watchTxn(id));
final itemsProvider = StreamProvider.family<List<TxnItem>, String>((ref, id) => ref.watch(dbProvider).watchItems(id));
final categoriesProvider = StreamProvider<List<Cat>>((ref) => ref.watch(dbProvider).watchCategories());
final capCentsProvider = StreamProvider<int>((ref) => ref.watch(dbProvider).watchCapCents());
final pendingCountProvider = StreamProvider<int>((ref) => ref.watch(dbProvider).watchPendingCount());
/// Starts reminders. Read it once from Home; it then rebuilds the schedule whenever bills, spending or the cap change.
final notificationsProvider = Provider<NotificationService>((ref) {
  final svc = NotificationService(ref.read(dbProvider));
  Timer? debounce;
  void queue() {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 800), () => svc.refresh().catchError((_) {}));
  }

  svc.init().then((_) async {
    final db = ref.read(dbProvider);
    if (await db.getKv('meta.asked_notifications') == null) {
      await db.setKv('meta.asked_notifications', '1');
      await svc.requestPermission();
    }
    queue();
  }).catchError((_) {});
  ref.listen(billsProvider, (_, _) => queue());
  ref.listen(weekSpentProvider, (_, _) => queue());
  ref.listen(capCentsProvider, (_, _) => queue());
  ref.listen(recentTxnsProvider, (_, _) => queue()); // income and SPayLater entries also count as "logged today"
  ref.onDispose(() => debounce?.cancel());
  return svc;
});

final spaylaterMonthProvider = StreamProvider.family<int, String>((ref, monthStart) => ref.watch(dbProvider).watchSpaylaterMonth(monthStart));
final recurringProvider = StreamProvider<List<RecurringItem>>((ref) => ref.watch(dbProvider).watchRecurring());
final billsProvider = StreamProvider<List<Bill>>((ref) => ref.watch(dbProvider).watchBills());
final weekDailyProvider = StreamProvider<Map<String, int>>((ref) {
  final today = todayKL();
  return ref.watch(dbProvider).watchDailyCapSpent(mondayOf(today), addDays(mondayOf(today), 6));
});
final weekSpentProvider = StreamProvider<int>((ref) {
  final today = todayKL();
  return ref.watch(dbProvider).watchCapSpent(mondayOf(today), addDays(mondayOf(today), 6));
});


