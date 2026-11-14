// Settings and small records that are not entries, kept in step between the phone and the server:
// savings goal and sweeps, shop-to-category rules, remembered cards, reminder switches, carry-over, pay link.
// Pure Dart. The storage and network side is data/app_state.dart.
import 'dart:convert';

/// Exact keys that are synced.
const syncedKeys = {'goal.name', 'goal.target_cents', 'detected.cards', 'ledger.paylink', 'setting.carry', 'setting.n_bills', 'setting.n_daily', 'setting.n_weekly', 'setting.n_cap', 'setting.n_monthly'};

/// Key prefixes that are synced: one value per week or per shop.
const syncedPrefixes = ['sweep.', 'sweepskip.', 'rule.'];

bool isSynced(String key) => syncedKeys.contains(key) || syncedPrefixes.any(key.startsWith);

/// The document sent to the server. Keys are sorted so the same values always give the same text.
String encodeState(Map<String, String> kv) => jsonEncode({'v': 1, 'kv': {for (final k in kv.keys.toList()..sort()) k: kv[k]}});

/// Reads a document from the server. Anything that is not a synced key is dropped, so a bad copy cannot touch other settings.
Map<String, String> decodeState(String? doc) {
  if (doc == null || doc.isEmpty) return {};
  try {
    final kv = (jsonDecode(doc) as Map)['kv'] as Map;
    return {for (final e in kv.entries) if (e.key is String && e.value is String && isSynced(e.key as String)) e.key as String: e.value as String};
  } catch (_) {
    return {};
  }
}

/// What the phone should hold after a sync.
///
/// [local] is what is on the phone now, [synced] what it held after the last sync (null on a fresh install),
/// [remote] what the server has (null when it has nothing).
/// - Nothing changed here since the last sync: the server copy is taken as it is.
/// - Something changed here (or this is the first sync): both are kept, and the phone wins where they differ.
///   Values here are only ever added or changed, never removed, so keeping both loses nothing.
Map<String, String> mergeState({required Map<String, String> local, required Map<String, String>? synced, required Map<String, String>? remote}) {
  if (remote == null) return {...local};
  final changedHere = synced == null || !_same(local, synced);
  return changedHere ? {...remote, ...local} : {...remote};
}

bool sameState(Map<String, String> a, Map<String, String> b) => _same(a, b);

bool _same(Map<String, String> a, Map<String, String> b) {
  if (a.length != b.length) return false;
  for (final e in a.entries) {
    if (b[e.key] != e.value) return false;
  }
  return true;
}
