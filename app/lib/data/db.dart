import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../core/time.dart';

part 'db.g.dart';

@DataClassName('Cat')
class Categories extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text()();
  TextColumn get kind => text()(); // spend | income
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('Txn')
class Txns extends Table {
  TextColumn get id => text()();
  TextColumn get spentAt => text()(); // YYYY-MM-DD
  TextColumn get merchant => text()();
  IntColumn get amountCents => integer()();
  IntColumn get receiptTotalCents => integer().nullable()();
  IntColumn get taxCents => integer().withDefault(const Constant(0))();
  TextColumn get direction => text().withDefault(const Constant('spend'))();
  IntColumn get categoryId => integer()();
  TextColumn get paymentType => text()();
  BoolColumn get countsTowardCap => boolean().withDefault(const Constant(true))();
  TextColumn get note => text().nullable()();
  TextColumn get source => text().withDefault(const Constant('manual'))();
  TextColumn get reference => text().nullable()();
  RealColumn get confidence => real().nullable()();
  TextColumn get createdAt => text()();
  TextColumn get updatedAt => text()();
  TextColumn get deletedAt => text().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('TxnItem')
class TxnItems extends Table {
  TextColumn get id => text()();
  TextColumn get txnId => text()();
  TextColumn get name => text()();
  IntColumn get priceCents => integer()();
  BoolColumn get included => boolean().withDefault(const Constant(true))();
  @override
  Set<Column> get primaryKey => {id};
}

/// Changes waiting to reach the server. One row per entity; a newer edit replaces the older row.
class PendingOps extends Table {
  IntColumn get seq => integer().autoIncrement()();
  TextColumn get entityId => text().unique()();
  TextColumn get op => text()(); // put | delete
}

@DataClassName('KvRow')
class Kv extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  @override
  Set<Column> get primaryKey => {key};
}

@DataClassName('Bill')
class Bills extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get kind => text().withDefault(const Constant('spaylater'))(); // spaylater | credit_card | rent | utilities | other
  TextColumn get dueDate => text()(); // YYYY-MM-DD
  IntColumn get amountCents => integer()();
  TextColumn get paidAt => text().nullable()(); // YYYY-MM-DD when paid
  @override
  Set<Column> get primaryKey => {id};
}

/// Repeating entries such as rent or a salary. They post themselves on the chosen day each month.
@DataClassName('RecurringItem')
class RecurringItems extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get direction => text().withDefault(const Constant('spend'))();
  IntColumn get amountCents => integer()();
  IntColumn get categoryId => integer()();
  TextColumn get paymentType => text().withDefault(const Constant('debit'))();
  IntColumn get dayOfMonth => integer().withDefault(const Constant(1))(); // 1 to 28
  BoolColumn get countsTowardCap => boolean().withDefault(const Constant(false))();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  TextColumn get lastPosted => text().nullable()(); // YYYY-MM of the last month posted
  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [Categories, Txns, TxnItems, PendingOps, Kv, Bills, RecurringItems])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'cukup'));
  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) await m.createTable(bills);
          if (from < 3) await m.createTable(recurringItems);
        },
      );

  // ---- repeating entries ----
  static const recurringOpPrefix = 'rec:';

  Stream<List<RecurringItem>> watchRecurring() => (select(recurringItems)..orderBy([(r) => OrderingTerm.asc(r.dayOfMonth), (r) => OrderingTerm.asc(r.id)])).watch();
  Future<List<RecurringItem>> getRecurringAll() => select(recurringItems).get();
  Future<RecurringItem?> getRecurring(String id) => (select(recurringItems)..where((r) => r.id.equals(id))).getSingleOrNull();

  Future<void> saveRecurring(RecurringItemsCompanion r) => transaction(() async {
        await into(recurringItems).insertOnConflictUpdate(r);
        await _queue('$recurringOpPrefix${r.id.value}', 'put');
      });

  Future<void> setRecurringPosted(String id, String month) => transaction(() async {
        await (update(recurringItems)..where((r) => r.id.equals(id))).write(RecurringItemsCompanion(lastPosted: Value(month)));
        await _queue('$recurringOpPrefix$id', 'put');
      });

  Future<void> deleteRecurring(String id) => transaction(() async {
        await (delete(recurringItems)..where((r) => r.id.equals(id))).go();
        await _queue('$recurringOpPrefix$id', 'delete');
      });

  Future<void> saveRecurringFromServer(RecurringItemsCompanion r) => into(recurringItems).insertOnConflictUpdate(r);

  Future<void> removeRecurringNotIn(Set<String> ids) async {
    for (final r in await getRecurringAll()) {
      if (!ids.contains(r.id) && !await hasPending('$recurringOpPrefix${r.id}')) {
        await (delete(recurringItems)..where((x) => x.id.equals(r.id))).go();
      }
    }
  }

  // ---- bills ----
  /// Pending-op ids for bills are prefixed so they never clash with transaction ids.
  static const billOpPrefix = 'bill:';

  Stream<List<Bill>> watchBills() => (select(bills)..orderBy([(b) => OrderingTerm.asc(b.dueDate), (b) => OrderingTerm.asc(b.id)])).watch();
  Future<List<Bill>> getBills() => (select(bills)..orderBy([(b) => OrderingTerm.asc(b.dueDate)])).get();
  Future<Bill?> getBill(String id) => (select(bills)..where((b) => b.id.equals(id))).getSingleOrNull();

  Future<void> saveBill(BillsCompanion b) => transaction(() async {
        await into(bills).insertOnConflictUpdate(b);
        await _queue('$billOpPrefix${b.id.value}', 'put');
      });

  Future<void> deleteBill(String id) => transaction(() async {
        await (delete(bills)..where((b) => b.id.equals(id))).go();
        await _queue('$billOpPrefix$id', 'delete');
      });

  Future<void> saveBillFromServer(BillsCompanion b) => into(bills).insertOnConflictUpdate(b);

  /// Server is the source of truth for bills it still has: drop local rows it no longer lists (unless a local change is pending).
  Future<void> removeBillsNotIn(Set<String> ids) async {
    for (final b in await getBills()) {
      if (!ids.contains(b.id) && !await hasPending('$billOpPrefix${b.id}')) {
        await (delete(bills)..where((x) => x.id.equals(b.id))).go();
      }
    }
  }

  // ---- reads ----
  Stream<List<Txn>> watchTxns({int? limit}) {
    final q = select(txns)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.desc(t.spentAt), (t) => OrderingTerm.desc(t.createdAt)]);
    if (limit != null) q.limit(limit);
    return q.watch();
  }

  Stream<List<Cat>> watchCategories() => (select(categories)..orderBy([(c) => OrderingTerm.asc(c.sortOrder)])).watch();

  /// Spending that counts toward the weekly cap, between two dates inclusive.
  Stream<int> watchCapSpent(String from, String to) {
    return customSelect(
      "SELECT COALESCE(SUM(amount_cents), 0) AS c FROM txns "
      "WHERE deleted_at IS NULL AND direction = 'spend' AND counts_toward_cap = 1 AND spent_at BETWEEN ?1 AND ?2",
      variables: [Variable<String>(from), Variable<String>(to)],
      readsFrom: {txns},
    ).watchSingle().map((r) => r.read<int>('c'));
  }

  /// Cap-counting spend per day (date -> cents), between two dates inclusive. Same filter as [watchCapSpent].
  Stream<Map<String, int>> watchDailyCapSpent(String from, String to) {
    return customSelect(
      "SELECT spent_at AS d, COALESCE(SUM(amount_cents), 0) AS c FROM txns "
      "WHERE deleted_at IS NULL AND direction = 'spend' AND counts_toward_cap = 1 AND spent_at BETWEEN ?1 AND ?2 GROUP BY spent_at",
      variables: [Variable<String>(from), Variable<String>(to)],
      readsFrom: {txns},
    ).watch().map((rows) => {for (final r in rows) r.read<String>('d'): r.read<int>('c')});
  }

  /// Total paid by SPayLater in the month starting at [monthStart] (YYYY-MM-01).
  Stream<int> watchSpaylaterMonth(String monthStart) {
    final d = DateTime.utc(int.parse(monthStart.substring(0, 4)), int.parse(monthStart.substring(5, 7)) + 1, 0);
    final end = ymd(d);
    return customSelect(
      "SELECT COALESCE(SUM(amount_cents), 0) AS c FROM txns "
      "WHERE deleted_at IS NULL AND direction = 'spend' AND payment_type = 'spaylater' AND spent_at BETWEEN ?1 AND ?2",
      variables: [Variable<String>(monthStart), Variable<String>(end)],
      readsFrom: {txns},
    ).watchSingle().map((r) => r.read<int>('c'));
  }

  // ---- merchant rules (learned from the category the user picks; stored on this phone) ----
  static String ruleKey(String merchant) => 'rule.${merchant.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim()}';

  Future<int?> getRule(String merchant) async {
    if (merchant.trim().isEmpty) return null;
    return int.tryParse(await getKv(ruleKey(merchant)) ?? '');
  }

  Future<void> learnRule(String merchant, int categoryId) {
    if (merchant.trim().isEmpty) return Future.value();
    return setKv(ruleKey(merchant), '$categoryId');
  }

  Stream<int> watchCapCents() => (select(kv)..where((k) => k.key.equals('setting.weekly_cap_cents')))
      .watchSingleOrNull()
      .map((r) => int.tryParse(r?.value ?? '') ?? 25000);

  Stream<int> watchPendingCount() => customSelect('SELECT COUNT(*) AS c FROM pending_ops', readsFrom: {pendingOps}).watchSingle().map((r) => r.read<int>('c'));

  Stream<Txn?> watchTxn(String id) => (select(txns)..where((t) => t.id.equals(id))).watchSingleOrNull();
  Stream<List<TxnItem>> watchItems(String txnId) => (select(txnItems)..where((i) => i.txnId.equals(txnId))).watch();

  Future<Txn?> getTxn(String id) => (select(txns)..where((t) => t.id.equals(id))).getSingleOrNull();
  Future<List<TxnItem>> getItems(String txnId) => (select(txnItems)..where((i) => i.txnId.equals(txnId))).get();

  /// Counted spending (what the weekly cap sees) for the week starting [monday].
  Future<int> weekSpentFor(String monday) async {
    final end = DateTime.parse(monday).add(const Duration(days: 6));
    final endYmd = '${end.year.toString().padLeft(4, '0')}-${end.month.toString().padLeft(2, '0')}-${end.day.toString().padLeft(2, '0')}';
    final rows = await customSelect(
      "SELECT COALESCE(SUM(amount_cents), 0) AS c FROM txns WHERE deleted_at IS NULL AND direction = 'spend' AND counts_toward_cap = 1 AND spent_at BETWEEN ?1 AND ?2",
      variables: [Variable.withString(monday), Variable.withString(endYmd)],
    ).get();
    return rows.first.read<int>('c');
  }

  /// All values stored under keys that start with [prefix].
  Future<List<String>> kvValuesWithPrefix(String prefix) async {
    final rows = await customSelect('SELECT value FROM kv WHERE "key" LIKE ?1', variables: [Variable.withString('$prefix%')]).get();
    return [for (final r in rows) r.read<String>('value')];
  }

  Future<String?> getKv(String key) async => (await (select(kv)..where((k) => k.key.equals(key))).getSingleOrNull())?.value;
  Future<void> setKv(String key, String value) => into(kv).insertOnConflictUpdate(KvCompanion.insert(key: key, value: value));

  // ---- local writes (each one also queues a push) ----
  Future<void> saveTxn(TxnsCompanion t, List<TxnItemsCompanion> items) => transaction(() async {
        await into(txns).insertOnConflictUpdate(t);
        await (delete(txnItems)..where((i) => i.txnId.equals(t.id.value))).go();
        for (final i in items) {
          await into(txnItems).insert(i);
        }
        await _queue(t.id.value, 'put');
      });

  /// Same as saveTxn but for rows that came from the server, so nothing is queued to push back.
  Future<void> saveTxnFromServer(TxnsCompanion t, List<TxnItemsCompanion> items) => transaction(() async {
        await into(txns).insertOnConflictUpdate(t);
        await (delete(txnItems)..where((i) => i.txnId.equals(t.id.value))).go();
        for (final i in items) {
          await into(txnItems).insertOnConflictUpdate(i);
        }
      });

  Future<void> softDelete(String id) => transaction(() async {
        final now = nowIso();
        await (update(txns)..where((t) => t.id.equals(id))).write(TxnsCompanion(deletedAt: Value(now), updatedAt: Value(now)));
        await _queue(id, 'delete');
      });

  Future<void> restore(String id) => transaction(() async {
        await (update(txns)..where((t) => t.id.equals(id))).write(TxnsCompanion(deletedAt: const Value(null), updatedAt: Value(nowIso())));
        await _queue(id, 'put');
      });

  Future<void> _queue(String id, String op) async {
    await (delete(pendingOps)..where((p) => p.entityId.equals(id))).go();
    await into(pendingOps).insert(PendingOpsCompanion.insert(entityId: id, op: op));
  }

  // ---- sync helpers ----
  Future<List<PendingOp>> pendingOpsInOrder() => (select(pendingOps)..orderBy([(p) => OrderingTerm.asc(p.seq)])).get();

  /// Only clears the row if it was not replaced by a newer edit while the push was in flight.
  Future<void> clearOp(int seq) => (delete(pendingOps)..where((p) => p.seq.equals(seq))).go();

  Future<bool> hasPending(String entityId) async => (await (select(pendingOps)..where((p) => p.entityId.equals(entityId))).getSingleOrNull()) != null;

  Future<void> replaceCategories(List<CategoriesCompanion> rows) => transaction(() async {
        await delete(categories).go();
        for (final r in rows) {
          await into(categories).insert(r);
        }
      });
}


