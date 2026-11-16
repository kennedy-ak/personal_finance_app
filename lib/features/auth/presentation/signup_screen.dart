import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/components.dart';
import '../../../core/theme.dart';
import '../data/auth_repository.dart';
import 'auth_field.dart';

/// Three fields, and a promise about what comes next.
///
/// Accounts are not asked for here. Signing up and describing your money are
/// two different jobs, and cramming them together is how people abandon both.
class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
      _info = null;
    });
    try {
      final res = await ref.read(authRepositoryProvider).signUp(
            email: _emailCtrl.text.trim(),
            password: _passwordCtrl.text,
            name: _nameCtrl.text,
          );
      if (!mounted) return;
      if (res.signedIn) {
        context.go('/');
      } else {
        setState(() => _info =
            'Account created. Log in and add your accounts.');
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);

    return Scaffold(
      backgroundColor: t.canvas,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                            alignment: Alignment.centerLeft,
                            onPressed: () =>
                                context.canPop() ? context.pop() : context.go('/login'),
                            icon: Icon(Icons.arrow_back,
                                size: 22, color: t.inkMuted),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text('Set up your money',
                            style: AppType.display.copyWith(color: t.ink)),
                        const SizedBox(height: 10),
                        Text('Three fields. You add accounts next.',
                            style: AppType.body.copyWith(
                                height: 1.5, color: t.inkMuted)),
                        const SizedBox(height: 26),
                        AuthField(
                          label: 'Name',
                          controller: _nameCtrl,
                          hint: 'Ama Mensah',
                          textCapitalization: TextCapitalization.words,
                          autofillHints: const [AutofillHints.name],
                          validator: (v) => v == null || v.trim().isEmpty
                              ? 'Tell us what to call you'
                              : null,
                        ),
                        const SizedBox(height: 16),
                        AuthField(
                          label: 'Email',
                          controller: _emailCtrl,
                          hint: 'you@example.com',
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          validator: (v) => v == null || !v.contains('@')
                              ? 'Enter a valid email'
                              : null,
                        ),
                        const SizedBox(height: 16),
                        AuthField(
                          label: 'Password',
                          controller: _passwordCtrl,
                          hint: 'At least 8 characters',
                          obscure: _obscure,
                          autofillHints: const [AutofillHints.newPassword],
                          onToggleObscure: () =>
                              setState(() => _obscure = !_obscure),
                          validator: (v) => v == null || v.length < 8
                              ? 'At least 8 characters'
                              : null,
                          onSubmitted: (_) => _submit(),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 16),
                          AlertCard(
                            tone: AlertTone.critical,
                            eyebrow: 'Could not create account',
                            message: _error!,
                          ),
                        ],
                        if (_info != null) ...[
                          const SizedBox(height: 16),
                          AlertCard(
                            tone: AlertTone.info,
                            eyebrow: 'Check your email',
                            message: _info!,
                          ),
                        ],
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
                Text(
                  'By continuing you agree to the terms and privacy notice.',
                  textAlign: TextAlign.center,
                  style: AppType.bodySmall
                      .copyWith(fontSize: 12, height: 1.5, color: t.inkFaint),
                ),
                const SizedBox(height: 14),
                PrimaryButton(
                  label: 'Create account',
                  loading: _loading,
                  onPressed: _loading ? null : _submit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
