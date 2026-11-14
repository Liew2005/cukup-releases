import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app.dart';
import 'detected.dart';
import 'providers.dart';

const _channel = MethodChannel('cukup/share');

/// Listens for a Touch 'n Go or bank screenshot shared to Cukup from the Android share sheet,
/// reads it on the phone, and opens Review with the amount, payee, reference and date filled in.
final shareImportProvider = Provider<void>((ref) {
  var busy = false;

  Future<void> take() async {
    if (busy) return;
    busy = true;
    try {
      final path = await _channel.invokeMethod<String>('take');
      if (path == null) return;
      final router = ref.read(routerProvider);
      try {
        final parsed = await ref.read(scanServiceProvider).scan(path, payment: true);
        router.push('/review', extra: parsed);
      } catch (_) {
        router.push('/add'); // could not read it: enter it by hand
      }
    } on MissingPluginException {
      // not running on Android
    } finally {
      busy = false;
    }
  }

  // The banner for a detected payment was tapped: open its Confirm sheet.
  Future<void> confirm() async {
    final id = await takeConfirmId();
    if (id != null) ref.read(routerProvider).push('/confirm/$id');
  }

  _channel.setMethodCallHandler((call) async {
    if (call.method == 'shared') await take();
    if (call.method == 'confirm') await confirm();
  });
  take(); // a screenshot that opened the app from cold
  confirm(); // a banner tap that opened the app from cold
  ref.onDispose(() => _channel.setMethodCallHandler(null));
});
