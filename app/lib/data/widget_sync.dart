import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';

import '../core/quick.dart';
import '../core/time.dart';
import 'carry.dart';
import 'providers.dart';

/// Keeps the home-screen widget in step with the app: pushes the cap and this week's spend whenever either changes.
final widgetSyncProvider = Provider<void>((ref) {
  Future<void> push() async {
    final cap = ref.read(capInfoProvider).asData?.value.effective ?? ref.read(capCentsProvider).asData?.value;
    final spent = ref.read(weekSpentProvider).asData?.value;
    if (cap == null || spent == null) return;
    try {
      await HomeWidget.saveWidgetData<String>('cap_cents', '$cap');
      await HomeWidget.saveWidgetData<String>('spent_cents', '$spent');
      await HomeWidget.saveWidgetData<String>('week_end', addDays(mondayOf(todayKL()), 6));
      await HomeWidget.updateWidget(androidName: 'CukupWidgetProvider');
    } catch (_) {
      // no widget on this device, or the plugin is unavailable: nothing to do
    }
  }

  ref.listen(weekSpentProvider, (_, _) => push());
  ref.listen(capCentsProvider, (_, _) => push());
  ref.listen(capInfoProvider, (_, _) => push());
  push();
});

/// Most-used shops for the Quick add chips.
final quickMerchantsProvider = StreamProvider<List<QuickMerchant>>(
  (ref) => ref.watch(dbProvider).watchTxns(limit: 300).map(topMerchants),
);
