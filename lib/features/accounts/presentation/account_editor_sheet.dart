import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../data/account_repository.dart';
import '../domain/account.dart';

/// Captures what an account actually *is* — not just its name and number.
///
/// Kind, liquidity and the floor are what let the app answer "where should I
/// take this from?" instead of treating every account as an identical pot.
class AccountEditorSheet extends ConsumerStatefulWidget {
  /// Null creates a new account.
  final Account? account;

  const AccountEditorSheet({super.key, this.account});

  static Future<bool?> show(BuildContext context, {Account? account}) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      // Without this the sheet opens inside the shell's Scaffold body and the
      // floating add button is painted on top of the form.
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => AccountEditorSheet(account: account),
    );
  }

  @override
  ConsumerState<AccountEditorSheet> createState() => _AccountEditorSheetState();
}

class _AccountEditorSheetState extends ConsumerState<AccountEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _balanceCtrl;
  late final TextEditingController _minCtrl;
  late final TextEditingController _purposeCtrl;

  late AccountKind _kind;
  late Liquidity _liquidity;
  bool _saving = false;

  bool get _isNew => widget.account == null;

  @override
  void initState() {
    super.initState();
    final a = widget.account;
    _nameCtrl = TextEditingController(text: a?.name ?? '');
    _balanceCtrl =
        TextEditingController(text: (a?.balance ?? 0).toStringAsFixed(2));
    _minCtrl = TextEditingController(text: (a?.minBalance ?? 0).toStringAsFixed(2));
    _purposeCtrl = TextEditingController(text: a?.purpose ?? '');
    _kind = a?.kind ?? AccountKind.bank;
    _liquidity = a?.liquidity ?? Liquidity.liquid;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _balanceCtrl.dispose();
    _minCtrl.dispose();
    _purposeCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final repo = ref.read(accountRepositoryProvider);
    try {
      final balance = double.tryParse(_balanceCtrl.text) ?? 0;
      final minBalance = double.tryParse(_minCtrl.text) ?? 0;

      if (_isNew) {
        await repo.create(
          name: _nameCtrl.text.trim(),
          openingBalance: balance,
          kind: _kind,
          liquidity: _liquidity,
          minBalance: minBalance,
          purpose: _purposeCtrl.text.trim().isEmpty ? null : _purposeCtrl.text.trim(),
        );
      } else {
        final a = widget.account!;
        await repo.update(
          a.id,
          name: _nameCtrl.text.trim(),
          kind: _kind,
          liquidity: _liquidity,
          minBalance: minBalance,
          purpose: _purposeCtrl.text.trim(),
        );
        await repo.reconcileBalance(a, balance);
      }
      bumpAccounts(ref);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 18,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                _isNew ? 'New account' : 'Edit account',
                style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _nameCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  prefixIcon: Icon(Icons.label_outline),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _balanceCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: _isNew ? 'Starting balance' : 'Balance',
                  prefixText: 'GHS ',
                  helperText: _isNew
                      ? null
                      : 'Correcting this adjusts the opening balance, not your history.',
                  helperMaxLines: 2,
                  prefixIcon: const Icon(Icons.account_balance_wallet_outlined),
                ),
              ),
              const SizedBox(height: 20),
              const _FieldLabel('Account type'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final k in AccountKind.values)
                    ChoiceChip(
                      label: Text(k.label),
                      selected: _kind == k,
                      onSelected: (_) => setState(() => _kind = k),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              const _FieldLabel('Availability'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final l in Liquidity.values)
                    ChoiceChip(
                      label: Text(l.label),
                      selected: _liquidity == l,
                      onSelected: (_) => setState(() => _liquidity = l),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              // One line that changes with the choice, instead of three
              // permanent paragraphs.
              Text(
                switch (_liquidity) {
                  Liquidity.liquid => 'Counts towards what you can safely spend.',
                  Liquidity.reserved =>
                    'Kept aside for something. Shown separately, never offered.',
                  Liquidity.locked =>
                    'Long-term. Never counted as spendable money.',
                },
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _minCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Keep at least',
                  prefixText: 'GHS ',
                  prefixIcon: Icon(Icons.shield_outlined),
                  helperText: 'A floor the coach will not suggest dipping below.',
                  helperMaxLines: 2,
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return null;
                  final n = double.tryParse(v);
                  if (n == null || n < 0) return 'Enter zero or more';
                  return null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _purposeCtrl,
                maxLines: 2,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'What is it for? (optional)',
                  hintText: 'e.g. Rent and utilities leave from here',
                  prefixIcon: Icon(Icons.notes_outlined),
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  backgroundColor: AppColors.seed,
                ),
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.check),
                label: Text(_isNew ? 'Create account' : 'Save changes'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
      );
}
