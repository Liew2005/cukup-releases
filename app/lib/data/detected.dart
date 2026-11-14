import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../core/cap_rule.dart';
import '../core/pay_notif.dart';
import '../core/time.dart';
import 'db.dart';
import 'providers.dart';

const _channel = MethodChannel('cukup/share');
const _doneKey = 'detected.done';
const _cardsKey = 'detected.cards';

Future<String> _dir() async => (await getApplicationSupportDirectory()).path;

/// The file the Android listener writes (app-private). Empty when nothing was ever detected.
Future<String> _readFile() async {
  try {
    final f = File('${await _dir()}/detected.jsonl');
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

/// The detection whose banner was just tapped, if any (asked once; Android forgets it after).
Future<String?> takeConfirmId() async {
  try {
    return await _channel.invokeMethod<String>('takeConfirm');
  } catch (_) {
    return null;
  }
}

/// Everything the listener has seen, newest first, for the log in Settings.
Future<List<LogLine>> detectedLog() async => readInbox(await _readFile(), const {}).log;

/// What you chose on the Confirm sheet. Anything left null keeps what was detected.
class ConfirmChoice {
  const ConfirmChoice({this.merchant, this.cents, this.categoryId, this.paymentType, this.countsTowardCap});
  final String? merchant;
  final int? cents;
  final int? categoryId;
  final String? paymentType;
  final bool? countsTowardCap;
}

/// Payments noticed from notifications that still need a Save or Delete. Nothing becomes an entry without a Save:
/// on the banner (picked up here the next time the app is open), on the Home card, or on the Confirm sheet.
class DetectedController extends Notifier<List<Detected>> {
  bool _busy = false;
  Map<String, String> _cards = const {}; // card name (lower case) -> credit_card | debit
  final Map<String, Cat> _guess = {}; // detection id -> the category it would be saved under

  @override
  List<Detected> build() {
    final watcher = AppLifecycleListener(onResume: refresh);
    ref.onDispose(watcher.dispose);
    ref.listen(categoriesProvider, (_, _) => refresh()); // a new or renamed category changes the guesses
    Future.microtask(refresh);
    return const [];
  }

  AppDatabase get _db => ref.read(dbProvider);

  /// The category a detection would be saved under, for showing before Save.
  Cat? guessFor(Detected d) => _guess[d.id];

  /// What the card was last saved as, or null when it is new.
  String? payFor(Detected d) => d.paymentType(_cards);

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

  Future<List<Cat>> _spendCats() async => (await ref.read(categoriesProvider.future)).where((c) => c.kind == 'spend').toList();

  /// The category you last used for this shop, else Other.
  Future<Cat?> _categoryFor(String merchant, List<Cat> cats) async {
    if (cats.isEmpty) return null;
    final learned = await _db.getRule(merchant);
    return cats.where((c) => c.id == learned).firstOrNull ?? cats.where((c) => c.name.toLowerCase() == 'other').firstOrNull ?? cats.first;
  }

  Future<void> refresh() async {
    if (_busy) return;
    _busy = true;
    try {
      try {
        _cards = {for (final e in (jsonDecode(await _db.getKv(_cardsKey) ?? '{}') as Map).entries) '${e.key}': '${e.value}'};
      } catch (_) {
        _cards = const {};
      }
      final inbox = readInbox(await _readFile(), await _done());
      var changed = false;
      for (final d in inbox.toSave) {
        changed = await _store(d, const ConfirmChoice()) || changed;
      }
      if (inbox.toSave.isNotEmpty) await _markDone(inbox.toSave.map((d) => d.id));
      for (final d in inbox.renamed) {
        changed = await _rename(d) || changed;
      }
      final cats = await _spendCats();
      _guess.clear();
      for (final d in inbox.pending) {
        final c = await _categoryFor(d.merchant, cats);
        if (c != null) _guess[d.id] = c;
      }
      if (changed) ref.read(syncProvider.notifier).run();
      state = inbox.pending;
      await _exportContext(cats);
    } finally {
      _busy = false;
    }
  }

  /// Writes the entry. Returns false when it already exists or categories have not loaded yet.
  Future<bool> _store(Detected d, ConfirmChoice c) async {
    final cats = await _spendCats();
    if (cats.isEmpty) return false; // it stays for next time
    if (await _db.getTxn(d.txnId) != null) return false;
    final merchant = (c.merchant ?? '').trim().isEmpty ? d.merchant : c.merchant!.trim();
    final cat = cats.where((x) => x.id == c.categoryId).firstOrNull ?? await _categoryFor(merchant, cats);
    if (cat == null) return false;
    final pay = c.paymentType ?? d.paymentType(_cards) ?? 'credit_card';
    final now = nowIso();
    await _db.saveTxn(
      TxnsCompanion.insert(
        id: d.txnId,
        spentAt: d.date,
        merchant: merchant,
        amountCents: c.cents ?? d.cents,
        categoryId: cat.id,
        paymentType: pay,
        createdAt: now,
        updatedAt: now,
        direction: const Value('spend'),
        countsTowardCap: Value(pay != 'spaylater' && (c.countsTowardCap ?? capDefault(cat.name))),
        source: const Value('import'),
        note: Value('Detected from ${d.app}, saved ${d.via == 'banner' ? 'from the banner' : 'in the app'}'),
      ),
      const [],
    );
    if (c.categoryId != null) await _db.learnRule(merchant, cat.id); // you picked it: remember it for this shop
    if (d.card != null && (c.paymentType == 'credit_card' || c.paymentType == 'debit' || d.chosenPay != null)) {
      _cards = {..._cards, d.card!.toLowerCase(): pay};
      await _db.setKv(_cardsKey, jsonEncode(_cards));
    }
    return true;
  }

  /// A payment saved under the app's name ("CIMB") whose shop a second app has since supplied.
  Future<bool> _rename(Detected d) async {
    final t = await _db.getTxn(d.txnId);
    if (t == null || t.deletedAt != null || t.merchant != d.app || d.shop == null) return false;
    await _db.saveTxn(t.toCompanion(true).copyWith(merchant: Value(d.shop!), updatedAt: Value(nowIso())), const []);
    return true;
  }

  /// Hands the banner what it needs to guess a category and a payment type while the app is closed.
  Future<void> _exportContext(List<Cat> cats) async {
    try {
      final rules = await _db.kvPrefix('rule.');
      final f = File('${await _dir()}/detect_ctx.json');
      await f.writeAsString(jsonEncode({
        'cats': {for (final c in cats) '${c.id}': c.name},
        'rules': {for (final e in rules.entries) if (int.tryParse(e.value) != null) e.key.substring(5): int.parse(e.value)},
        'cards': _cards,
      }));
    } catch (_) {
      // the banner falls back to "Other" and asks about the card
    }
  }

  Future<void> _finish(Detected d) async {
    await _markDone([d.id]);
    _guess.remove(d.id);
    state = [for (final x in state) if (x.id != d.id) x];
    try {
      await _channel.invokeMethod('detectCancel', d.id);
    } catch (_) {}
    await _exportContext(await _spendCats());
  }

  /// Save from the Home card or the Confirm sheet.
  Future<void> save(Detected d, [ConfirmChoice choice = const ConfirmChoice()]) async {
    d.via = 'app';
    final ok = await _store(d, choice);
    await _finish(d);
    if (ok) ref.read(syncProvider.notifier).run();
  }

  /// Delete: it was not a spend, or you do not want it logged.
  Future<void> dismiss(Detected d) => _finish(d);
}

final detectedProvider = NotifierProvider<DetectedController, List<Detected>>(DetectedController.new);
