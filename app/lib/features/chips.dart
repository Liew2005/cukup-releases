import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// A row of single-choice chips in the Cukup style.
class PickChips<T> extends StatelessWidget {
  const PickChips({super.key, required this.options, required this.selected, required this.onSelected});
  final Map<T, String> options;
  final T? selected;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) => Wrap(spacing: 8, runSpacing: 8, children: [
        for (final e in options.entries)
          ChoiceChip(
            label: Text(e.value),
            selected: selected == e.key,
            onSelected: (_) => onSelected(e.key),
            selectedColor: Brand.forest,
            labelStyle: TextStyle(color: selected == e.key ? Brand.paper : Brand.ink, fontWeight: FontWeight.w600),
            showCheckmark: false,
            backgroundColor: Brand.card,
            side: const BorderSide(color: Brand.line),
          ),
      ]);
}

class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Brand.muted)),
      );
}
