import 'package:flutter/material.dart';
import 'package:flutter_native_contact_picker/flutter_native_contact_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/ledger.dart';
import '../data/ledger.dart';
import '../theme/theme.dart';

/// Add a friend, or edit one when [existing] is given. Returns the saved friend, or null if cancelled.
Future<Friend?> showFriendDialog(BuildContext context, WidgetRef ref, {Friend? existing}) async {
  final name = TextEditingController(text: existing?.name ?? '');
  final phone = TextEditingController(text: existing?.phone ?? '');
  String? error;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(existing == null ? 'Add friend' : 'Edit friend'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () async {
                // The phone's own contact picker: Cukup only receives the one contact you tap, no access to the rest.
                try {
                  final c = await FlutterNativeContactPicker().selectPhoneNumber();
                  if (c == null) return;
                  setState(() {
                    if ((c.fullName ?? '').trim().isNotEmpty) name.text = c.fullName!.trim();
                    final number = c.selectedPhoneNumber ?? ((c.phoneNumbers?.isNotEmpty ?? false) ? c.phoneNumbers!.first : null);
                    if (number != null) phone.text = number;
                    error = null;
                  });
                } catch (_) {
                  setState(() => error = 'Could not open your contacts. Type the name instead.');
                }
              },
              icon: const Icon(Icons.contacts_outlined, size: 18),
              label: const Text('Pick from contacts'),
              style: TextButton.styleFrom(foregroundColor: Brand.forest, padding: EdgeInsets.zero),
            ),
          ),
          TextField(controller: name, autofocus: existing != null, textCapitalization: TextCapitalization.words, decoration: InputDecoration(labelText: 'Name', errorText: error)),
          const SizedBox(height: 12),
          TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'WhatsApp number (optional)', hintText: '012 345 6789')),
        ]),
        actions: [
          TextButton(onPressed: () => ctx.pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              if (name.text.trim().isEmpty) return setState(() => error = 'Give them a name');
              ctx.pop(true);
            },
            child: const Text('Save', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    ),
  );
  if (ok != true) return null;
  final notifier = ref.read(ledgerProvider.notifier);
  if (existing == null) return notifier.addFriend(name.text, phone: phone.text);
  await notifier.updateFriend(existing.id, name: name.text, phone: phone.text);
  return Friend(id: existing.id, name: name.text.trim(), phone: phone.text.trim());
}

/// Pick the friends who were there. Tapping a chip toggles it; "+ Friend" adds a new one and selects them.
class FriendChips extends ConsumerWidget {
  const FriendChips({super.key, required this.selected, required this.onChanged});
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final friends = ref.watch(ledgerProvider).friends;
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final f in friends)
        FilterChip(
          label: Text(f.name),
          selected: selected.contains(f.id),
          onSelected: (on) => onChanged(on ? {...selected, f.id} : ({...selected}..remove(f.id))),
          selectedColor: Brand.forest,
          labelStyle: TextStyle(color: selected.contains(f.id) ? Brand.paper : Brand.ink, fontWeight: FontWeight.w600),
          checkmarkColor: Brand.paper,
          backgroundColor: Brand.card,
          side: const BorderSide(color: Brand.line),
        ),
      ActionChip(
        avatar: const Icon(Icons.add, size: 18),
        label: const Text('Friend'),
        onPressed: () async {
          final f = await showFriendDialog(context, ref);
          if (f != null) onChanged({...selected, f.id});
        },
        backgroundColor: Brand.card,
        side: const BorderSide(color: Brand.line),
        labelStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ]);
  }
}
