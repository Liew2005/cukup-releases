import '../core/app_state.dart';
import '../core/time.dart';
import 'api.dart';
import 'db.dart';

const _syncedKey = 'state.synced'; // the document as it stood after the last sync

Future<Map<String, String>> _snapshot(AppDatabase db) async {
  final out = <String, String>{};
  for (final k in syncedKeys) {
    final v = await db.getKv(k);
    if (v != null) out[k] = v;
  }
  for (final p in syncedPrefixes) {
    out.addAll(await db.kvPrefix(p));
  }
  return out;
}

/// Two-way sync of the small things that are not entries (see core/app_state.dart).
/// Returns true when values on this phone changed, so screens that show them can refresh.
Future<bool> syncAppState(AppDatabase db, ApiClient api) async {
  final local = await _snapshot(db);
  final syncedDoc = await db.getKv(_syncedKey);
  final synced = syncedDoc == null ? null : decodeState(syncedDoc);
  final res = await api.appState();
  final remoteDoc = res['doc'] as String?;
  final remote = remoteDoc == null ? null : decodeState(remoteDoc);

  final merged = mergeState(local: local, synced: synced, remote: remote);
  var changed = false;
  for (final e in merged.entries) {
    if (local[e.key] != e.value) {
      await db.setKv(e.key, e.value);
      changed = true;
    }
  }
  if (remote == null || !sameState(merged, remote)) {
    if (merged.isEmpty && remote == null) return false; // nothing anywhere yet
    await api.putAppState(encodeState(merged), nowIso());
  }
  await db.setKv(_syncedKey, encodeState(merged));
  return changed;
}
