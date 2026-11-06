import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/carry.dart';
import '../data/providers.dart';
import '../theme/theme.dart';

/// Settings switch: take last week's overspending off this week's cap. On by default.
class CarrySwitch extends ConsumerStatefulWidget {
  const CarrySwitch({super.key});
  @override
  ConsumerState<CarrySwitch> createState() => _CarrySwitchState();
}

class _CarrySwitchState extends ConsumerState<CarrySwitch> {
  bool _on = true;

  @override
  void initState() {
    super.initState();
    ref.read(dbProvider).getKv('setting.carry').then((v) {
      if (mounted) setState(() => _on = v != '0');
    });
  }

  @override
  Widget build(BuildContext context) => SwitchListTile(
        title: const Text('Carry overspending forward'),
        subtitle: const Text('Go over one week and the next week\'s cap shrinks to pay it back, by at most half the cap a week', style: TextStyle(fontSize: 12, color: Brand.muted)),
        value: _on,
        activeThumbColor: Brand.paper,
        activeTrackColor: Brand.forest,
        onChanged: (v) {
          setState(() => _on = v);
          setCarryOver(ref, v);
        },
      );
}
