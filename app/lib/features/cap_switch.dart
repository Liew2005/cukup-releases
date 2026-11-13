import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// Spending in the Bills category (water, electricity, phone) is recorded but stays out of the weekly cap,
/// unless the person turns the switch on. Everything else counts by default.
bool capDefault(String? categoryName) => (categoryName ?? '').trim().toLowerCase() != 'bills';

/// "Counts toward weekly cap" switch shown under Paid with.
class CapSwitch extends StatelessWidget {
  const CapSwitch({super.key, required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Counts toward weekly cap'),
      subtitle: Text(
        value ? 'Comes off what you have left this week' : 'Recorded, but your weekly cap ignores it',
        style: const TextStyle(fontSize: 12, color: Brand.muted),
      ),
      value: value,
      activeThumbColor: Brand.paper,
      activeTrackColor: Brand.forest,
      onChanged: onChanged,
    );
  }
}
