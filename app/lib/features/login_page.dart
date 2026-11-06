import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api.dart';
import '../data/providers.dart';
import '../theme/theme.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});
  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _pw = TextEditingController();
  final _code = TextEditingController();
  bool _needsCode = false;
  bool _busy = false;
  bool _show = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    ref.read(apiProvider).totpRequired().then((v) {
      if (mounted) setState(() => _needsCode = v);
    });
  }

  Future<void> _submit() async {
    if (_pw.text.isEmpty || _busy) return;
    if (_needsCode && _code.text.replaceAll(' ', '').length != 6) {
      setState(() => _error = 'Enter the 6-digit code from your authenticator app.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authProvider.notifier).login(_pw.text, code: _needsCode ? _code.text.replaceAll(' ', '') : null);
      ref.read(syncProvider.notifier).run();
    } on ApiException catch (e) {
      setState(() => _error = switch (e.status) {
            0 => 'Cannot reach the server. Check your internet.',
            401 => _needsCode ? 'Wrong password or code.' : 'Wrong password.',
            429 => 'Too many tries. Wait a few minutes.',
            _ => e.message,
          });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _pw.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(flex: 2),
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(color: Brand.forest, borderRadius: BorderRadius.circular(16)),
                alignment: Alignment.center,
                child: const Text('C', style: TextStyle(color: Brand.paper, fontSize: 30, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(height: 20),
              Text('Cukup', style: t.displaySmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1)),
              const SizedBox(height: 6),
              Text('Spend what you planned. Keep the rest.', style: t.bodyLarge?.copyWith(color: Brand.muted)),
              const SizedBox(height: 36),
              TextField(
                controller: _pw,
                obscureText: !_show,
                autofillHints: const [AutofillHints.password],
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: 'Password',
                  errorText: _error,
                  suffixIcon: IconButton(
                    tooltip: _show ? 'Hide password' : 'Show password',
                    icon: Icon(_show ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                    onPressed: () => setState(() => _show = !_show),
                  ),
                ),
              ),
              if (_needsCode) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _code,
                  keyboardType: TextInputType.number,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  maxLength: 7,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                  decoration: const InputDecoration(labelText: '6-digit code', counterText: ''),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton(onPressed: _busy ? null : _submit, child: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Brand.paper)) : const Text('Sign in')),
              const Spacer(flex: 3),
            ],
          ),
        ),
      ),
    );
  }
}
