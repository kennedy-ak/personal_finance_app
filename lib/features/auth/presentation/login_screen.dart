import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme.dart';
import '../../../shared/widgets/app_logo.dart';
import '../data/auth_repository.dart';

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
      setState(() => _error = e.toString().replaceFirst('AuthApiException: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(
            height: 320,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.gradStart, AppColors.gradEnd],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(
                  children: [
                    const SizedBox(height: 36),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.18),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const AppLogo(size: 80),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Pursely',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Track. Plan. Grow.',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    const SizedBox(height: 36),
                    Card(
                      elevation: 6,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                      child: Padding(
                        padding: const EdgeInsets.all(22),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text('Welcome back',
                                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                              const SizedBox(height: 4),
                              Text('Sign in to continue',
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
                              const SizedBox(height: 22),
                              TextFormField(
                                controller: _emailCtrl,
                                keyboardType: TextInputType.emailAddress,
                                autofillHints: const [AutofillHints.email],
                                decoration: const InputDecoration(
                                  labelText: 'Email',
                                  prefixIcon: Icon(Icons.email_outlined),
                                ),
                                validator: (v) =>
                                    v == null || !v.contains('@') ? 'Enter a valid email' : null,
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _passwordCtrl,
                                obscureText: _obscure,
                                autofillHints: const [AutofillHints.password],
                                decoration: InputDecoration(
                                  labelText: 'Password',
                                  prefixIcon: const Icon(Icons.lock_outline),
                                  suffixIcon: IconButton(
                                    icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                                    onPressed: () => setState(() => _obscure = !_obscure),
                                  ),
                                ),
                                validator: (v) =>
                                    v == null || v.length < 6 ? 'Min 6 characters' : null,
                              ),
                              if (_error != null) ...[
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: AppColors.expense.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.error_outline,
                                          color: AppColors.expense, size: 18),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(_error!,
                                            style: const TextStyle(
                                                color: AppColors.expense, fontSize: 12)),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: 22),
                              FilledButton(
                                onPressed: _loading ? null : _submit,
                                child: _loading
                                    ? const SizedBox(
                                        height: 18,
                                        width: 18,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2, color: Colors.white))
                                    : const Text('Sign in'),
                              ),
                              const SizedBox(height: 12),
                              TextButton(
                                onPressed: _loading ? null : () => context.push('/signup'),
                                child: const Text("Don't have an account? Create one"),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
