import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/format.dart';
import '../data/app_lock.dart';
import '../data/ledger.dart' show loadPayLink, savePayLink;
import '../data/db.dart';
import 'export_action.dart';
import 'notif_switch.dart';
import 'carry_switch.dart';
import 'update_tile.dart';
import '../data/providers.dart';
import '../theme/theme.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  Future<void> _toggleLock(BuildContext context, WidgetRef ref, bool on) async {
    final lock = ref.read(appLockProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    if (on && !await lock.deviceCanAuthenticate()) {
      messenger.showSnackBar(const SnackBar(content: Text('Set up a fingerprint or screen lock in your phone settings first.')));
      return;
    }
    final ok = await lock.setEnabled(on);
    if (!ok) messenger.showSnackBar(const SnackBar(content: Text('Could not confirm. App lock stays off.')));
  }

  Future<void> _editCap(BuildContext context, WidgetRef ref, int current) async {
    final field = TextEditingController(text: (current / 100).toStringAsFixed(current % 100 == 0 ? 0 : 2));
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Weekly cap'),
        content: TextField(controller: field, autofocus: true, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Per week', prefixText: 'RM ')),
        actions: [
          TextButton(onPressed: () => c.pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => c.pop(true), child: const Text('Save', style: TextStyle(color: Brand.forest, fontWeight: FontWeight.w800))),
        ],
      ),
    );
    final cents = parseCents(field.text);
    if (ok != true) return;
    if (cents == null || cents <= 0 || cents > 100000000) {
      messenger.showSnackBar(const SnackBar(content: Text('Enter an amount above zero, like 300.')));
      return;
    }
    try {
      await ref.read(apiProvider).putSetting('weekly_cap_cents', '$cents'); // server first, so a sync cannot bring the old value back
      await ref.read(dbProvider).setKv('setting.weekly_cap_cents', '$cents');
      messenger.showSnackBar(SnackBar(content: Text('Weekly cap is now ${rm(cents)}')));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Could not save. Changing the cap needs a connection.')));
    }
  }

  Future<void> _editPayLink(BuildContext context, WidgetRef ref) async {
    final db = ref.read(dbProvider);
    final field = TextEditingController(text: await loadPayLink(db));
    if (!context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Payment link'),
        content: TextField(controller: field, autofocus: true, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Link friends can tap to pay you')),
        actions: [
          TextButton(onPressed: () => c.pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => c.pop(true), child: const Text('Save', style: TextStyle(color: Brand.forest, fontWeight: FontWeight.w800))),
        ],
      ),
    );
    if (ok == true) await savePayLink(db, field.text);
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('Entries stay safe on your server. You will need your password to sign back in.'),
        actions: [
          TextButton(onPressed: () => c.pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => c.pop(true), child: const Text('Sign out', style: TextStyle(color: Brand.danger, fontWeight: FontWeight.w800))),
        ],
      ),
    );
    if (ok == true) await ref.read(authProvider.notifier).logout();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lock = ref.watch(appLockProvider);
    final sync = ref.watch(syncProvider);
    final pending = ref.watch(pendingCountProvider).asData?.value ?? 0;
    final cap = ref.watch(capCentsProvider).asData?.value ?? 25000;

    final syncText = sync.running
        ? 'Syncing…'
        : sync.error != null
            ? sync.error!
            : sync.lastSyncAt != null
                ? 'Up to date'
                : 'Not synced yet';

    Widget section(String title, List<Widget> rows) => Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(title.toUpperCase(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: Brand.muted))),
            Container(
              decoration: BoxDecoration(color: Brand.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: Brand.line)),
              child: Column(children: [
                for (var i = 0; i < rows.length; i++) ...[if (i > 0) const Divider(height: 1, color: Brand.line), rows[i]],
              ]),
            ),
          ]),
        );

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), tooltip: 'Back', onPressed: () => context.pop()),
        title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            section('Spending', [
              ListTile(title: const Text('Weekly cap'), subtitle: const Text('Tap to change', style: TextStyle(fontSize: 12, color: Brand.muted)), onTap: () => _editCap(context, ref, cap), trailing: Text(rm(cap), style: const TextStyle(fontWeight: FontWeight.w800))),
              const CarrySwitch(),
              ListTile(
                title: const Text('Repeating entries'),
                subtitle: const Text('Rent, salary, subscriptions that log themselves', style: TextStyle(fontSize: 12, color: Brand.muted)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/recurring'),
              ),
            ]),
            section('Friends', [
              ListTile(
                title: const Text('Payment link'),
                subtitle: const Text('Added to the messages that ask friends to pay you back', style: TextStyle(fontSize: 12, color: Brand.muted)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _editPayLink(context, ref),
              ),
            ]),
            section('Reminders', [
              const NotifSwitch(kind: 'bills', title: 'Bill reminders', subtitle: '3 days and 1 day before, and on the due day, 9am'),
              const NotifSwitch(kind: 'daily', title: 'Evening nudge', subtitle: '9pm, only on days you have logged nothing'),
              const NotifSwitch(kind: 'weekly', title: 'Sunday summary', subtitle: 'How the week went, Sunday 8pm'),
              const NotifSwitch(kind: 'cap', title: 'Cap alert', subtitle: 'At 80% and 100% of the weekly cap. Never more than one nudge a day'),
              ListTile(
                title: const Text('Send a test notification'),
                subtitle: const Text('Check that Cukup can reach you on this phone', style: TextStyle(fontSize: 12, color: Brand.muted)),
                trailing: const Icon(Icons.notifications_active_outlined, color: Brand.forest),
                onTap: () async {
                  final svc = ref.read(notificationsProvider);
                  final messenger = ScaffoldMessenger.of(context);
                  if (!await svc.enabled() && !await svc.requestPermission()) {
                    messenger.showSnackBar(const SnackBar(content: Text('Notifications are off for Cukup. Turn them on in your phone settings.')));
                    return;
                  }
                  final err = await svc.showTest();
                  if (err != null) messenger.showSnackBar(SnackBar(content: Text(err)));
                },
              ),
            ]),
            section('App', [const UpdateTile()]),
            section('Security', [
              SwitchListTile(
                title: const Text('App lock'),
                subtitle: const Text('Fingerprint or phone PIN when you open Cukup', style: TextStyle(fontSize: 12, color: Brand.muted)),
                value: lock.enabled,
                activeThumbColor: Brand.paper,
                activeTrackColor: Brand.forest,
                onChanged: lock.ready ? (v) => _toggleLock(context, ref, v) : null,
              ),
            ]),
            section('Data', [
              ListTile(
                title: const Text('Sync'),
                subtitle: Text(pending > 0 ? '$syncText · $pending waiting' : syncText, style: TextStyle(fontSize: 12, color: sync.error != null ? Brand.danger : Brand.muted)),
                trailing: sync.running ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: Brand.forest)) : const Icon(Icons.sync, color: Brand.forest),
                onTap: sync.running ? null : () => ref.read(syncProvider.notifier).run(),
              ),
              ListTile(
                title: const Text('Export everything (CSV)'),
                subtitle: const Text('Opens the share sheet so you can save it to Drive or email it', style: TextStyle(fontSize: 12, color: Brand.muted)),
                trailing: const Icon(Icons.ios_share_rounded, color: Brand.forest),
                onTap: () async {
                  final all = ref.read(txnsProvider).asData?.value ?? const <Txn>[];
                  final cats = ref.read(categoriesProvider).asData?.value ?? const <Cat>[];
                  await exportCsv(context, all, {for (final c in cats) c.id: c.name}, label: 'all');
                },
              ),
              ListTile(title: const Text('Sign out', style: TextStyle(color: Brand.danger, fontWeight: FontWeight.w600)), onTap: () => _signOut(context, ref)),
            ]),
            const SizedBox(height: 8),
            const Center(child: Text('Cukup · Your data stays on your own server', style: TextStyle(fontSize: 12, color: Brand.muted))),
          ],
        ),
      ),
    );
  }
}
