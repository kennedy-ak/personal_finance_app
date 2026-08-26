import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/components.dart';
import '../../../core/design/sheets.dart';
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

  /// Pre-selects the kind, so the first-run cards can open straight into the
  /// right shape of account.
  final AccountKind? initialKind;

  const AccountEditorSheet({super.key, this.account, this.initialKind});

  static Future<bool?> show(
    BuildContext context, {
    Account? account,
    AccountKind? initialKind,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      // Without this the sheet opens inside the shell's Scaffold body and the
      // floating add button is painted on top of the form.
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          AccountEditorSheet(account: account, initialKind: initialKind),
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
    _minCtrl =
        TextEditingController(text: (a?.minBalance ?? 0).toStringAsFixed(2));
    _purposeCtrl = TextEditingController(text: a?.purpose ?? '');
    _kind = a?.kind ?? widget.initialKind ?? AccountKind.bank;
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
      final balance = double.tryParse(_balanceCtrl.text.replaceAll(',', '')) ?? 0;
      final minBalance = double.tryParse(_minCtrl.text.replaceAll(',', '')) ?? 0;

      if (_isNew) {
        await repo.create(
          name: _nameCtrl.text.trim(),
          openingBalance: balance,
          kind: _kind,
          liquidity: _liquidity,
          minBalance: minBalance,
          purpose:
              _purposeCtrl.text.trim().isEmpty ? null : _purposeCtrl.text.trim(),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save this account.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);

    return SheetSurface(
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SheetHeader(title: _isNew ? 'New account' : 'Edit account'),
              const SizedBox(height: 16),
              SheetField(
                label: 'Name',
                controller: _nameCtrl,
                hint: 'Fidelity Bank',
                textCapitalization: TextCapitalization.words,
                autofocus: _isNew,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Give it a name' : null,
              ),
              const SizedBox(height: 13),
              SegmentedChips<AccountKind>(
                label: 'Kind',
                // The three that cover almost everyone, in the order a
                // Ghanaian user would reach for them. The rest live under
                // Availability, where they actually change behaviour.
                options: const [
                  (AccountKind.bank, 'Bank'),
                  (AccountKind.momo, 'Mobile Money'),
                  (AccountKind.cash, 'Cash'),
                ],
                selected: _kind == AccountKind.savings ||
                        _kind == AccountKind.investment ||
                        _kind == AccountKind.credit
                    ? AccountKind.bank
                    : _kind,
                onChanged: (k) => setState(() => _kind = k),
              ),
              const SizedBox(height: 13),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: MoneyField(
                      label: _isNew ? 'Starting balance' : 'Balance',
                      controller: _balanceCtrl,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: MoneyField(
                      label: 'Floor',
                      controller: _minCtrl,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return null;
                        final n = double.tryParse(v.replaceAll(',', ''));
                        if (n == null || n < 0) return 'Zero or more';
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              Text(
                _isNew
                    ? 'The floor is what the app will never suggest dipping below.'
                    : 'Correcting the balance adjusts the opening figure, not '
                        'your history.',
                style: AppType.rowSub.copyWith(height: 1.4, color: t.inkFaint),
              ),
              const SizedBox(height: 16),
              SegmentedChips<Liquidity>(
                label: 'Availability',
                options: const [
                  (Liquidity.liquid, 'Spendable'),
                  (Liquidity.reserved, 'Reserved'),
                  (Liquidity.locked, 'Locked'),
                ],
                selected: _liquidity,
                onChanged: (l) => setState(() => _liquidity = l),
              ),
              const SizedBox(height: 7),
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
                style: AppType.rowSub.copyWith(height: 1.4, color: t.inkFaint),
              ),
              const SizedBox(height: 16),
              SheetField(
                label: 'What is it for? (optional)',
                controller: _purposeCtrl,
                hint: 'Rent and utilities leave from here',
                maxLines: 2,
              ),
              const SizedBox(height: 20),
              PrimaryButton(
                label: _isNew ? 'Create account' : 'Save account',
                loading: _saving,
                onPressed: _saving ? null : _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
