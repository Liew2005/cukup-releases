import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import 'providers.dart';

class LockState {
  const LockState({required this.ready, required this.enabled, required this.locked});
  final bool ready; // the saved setting has been read
  final bool enabled;
  final bool locked;
}

/// Fingerprint (or phone PIN) lock that covers the app when it opens and after it has been away.
/// The server password is still what signs you in; this only guards the phone.
class AppLockController extends Notifier<LockState> {
  static const _awayLimit = Duration(seconds: 30);
  static const _key = 'local.app_lock'; // stays on the phone, never synced

  final _auth = LocalAuthentication();
  DateTime? _pausedAt;
  bool _prompting = false;

  @override
  LockState build() {
    _load();
    return const LockState(ready: false, enabled: false, locked: false);
  }

  Future<void> _load() async {
    final on = (await ref.read(dbProvider).getKv(_key)) == '1';
    state = LockState(ready: true, enabled: on, locked: on);
  }

  Future<bool> deviceCanAuthenticate() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  Future<bool> _prompt(String reason) async {
    _prompting = true;
    try {
      return await _auth.authenticate(localizedReason: reason);
    } catch (_) {
      return false;
    } finally {
      _prompting = false;
      _pausedAt = null;
    }
  }

  /// Turning it on asks once, so you know it works before you rely on it.
  Future<bool> setEnabled(bool on) async {
    if (on && !await _prompt('Confirm to turn on app lock')) return false;
    await ref.read(dbProvider).setKv(_key, on ? '1' : '0');
    state = LockState(ready: true, enabled: on, locked: false);
    return true;
  }

  Future<bool> unlock() async {
    if (_prompting) return false;
    final ok = await _prompt('Unlock Cukup');
    if (ok) state = LockState(ready: true, enabled: state.enabled, locked: false);
    return ok;
  }

  void appPaused() {
    if (!_prompting) _pausedAt = DateTime.now();
  }

  void appResumed() {
    final since = _pausedAt;
    if (_prompting || since == null || !state.enabled || state.locked) return;
    if (DateTime.now().difference(since) > _awayLimit) state = LockState(ready: true, enabled: true, locked: true);
  }
}

final appLockProvider = NotifierProvider<AppLockController, LockState>(AppLockController.new);
