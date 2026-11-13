import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../core/pay_notif.dart';
import '../core/time.dart';
import '../features/cap_switch.dart' show capDefault;
import 'db.dart';
import 'providers.dart';

const _channel = MethodChannel('cukup/share');
const _doneKey = 'detected.done';

/// The file the Android listener writes (app-private). Empty when nothing was ever detected.
Future<String> _readFile() async {
  try {
    final f = File('${(await getApplicationSupportDirectory()).path}/detected.jsonl');
    return await f.exists() ? await f.readAsString() : '';
  } catch (_) {
    return '';
  }
}

/// Is Cukup allowed to read notifications? False on anything but Android.
Future<bool> detectAccess() async {
  try {
    return await _channel.invokeMethod<bool>('detectAccess') ?? false;
  } catch (_) {
    return false;
  }
}

Future<void> openDetectSettings() async {
  try {
    await _channel.invokeMethod('detectSettings');
  } catch (_) {}
}

Future<void> openAppInfo() async {
  try {
    await _channel.invokeMethod('appInfo');
  } catch (_) {}
}

/// Everything the listener has seen, newest first, for the log in Settings.
Future<List<LogLine>> detectedLog() async => readInbox(await _readFile(), const {}).log;

/// Payments noticed from notifications that still need a Save or Ignore.
/// Ones where Save was tapped on the notification itself are turned into entries as soon as the app is open.
class DetectedController extends Notifier<List<Detected>> {
  bool _busy = false;

  @override
  List<Detected> build() {
    final watcher = AppLifecycleListener(onResume: refresh);
    ref.onDispose(watcher.dispose);
    Future.microtask(refresh);
    return const [];
  }

  AppDatabase get _db => ref.read(dbProvider);

  Future<Set<String>> _done() async {
    try {
      return {for (final e in jsonDecode(await _db.getKv(_doneKey) ?? '[]') as List) '$e'};
    } catch (_) {
      return {};
    }
  }

  Future<void> _markDone(Iterable<String> ids) async {
    final all = [...await _done(), ...ids];
    await _db.setKv(_doneKey, jsonEncode(all.length > 600 ? all.sublist(all.length - 600) : all));
  }

  Future<void> refresh() async {
    if (_busy) return;
    _busy = true;
    try {
      final inbox = readInbox(await _readFile(), await _done());
      var saved = false;
      for (final d in inbox.toSave) {
        saved = await _store(d) || saved;
      }
      if (inbox.toSave.isNotEmpty) await _markDone(inbox.toSave.map((d) => d.id));
      if (saved) ref.read(syncProvider.notifier).run();
      state = inbox.pending;
    } finally {
      _busy = false;
    }
  }

  /// Writes the entry. The shop falls back to the app name; the category is the one you last used for that shop, else Other.
  Future<bool> _store(Detected d) async {
    final cats = (await ref.read(categoriesProvider.future)).where((c) => c.kind == 'spend').toList();
    if (cats.isEmpty) return false; // categories not loaded yet: it stays for next time
    if (await _db.getTxn(d.txnId) != null) return false;
    final merchant = d.merchant ?? d.app;
    final learned = await _db.getRule(merchant);
    final cat = cats.where((c) => c.id == learned).firstOrNull ?? cats.where((c) => c.name.toLowerCase() == 'other').firstOrNull ?? cats.first;
    final now = nowIso();
    await _db.saveTxn(
      TxnsCompanion.insert(
        id: d.txnId,
        spentAt: d.date,
        merchant: merchant,
        amountCents: d.cents,
        categoryId: cat.id,
        paymentType: d.paymentType,
        createdAt: now,
        updatedAt: now,
        direction: const Value('spend'),
        countsTowardCap: Value(capDefault(cat.name)),
        source: const Value('import'),
        note: Value('Detected from ${d.app}'),
      ),
      const [],
    );
    return true;
  }

  Future<void> _finish(Detected d) async {
    await _markDone([d.id]);
    state = [for (final x in state) if (x.id != d.id) x];
    try {
      await _channel.invokeMethod('detectCancel', d.id);
    } catch (_) {}
  }

  /// Save from the Home card.
  Future<void> save(Detected d) async {
    final ok = await _store(d);
    await _finish(d);
    if (ok) ref.read(syncProvider.notifier).run();
  }

  /// Ignore, or handed to the Review screen to edit before saving.
  Future<void> dismiss(Detected d) => _finish(d);
}

final detectedProvider = NotifierProvider<DetectedController, List<Detected>>(DetectedController.new);
