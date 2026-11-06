import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/format.dart';
import '../core/ledger.dart';
import '../core/time.dart';
import '../data/ledger.dart';
import '../data/providers.dart';
import '../theme/theme.dart';
import 'friend_picker.dart';

/// Home card: how much friends owe you, or a nudge to start. Opens the friends list.
class FriendsCard extends ConsumerWidget {
  const FriendsCard({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = ref.watch(ledgerProvider);
    final owed = l.totalOwed;
    return InkWell(
      onTap: () => context.push('/friends'),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(color: Brand.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: Brand.line)),
        child: Row(children: [
          const Icon(Icons.group_outlined, color: Brand.forest),
          const SizedBox(width: 12),
          Expanded(
            child: Text(owed > 0 ? 'Friends owe you ${rm(owed)}' : (l.friends.isEmpty ? 'Split bills with friends' : 'Friends are all paid up'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ),
          const Icon(Icons.chevron_right, color: Brand.muted),
        ]),
      ),
    );
  }
}

class FriendsPage extends ConsumerWidget {
  const FriendsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = ref.watch(ledgerProvider);
    final friends = [...l.friends]..sort((a, b) => l.balanceOf(b.id).compareTo(l.balanceOf(a.id)));
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), tooltip: 'Back', onPressed: () => context.pop()),
        title: const Text('Friends', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [IconButton(icon: const Icon(Icons.person_add_alt_1_outlined), tooltip: 'Add friend', onPressed: () => showFriendDialog(context, ref))],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          children: [
            const Text('Owed to you', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Brand.muted)),
            const SizedBox(height: 4),
            Text(rm(l.totalOwed), style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w800, letterSpacing: -1.5, color: Brand.forest)),
            const SizedBox(height: 18),
            if (friends.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('No friends yet. Add one, then split a receipt or a Quick add with them and the app keeps count of who owes what.', style: TextStyle(color: Brand.muted, height: 1.4)),
              ),
            for (final f in friends) _FriendTile(friend: f, balance: l.balanceOf(f.id)),
          ],
        ),
      ),
    );
  }
}

class _FriendTile extends StatelessWidget {
  const _FriendTile({required this.friend, required this.balance});
  final Friend friend;
  final int balance;

  @override
  Widget build(BuildContext context) {
    final owes = balance > 0;
    final credit = balance < 0;
    return InkWell(
      onTap: () => context.push('/friends/${friend.id}'),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: Brand.line))),
        child: Row(children: [
          Expanded(child: Text(friend.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
          Text(owes ? 'owes ${rm(balance)}' : (credit ? 'credit ${rm(-balance)}' : 'settled'), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: owes ? Brand.forest : Brand.muted)),
          const SizedBox(width: 6),
          const Icon(Icons.chevron_right, color: Brand.muted),
        ]),
      ),
    );
  }
}

class FriendDetailPage extends ConsumerWidget {
  const FriendDetailPage({super.key, required this.id});
  final String id;

  Future<int?> _askAmount(BuildContext context, String title, int initial) {
    final c = TextEditingController(text: initial > 0 ? (initial / 100).toStringAsFixed(2) : '');
    return showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(controller: c, autofocus: true, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(prefixText: 'RM ')),
        actions: [
          TextButton(onPressed: () => ctx.pop(), child: const Text('Cancel')),
          TextButton(onPressed: () => ctx.pop(parseCents(c.text)), child: const Text('OK', style: TextStyle(fontWeight: FontWeight.w800))),
        ],
      ),
    );
  }

  Future<void> _paid(BuildContext context, WidgetRef ref, Friend f, int balance) async {
    final v = await _askAmount(context, '${f.name} paid you', balance > 0 ? balance : 0);
    if (v == null || v <= 0) return;
    await ref.read(ledgerProvider.notifier).addPayment(f.id, v);
  }

  Future<void> _remind(BuildContext context, WidgetRef ref, Friend f, Ledger l) async {
    final link = await loadPayLink(ref.read(dbProvider));
    final msg = reminderMessage(name: f.name, open: l.openDebts(f.id), payLink: link);
    if (!context.mounted) return;
    final wa = whatsappNumber(f.phone);
    final pick = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 8), child: Text(msg, maxLines: 6, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: Brand.muted))),
          ListTile(leading: const Icon(Icons.qr_code_2), title: const Text('Share with my QR'), subtitle: const Text('Pick the WhatsApp chat'), onTap: () => ctx.pop('share')),
          if (wa != null) ListTile(leading: const Icon(Icons.chat_outlined), title: Text('Open ${f.name}\'s WhatsApp'), subtitle: const Text('Message only, no QR'), onTap: () => ctx.pop('chat')),
          ListTile(leading: const Icon(Icons.copy_outlined), title: const Text('Copy message'), onTap: () => ctx.pop('copy')),
        ]),
      ),
    );
    if (pick == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (pick == 'copy') {
        await Clipboard.setData(ClipboardData(text: msg));
        messenger.showSnackBar(const SnackBar(content: Text('Message copied.')));
      } else if (pick == 'chat') {
        final ok = await launchUrl(Uri.parse('https://wa.me/$wa?text=${Uri.encodeComponent(msg)}'), mode: LaunchMode.externalApplication);
        if (!ok) messenger.showSnackBar(const SnackBar(content: Text('Could not open WhatsApp.')));
      } else {
        final data = await rootBundle.load('assets/tng_qr.png');
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/my-tng-qr.png');
        await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
        await SharePlus.instance.share(ShareParams(text: msg, files: [XFile(file.path, mimeType: 'image/png')]));
      }
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Could not share that. Try Copy message.')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = ref.watch(ledgerProvider);
    final f = l.friend(id);
    if (f == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('This friend is gone.')));
    final balance = l.balanceOf(id);
    final open = l.openDebts(id).reversed.toList();
    final payments = l.payments.where((p) => p.friendId == id).toList()..sort((a, b) => b.date.compareTo(a.date));
    final notifier = ref.read(ledgerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), tooltip: 'Back', onPressed: () => context.pop()),
        title: Text(f.name, style: const TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(icon: const Icon(Icons.edit_outlined), tooltip: 'Edit', onPressed: () => showFriendDialog(context, ref, existing: f)),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete friend',
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text('Delete ${f.name}?'),
                  content: const Text('Their bills and payments are deleted too.'),
                  actions: [
                    TextButton(onPressed: () => ctx.pop(false), child: const Text('Cancel')),
                    TextButton(onPressed: () => ctx.pop(true), child: const Text('Delete', style: TextStyle(color: Brand.danger))),
                  ],
                ),
              );
              if (ok == true) {
                await notifier.deleteFriend(id);
                if (context.mounted) context.pop();
              }
            },
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          children: [
            Text(balance > 0 ? 'Owes you' : (balance < 0 ? 'Credit' : 'All settled'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Brand.muted)),
            const SizedBox(height: 4),
            Text(rm(balance.abs()), style: TextStyle(fontSize: 44, fontWeight: FontWeight.w800, letterSpacing: -1.5, color: balance > 0 ? Brand.forest : Brand.muted)),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: FilledButton(onPressed: () => _paid(context, ref, f, balance), child: const Text('Got paid'))),
              const SizedBox(width: 12),
              Expanded(child: OutlinedButton(onPressed: balance > 0 ? () => _remind(context, ref, f, l) : null, child: const Text('Remind'))),
            ]),
            const SizedBox(height: 24),
            if (open.isNotEmpty) const Text('Bills', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            for (final o in open)
              Dismissible(
                key: ValueKey(o.debt.id),
                direction: DismissDirection.endToStart,
                confirmDismiss: (_) async =>
                    await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Delete this bill?'),
                        content: Text('${o.debt.title} · ${rm(o.debt.cents)} will no longer count as owed.'),
                        actions: [
                          TextButton(onPressed: () => ctx.pop(false), child: const Text('Cancel')),
                          TextButton(onPressed: () => ctx.pop(true), child: const Text('Delete', style: TextStyle(color: Brand.danger))),
                        ],
                      ),
                    ) ??
                    false,
                onDismissed: (_) => notifier.deleteDebt(o.debt.id),
                background: Container(color: Brand.danger.withValues(alpha: 0.15), alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), child: const Icon(Icons.delete_outline, color: Brand.danger)),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: const BoxDecoration(border: Border(top: BorderSide(color: Brand.line))),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${o.debt.title} · ${shortDate(o.debt.date)}', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: o.settled ? Brand.muted : Brand.ink)),
                        if (o.debt.items.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(o.debt.items.join(', '), style: const TextStyle(fontSize: 13, color: Brand.muted))),
                      ]),
                    ),
                    const SizedBox(width: 12),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text(o.settled ? 'paid' : rm(o.leftCents), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: o.settled ? Brand.muted : Brand.forest)),
                      if (!o.settled && o.leftCents != o.debt.cents) Text('of ${rm(o.debt.cents)}', style: const TextStyle(fontSize: 12, color: Brand.muted)),
                    ]),
                  ]),
                ),
              ),
            if (payments.isNotEmpty) ...[
              const SizedBox(height: 24),
              const Text('Payments', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              for (final p in payments)
                Dismissible(
                  key: ValueKey(p.id),
                  direction: DismissDirection.endToStart,
                  onDismissed: (_) => notifier.deletePayment(p.id),
                  background: Container(color: Brand.danger.withValues(alpha: 0.15), alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), child: const Icon(Icons.delete_outline, color: Brand.danger)),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: const BoxDecoration(border: Border(top: BorderSide(color: Brand.line))),
                    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text('Paid you · ${shortDate(p.date)}', style: const TextStyle(fontSize: 15)),
                      Text(rm(p.cents), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ),
              const Padding(padding: EdgeInsets.only(top: 8), child: Text('Swipe a bill or payment left to delete it.', style: TextStyle(fontSize: 12, color: Brand.muted))),
            ],
          ],
        ),
      ),
    );
  }
}
