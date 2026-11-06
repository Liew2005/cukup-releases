import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/updater.dart';
import '../theme/theme.dart';

/// Settings row: current version, and an Update button when a newer build is out.
class UpdateTile extends ConsumerStatefulWidget {
  const UpdateTile({super.key});
  @override
  ConsumerState<UpdateTile> createState() => _UpdateTileState();
}

class _UpdateTileState extends ConsumerState<UpdateTile> {
  double? _progress;
  String? _message;

  Future<void> _install() async {
    final u = ref.read(updateProvider).asData?.value;
    if (u == null) return;
    setState(() {
      _progress = 0;
      _message = null;
    });
    final msg = await downloadAndInstall(u, (p) {
      if (mounted) setState(() => _progress = p);
    });
    if (mounted) {
      setState(() {
        _progress = null;
        _message = msg;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = ref.watch(appVersionProvider).asData?.value;
    final u = ref.watch(updateProvider).asData?.value;
    final checking = ref.watch(updateProvider).isLoading;
    final current = v == null ? 'Cukup' : 'Cukup ${v.name} (build ${v.build})';
    final String sub;
    if (_message != null) {
      sub = _message!;
    } else if (_progress != null) {
      sub = 'Downloading ${(_progress! * 100).round()}%';
    } else if (u != null) {
      sub = 'Version ${u.name} is ready${u.notes.isEmpty ? '' : '. ${u.notes}'}';
    } else {
      sub = checking ? 'Checking for updates…' : 'You have the latest version';
    }
    return ListTile(
      title: Text(current),
      subtitle: Text(sub, style: TextStyle(fontSize: 12, color: _message != null ? Brand.danger : Brand.muted)),
      trailing: u != null && _progress == null
          ? FilledButton(onPressed: _install, style: FilledButton.styleFrom(minimumSize: const Size(0, 40)), child: const Text('Update'))
          : TextButton(onPressed: checking || _progress != null ? null : () => ref.invalidate(updateProvider), child: const Text('Check', style: TextStyle(color: Brand.forest, fontWeight: FontWeight.w600))),
    );
  }
}
