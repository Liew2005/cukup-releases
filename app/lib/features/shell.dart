import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../theme/theme.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    final i = shell.currentIndex;
    Widget tab(int index, IconData icon, String label) {
      final on = i == index;
      return InkWell(
        onTap: () => shell.goBranch(index, initialLocation: index == i),
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 62,
          height: 52,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 24, color: on ? Brand.forest : Brand.muted),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 11, fontWeight: on ? FontWeight.w800 : FontWeight.w600, color: on ? Brand.forest : Brand.muted)),
          ]),
        ),
      );
    }

    return Scaffold(
      body: shell,
      bottomNavigationBar: Container(
        height: 84,
        decoration: const BoxDecoration(color: Brand.card, border: Border(top: BorderSide(color: Brand.line))),
        child: SafeArea(
          top: false,
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            tab(0, Icons.home_outlined, 'Home'),
            tab(1, Icons.list_rounded, 'Activity'),
            Semantics(
              label: 'Scan a receipt',
              button: true,
              child: InkWell(
                onTap: () => shell.goBranch(2),
                customBorder: const CircleBorder(),
                child: Container(width: 58, height: 58, decoration: const BoxDecoration(color: Brand.forest, shape: BoxShape.circle), child: const Icon(Icons.document_scanner_outlined, color: Brand.paper, size: 26)),
              ),
            ),
            tab(3, Icons.bar_chart_rounded, 'Insights'),
            tab(4, Icons.event_note_outlined, 'Bills'),
          ]),
        ),
      ),
    );
  }
}

class ComingSoon extends ConsumerWidget {
  const ComingSoon({super.key, required this.title, required this.note});
  final String title;
  final String note;
  @override
  Widget build(BuildContext context, WidgetRef ref) => SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(note, textAlign: TextAlign.center, style: const TextStyle(color: Brand.muted)),
            ]),
          ),
        ),
      );
}
