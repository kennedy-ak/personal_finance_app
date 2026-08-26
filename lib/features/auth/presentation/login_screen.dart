import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/design/components.dart';
import '../../../core/theme.dart';
import '../data/auth_repository.dart';
import 'auth_field.dart';

const _kLastEmail = 'last_email';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String? _error;
  String? _notice;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      final saved = p.getString(_kLastEmail);
      if (saved != null && mounted) setState(() => _emailCtrl.text = saved);
    });
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
      _notice = null;
    });
    try {
      final email = _emailCtrl.text.trim();
      await ref.read(authRepositoryProvider).signIn(
            email: email,
            password: _passwordCtrl.text,
          );
      final p = await SharedPreferences.getInstance();
      await p.setString(_kLastEmail, email);
      if (mounted) context.go('/');
    } catch (e) {
      setState(() => _error = _readable(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Supabase says "Invalid login credentials", which does not tell anyone
  /// which of the two fields to fix. The screen set answers that directly.
  String _readable(Object e) {
    final raw = e.toString().replaceFirst('AuthApiException: ', '');
    if (raw.toLowerCase().contains('invalid login credentials')) {
      return 'That password does not match this email. Try again or reset it.';
    }
    if (raw.toLowerCase().contains('email not confirmed')) {
      return 'This email is not confirmed yet. Check your inbox for the link.';
    }
    return raw;
  }

  Future<void> _resetPassword() async {
    final email = _emailCtrl.text.trim();
    if (!email.contains('@')) {
      setState(() => _error = 'Enter your email first, then tap reset.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).sendPasswordReset(email);
      if (mounted) {
        setState(() => _notice = 'Reset link sent to $email.');
      }
    } catch (e) {
      setState(() => _error = _readable(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    final hasError = _error != null;

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
                            onPressed: () => context.go('/splash'),
                            icon: Icon(Icons.arrow_back,
                                size: 22, color: t.inkMuted),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text('Welcome back',
                            style: AppType.display.copyWith(color: t.ink)),
                        const SizedBox(height: 26),
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
                          obscure: _obscure,
                          // The message lives in the banner below, so the
                          // field only carries the red border — one screen
                          // should not say the same thing twice.
                          hasError: hasError,
                          autofillHints: const [AutofillHints.password],
                          onToggleObscure: () =>
                              setState(() => _obscure = !_obscure),
                          validator: (v) => v == null || v.length < 6
                              ? 'Min 6 characters'
                              : null,
                          onSubmitted: (_) => _submit(),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 16),
                          AlertCard(
                            tone: AlertTone.critical,
                            eyebrow: 'Could not sign in',
                            message: _error!,
                          ),
                        ],
                        if (_notice != null) ...[
                          const SizedBox(height: 16),
                          AlertCard(
                            tone: AlertTone.info,
                            eyebrow: 'Check your email',
                            message: _notice!,
                          ),
                        ],
                        const SizedBox(height: 16),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _loading ? null : _resetPassword,
                            child: Text('Forgot password',
                                style: AppType.label
                                    .copyWith(fontSize: 13, color: t.brandInk)),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
                PrimaryButton(
                  label: 'Log in',
                  loading: _loading,
                  onPressed: _loading ? null : _submit,
                ),
                const SizedBox(height: 14),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _loading ? null : () => context.push('/signup'),
                  child: Text.rich(
                    TextSpan(
                      text: 'New here? ',
                      style: AppType.bodySmall.copyWith(
                          fontSize: 14, height: 1.0, color: t.inkMuted),
                      children: [
                        TextSpan(
                          text: 'Create an account',
                          style: AppType.label
                              .copyWith(fontSize: 14, color: t.brandInk),
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
