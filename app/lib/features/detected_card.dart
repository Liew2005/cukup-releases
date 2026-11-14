import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../core/format.dart';
import '../core/pay_notif.dart';
import '../data/detected.dart';
import '../theme/theme.dart';

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
      b.writeln('${_when(l.at)} | ${l.app} | ${l.kind == 'pay' ? 'PAY ${rm(l.cents ?? 0)}' : l.kind == 'merge' ? 'same payment ${rm(l.cents ?? 0)}' : 'skipped'} | ${l.title} | ${l.text.replaceAll('\n', ' ')}');
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
                'When TNG eWallet, ShopeePay, Grab, Google Wallet or your bank app (AmBank, UOB, HSBC, CIMB, GXBank, Ryt Bank, HLB) tells you a payment went through, '
                'a banner asks whether to save it. Nothing is recorded until you tap Save. Notifications from other apps are ignored, and nothing is sent anywhere: it is all read on this phone.',
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
                  Text(l.kind == 'pay' ? rm(l.cents ?? 0) : l.kind == 'merge' ? 'Same payment' : 'Skipped', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: l.kind == 'pay' ? Brand.forest : Brand.muted)),
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
