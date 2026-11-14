import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/api.dart';
import '../data/db.dart';
import '../data/providers.dart';
import '../theme/theme.dart';
import 'chips.dart';

/// Settings > Categories: add your own, rename, reorder, remove, and choose which ones stay out of the weekly cap.
/// Categories live on the server, so changes need a connection (like the weekly cap).
class CategoriesPage extends ConsumerStatefulWidget {
  const CategoriesPage({super.key});
  @override
  ConsumerState<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends ConsumerState<CategoriesPage> {
  bool _busy = false;

  bool _fixed(Cat c) => c.name == 'Other' || c.name == 'Other income';

  /// Runs a change on the server, then reloads the list. Shows why when it fails.
  Future<void> _run(Future<void> Function(ApiClient api) change, {String? done}) async {
    if (_busy) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await change(ref.read(apiProvider));
      await refreshCategories(ref.read(apiProvider), ref.read(dbProvider));
      if (done != null) messenger.showSnackBar(SnackBar(content: Text(done)));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.isNetwork ? 'Could not save. Changing categories needs a connection.' : e.message)));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Could not save. Try again.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit({Cat? cat, String kind = 'spend'}) async {
    final name = TextEditingController(text: cat?.name ?? '');
    var k = cat?.kind ?? kind;
    var cap = cat?.capDefault ?? true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(cat == null ? 'New category' : 'Edit category'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(controller: name, autofocus: cat == null, enabled: cat == null || !_fixed(cat), maxLength: 30, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Name')),
            if (cat == null) ...[
              const SizedBox(height: 4),
              PickChips<String>(options: const {'spend': 'Spending', 'income': 'Income'}, selected: k, onSelected: (v) => set(() => k = v)),
            ],
            if (k == 'spend')
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Counts toward weekly cap'),
                subtitle: Text(cap ? 'New entries here come off your week' : 'New entries here stay out of your week', style: const TextStyle(fontSize: 12, color: Brand.muted)),
                value: cap,
                activeThumbColor: Brand.paper,
                activeTrackColor: Brand.forest,
                onChanged: (v) => set(() => cap = v),
              ),
          ]),
          actions: [
            TextButton(onPressed: () => c.pop(false), child: const Text('Cancel')),
            TextButton(onPressed: () => c.pop(true), child: const Text('Save', style: TextStyle(color: Brand.forest, fontWeight: FontWeight.w800))),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final n = name.text.trim();
    if (n.isEmpty) return;
    if (cat == null) {
      await _run((api) => api.addCategory(n, k, cap), done: 'Added $n');
    } else {
      await _run((api) => api.putCategory(cat.id, {if (!_fixed(cat)) 'name': n, 'cap_default': cap}));
    }
  }

  Future<void> _delete(Cat cat) async {
    final to = cat.kind == 'income' ? 'Other income' : 'Other';
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Delete ${cat.name}?'),
        content: Text('Entries in ${cat.name} move to $to. They are not deleted.'),
        actions: [
          TextButton(onPressed: () => c.pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => c.pop(true), child: const Text('Delete', style: TextStyle(color: Brand.danger, fontWeight: FontWeight.w800))),
        ],
      ),
    );
    if (ok != true) return;
    await _run((api) => api.deleteCategory(cat.id), done: '${cat.name} deleted. Its entries are now in $to.');
    ref.read(syncProvider.notifier).run(); // brings the moved entries down
  }

  /// Saves the new order for one list. Positions are spaced so the two lists never collide.
  Future<void> _reorder(List<Cat> list, int from, int to, int base) async {
    final next = [...list];
    final moved = next.removeAt(from);
    next.insert(to.clamp(0, next.length), moved);
    await _run((api) async {
      for (var i = 0; i < next.length; i++) {
        final order = base + i + 1;
        if (next[i].sortOrder != order) await api.putCategory(next[i].id, {'sort_order': order});
      }
    });
  }

  Widget _list(String title, List<Cat> cats, int base) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(title.toUpperCase(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: Brand.muted))),
      Container(
        decoration: BoxDecoration(color: Brand.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: Brand.line)),
        clipBehavior: Clip.antiAlias,
        child: ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          onReorderItem: (a, b) => _reorder(cats, a, b, base),
          children: [
            for (var i = 0; i < cats.length; i++)
              ListTile(
                key: ValueKey(cats[i].id),
                contentPadding: const EdgeInsets.only(left: 4, right: 4),
                leading: ReorderableDragStartListener(index: i, child: const Padding(padding: EdgeInsets.all(12), child: Icon(Icons.drag_handle, color: Brand.muted))),
                title: Text(cats[i].name, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: cats[i].kind == 'spend' && !cats[i].capDefault ? const Text('Stays out of the weekly cap', style: TextStyle(fontSize: 12, color: Brand.muted)) : null,
                onTap: () => _edit(cat: cats[i]),
                trailing: _fixed(cats[i]) ? null : IconButton(icon: const Icon(Icons.delete_outline), tooltip: 'Delete ${cats[i].name}', color: Brand.muted, onPressed: () => _delete(cats[i])),
              ),
          ],
        ),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final cats = ref.watch(categoriesProvider).asData?.value ?? const <Cat>[];
    final spend = cats.where((c) => c.kind == 'spend').toList();
    final income = cats.where((c) => c.kind == 'income').toList();
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), tooltip: 'Back', onPressed: () => context.pop()),
        title: const Text('Categories', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [IconButton(icon: const Icon(Icons.add), tooltip: 'New category', onPressed: _busy ? null : () => _edit())],
      ),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 28), children: [
          if (_busy) const Padding(padding: EdgeInsets.only(bottom: 10), child: LinearProgressIndicator(color: Brand.forest, backgroundColor: Brand.line)),
          const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: Text('Tap a category to rename it or change whether it counts toward your weekly cap. Hold the handle to reorder.', style: TextStyle(fontSize: 13, color: Brand.muted, height: 1.4)),
          ),
          _list('Spending', spend, 0),
          const SizedBox(height: 18),
          _list('Income', income, 100),
        ]),
      ),
    );
  }
}
