import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_lock.dart';
import '../data/providers.dart';
import '../theme/theme.dart';

/// Sits above the whole app. Shows the lock screen while the app is locked and signed in.
class LockGate extends ConsumerStatefulWidget {
  const LockGate({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<LockGate> createState() => _LockGateState();
}

class _LockGateState extends ConsumerState<LockGate> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    final lock = ref.read(appLockProvider.notifier);
    if (s == AppLifecycleState.paused) lock.appPaused();
    if (s == AppLifecycleState.resumed) lock.appResumed();
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = ref.watch(authProvider) == AuthStatus.signedIn;
    final lock = ref.watch(appLockProvider);
    final cover = signedIn && (!lock.ready || (lock.enabled && lock.locked));
    return Stack(children: [
      widget.child,
      if (cover) Positioned.fill(child: lock.ready ? const _LockScreen() : const ColoredBox(color: Brand.paper)),
    ]);
  }
}

class _LockScreen extends ConsumerStatefulWidget {
  const _LockScreen();
  @override
  ConsumerState<_LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<_LockScreen> {
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _try());
  }

  Future<void> _try() async {
    final ok = await ref.read(appLockProvider.notifier).unlock();
    if (!ok && mounted) setState(() => _failed = true);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Brand.paper,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(color: Brand.forest, borderRadius: BorderRadius.circular(18)),
                alignment: Alignment.center,
                child: const Text('C', style: TextStyle(color: Brand.paper, fontSize: 34, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(height: 20),
              const Text('Cukup is locked', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5, decoration: TextDecoration.none, color: Brand.ink)),
              const SizedBox(height: 6),
              Text(_failed ? 'Not recognised. Try again.' : 'Use your fingerprint or phone PIN.', style: TextStyle(fontSize: 15, decoration: TextDecoration.none, color: _failed ? Brand.danger : Brand.muted)),
              const SizedBox(height: 28),
              SizedBox(
                width: 240,
                child: FilledButton.icon(
                  onPressed: () {
                    setState(() => _failed = false);
                    _try();
                  },
                  icon: const Icon(Icons.fingerprint),
                  label: const Text('Unlock'),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
