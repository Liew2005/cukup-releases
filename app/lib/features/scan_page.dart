import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../data/providers.dart';
import '../data/scan_service.dart';
import '../theme/theme.dart';

class ScanPage extends ConsumerStatefulWidget {
  const ScanPage({super.key});
  @override
  ConsumerState<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends ConsumerState<ScanPage> {
  final _picker = ImagePicker();
  bool _busy = false;
  String? _error;

  Future<void> _go(ImageSource source) async {
    if (_busy) return;
    setState(() => _error = null);
    final XFile? file;
    try {
      file = await _picker.pickImage(source: source, imageQuality: 88, maxWidth: 2400);
    } catch (_) {
      setState(() => _error = source == ImageSource.camera ? 'Could not open the camera.' : 'Could not open your photos.');
      return;
    }
    if (file == null) return;

    setState(() => _busy = true);
    try {
      final parsed = await ref.read(scanServiceProvider).scan(file.path);
      if (!mounted) return;
      context.push('/review', extra: parsed);
    } on ScanFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Something went wrong reading that receipt.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Scan a receipt', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.8)),
            const SizedBox(height: 8),
            const Text('Lay it flat, use good light, and get the whole receipt in the frame. Works without internet.', style: TextStyle(fontSize: 15, color: Brand.muted, height: 1.4)),
            const Spacer(),
            if (_busy)
              const Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  CircularProgressIndicator(color: Brand.forest),
                  SizedBox(height: 16),
                  Text('Reading your receipt…', style: TextStyle(fontWeight: FontWeight.w600)),
                ]),
              )
            else ...[
              if (_error != null)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: Brand.danger.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14), border: Border.all(color: Brand.danger.withValues(alpha: 0.4))),
                  child: Text(_error!, style: const TextStyle(color: Brand.danger, fontWeight: FontWeight.w600)),
                ),
              FilledButton.icon(onPressed: () => _go(ImageSource.camera), icon: const Icon(Icons.photo_camera_outlined), label: const Text('Take a photo')),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _go(ImageSource.gallery),
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Choose from gallery'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52), foregroundColor: Brand.forest, side: const BorderSide(color: Brand.line), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              ),
              const SizedBox(height: 8),
              TextButton(onPressed: () => context.push('/add'), child: const Text('Add by hand instead', style: TextStyle(color: Brand.muted, fontWeight: FontWeight.w600))),
            ],
            const Spacer(flex: 2),
          ],
        ),
      ),
    );
  }
}
