import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../core/format.dart';
import '../core/pay_notif.dart';
import '../data/detected.dart';
import '../data/receipt_models.dart';
import '../theme/theme.dart';
import 'dup_dialog.dart';

/// Home: payments Cukup noticed from your wallet and bank notifications, waiting for a yes or no.
/// Shows nothing when there are none.
class DetectedCard extends ConsumerWidget {
  const DetectedCard({super.key});

  Future<void> _save(BuildContext context, WidgetRef ref, Detected d) async {
    if (!await confirmNotDuplicate(context, ref, merchant: d.merchant ?? d.app, amountCents: d.cents, date: d.date)) return;
    await ref.read(detectedProvider.notifier).save(d);
  }

  /// Opens Check and save with the amount and shop filled in, for when something needs changing first.
  Future<void> _edit(BuildContext context, WidgetRef ref, Detected d) async {
    final parsed = ParsedReceipt(merchant: d.merchant, date: d.date, items: [], totalCents: d.cents, confidence: d.merchant != null ? 0.85 : 0.6, warnings: d.merchant == null ? ['no_merchant'] : const [], via: 'offline')..isImport = true;
    await ref.read(detectedProvider.notifier).dismiss(d);
    if (context.mounted) context.push('/review', extra: parsed);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(detectedProvider);
    if (pending.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
        decoration: BoxDecoration(color: Brand.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: Brand.amber, width: 1.5)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(pending.length == 1 ? 'Did you pay this?' : 'Did you pay these?', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          for (final d in pending.take(5))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${rm(d.cents)} · ${d.merchant ?? d.app}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    Text('${d.app} · ${shortWhen(d)}', style: const TextStyle(fontSize: 12, color: Brand.muted)),
                  ]),
                ),
                TextButton(onPressed: () => _save(context, ref, d), style: TextButton.styleFrom(foregroundColor: Brand.forest), child: const Text('Save', style: TextStyle(fontWeight: FontWeight.w800))),
                IconButton(icon: const Icon(Icons.edit_outlined, size: 20), tooltip: 'Check and edit', color: Brand.muted, onPressed: () => _edit(context, ref, d)),
                IconButton(icon: const Icon(Icons.close, size: 20), tooltip: 'Not a spend', color: Brand.muted, onPressed: () => ref.read(detectedProvider.notifier).dismiss(d)),
              ]),
            ),
          if (pending.length > 5) Padding(padding: const EdgeInsets.only(top: 6, bottom: 6), child: Text('and ${pending.length - 5} more', style: const TextStyle(fontSize: 12, color: Brand.muted))),
        ]),
      ),
    );
  }
}

String shortWhen(Detected d) => '${d.date.substring(8, 10)}/${d.date.substring(5, 7)} ${d.time}';

/// Settings > Detect payments: turn it on, and see exactly what was read.
class DetectedPage extends ConsumerStatefulWidget {
  const DetectedPage({super.key});
  @override
  ConsumerState<DetectedPage> createState() => _DetectedPageState();
}

class _DetectedPageState extends ConsumerState<DetectedPage> with WidgetsBindingObserver {
  bool _on = false;
  List<LogLine> _log = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load(); // back from Android settings
  }

  Future<void> _load() async {
    final on = await detectAccess();
    final log = await detectedLog();
    if (mounted) {
      setState(() {
        _on = on;
        _log = log;
      });
    }
  }

  String _when(int at) {
    final d = DateTime.fromMillisecondsSinceEpoch(at, isUtc: true).add(const Duration(hours: 8));
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)} ${two(d.hour)}:${two(d.minute)}';
  }

  Future<void> _share() async {
    final b = StringBuffer('Cukup detected payments log\n');
    for (final l in _log.take(300)) {
      b.writeln('${_when(l.at)} | ${l.app} | ${l.kind == 'pay' ? 'PAY ${rm(l.cents ?? 0)}' : 'skipped'} | ${l.title} | ${l.text.replaceAll('\n', ' ')}');
    }
    await SharePlus.instance.share(ShareParams(text: b.toString()));
  }

  @override
  Widget build(BuildContext context) {
    const small = TextStyle(fontSize: 13, color: Brand.muted, height: 1.4);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), tooltip: 'Back', onPressed: () => context.pop()),
        title: const Text('Detect payments', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [if (_log.isNotEmpty) IconButton(icon: const Icon(Icons.ios_share), tooltip: 'Share log', onPressed: _share)],
      ),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 28), children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Brand.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: Brand.line)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(_on ? Icons.check_circle : Icons.radio_button_unchecked, color: _on ? Brand.forest : Brand.muted),
                const SizedBox(width: 10),
                Expanded(child: Text(_on ? 'On. Cukup is watching for payments.' : 'Off', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
              ]),
              const SizedBox(height: 10),
              const Text(
                'When TNG eWallet, ShopeePay, Grab or your bank app (UOB, HSBC, CIMB, GXBank, Ryt Bank, HLB) tells you a payment went through, '
                'Cukup asks whether to save it. Notifications from other apps are ignored, and nothing is sent anywhere: it is all read on this phone.',
                style: small,
              ),
              const SizedBox(height: 12),
              FilledButton(onPressed: openDetectSettings, child: Text(_on ? 'Open notification access' : 'Turn on: allow notification access')),
              if (!_on) ...[
                const SizedBox(height: 12),
                const Text(
                  'If Android says "Restricted setting": open App info below, tap the three dots at the top right, choose "Allow restricted settings", then try again. '
                  'Android asks this once for apps installed outside the Play Store.',
                  style: small,
                ),
                TextButton(onPressed: openAppInfo, style: TextButton.styleFrom(foregroundColor: Brand.forest, padding: EdgeInsets.zero), child: const Text('Open App info')),
              ],
            ]),
          ),
          const SizedBox(height: 22),
          const Text('What Cukup has seen', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text('Long numbers are hidden. Use the share button at the top to send this list when a payment was missed or read wrongly.', style: small),
          const SizedBox(height: 8),
          if (_log.isEmpty) const Padding(padding: EdgeInsets.only(top: 12), child: Text('Nothing yet. Make a payment and it will show up here.', style: small)),
          for (final l in _log.take(100))
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Brand.line))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text('${l.app} · ${_when(l.at)}', style: const TextStyle(fontSize: 12, color: Brand.muted))),
                  Text(l.kind == 'pay' ? rm(l.cents ?? 0) : 'Skipped', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: l.kind == 'pay' ? Brand.forest : Brand.muted)),
                ]),
                const SizedBox(height: 2),
                Text([l.title, l.text].where((s) => s.isNotEmpty).join(': '), maxLines: 4, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)),
              ]),
            ),
        ]),
      ),
    );
  }
}
