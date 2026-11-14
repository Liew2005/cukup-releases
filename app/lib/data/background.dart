import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';

import '../core/time.dart';
import 'carry.dart';
import 'detected.dart';
import 'notifications.dart';
import 'providers.dart';

/// Runs when Save is tapped on a detected-payment banner while the app is closed. Android starts this code on its own,
/// with no screen: it turns the tap into an entry straight away, then brings the home-screen widget, the cap alert
/// and the server up to date. If Android will not run it, nothing is lost: the app does the same when it next opens.
@pragma('vm:entry-point')
Future<void> backgroundCallback(Uri? uri) async {
  if (uri == null || uri.scheme != 'cukup' || uri.host != 'detected') return;
  detectedHeadless = true;
  final c = ProviderContainer();
  try {
    final saved = await c.read(detectedProvider.notifier).refresh(sync: false);
    if (!saved) return;
    final db = c.read(dbProvider);

    try {
      final cap = (await loadCapInfo(db)).effective;
      final spent = await db.weekSpentFor(mondayOf(todayKL()));
      await HomeWidget.saveWidgetData<String>('cap_cents', '$cap');
      await HomeWidget.saveWidgetData<String>('spent_cents', '$spent');
      await HomeWidget.saveWidgetData<String>('week_end', addDays(mondayOf(todayKL()), 6));
      await HomeWidget.updateWidget(androidName: 'CukupWidgetProvider');
    } catch (_) {
      // no widget on the home screen
    }

    try {
      final n = NotificationService(db);
      await n.init();
      await n.refresh(); // the cap alert, and tonight's "nothing logged" nudge no longer applies
    } catch (_) {}

    try {
      if (await c.read(authStoreProvider).load() != null) await c.read(syncProvider.notifier).run().timeout(const Duration(seconds: 25));
    } catch (_) {
      // offline or slow: the entry is queued and goes up on the next sync
    }
  } catch (_) {
    // anything unexpected: the tap is still on record and the app picks it up when it opens
  } finally {
    c.dispose();
  }
}

/// Tells Android which code to start for the banner's Save. Called once each time the app starts.
Future<void> registerBackground() async {
  try {
    await HomeWidget.registerInteractivityCallback(backgroundCallback);
  } catch (_) {
    // not on Android
  }
}
