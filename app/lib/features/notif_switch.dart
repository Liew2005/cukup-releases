import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../theme/theme.dart';

/// One on/off switch for a kind of reminder (bills, daily, weekly, cap).
class NotifSwitch extends ConsumerStatefulWidget {
  const NotifSwitch({super.key, required this.kind, required this.title, required this.subtitle});
  final String kind;
  final String title;
  final String subtitle;
  @override
  ConsumerState<NotifSwitch> createState() => _NotifSwitchState();
}

class _NotifSwitchState extends ConsumerState<NotifSwitch> {
  bool _on = true;

  @override
  void initState() {
    super.initState();
    ref.read(notificationsProvider).isOn(widget.kind).then((v) {
      if (mounted) setState(() => _on = v);
    });
  }

  @override
  Widget build(BuildContext context) => SwitchListTile(
        title: Text(widget.title),
        subtitle: Text(widget.subtitle, style: const TextStyle(fontSize: 12, color: Brand.muted)),
        value: _on,
        activeThumbColor: Brand.paper,
        activeTrackColor: Brand.forest,
        onChanged: (v) {
          setState(() => _on = v);
          ref.read(notificationsProvider).setOn(widget.kind, v).catchError((_) {});
        },
      );
}
