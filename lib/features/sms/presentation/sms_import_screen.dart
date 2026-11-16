import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/components.dart';
import '../../../core/design/sheets.dart';
import '../../../core/design/tokens.dart';
import '../../../core/formatters.dart';
import '../../../core/theme.dart';
import '../../accounts/data/account_repository.dart';
import '../../accounts/domain/account.dart';
import '../../categories/data/category_repository.dart';
import '../../categories/domain/category.dart';
import '../../transactions/data/transaction_repository.dart';
import '../../transactions/domain/transaction.dart';
import '../data/sms_import_repository.dart';
import '../data/sms_scan_controller.dart';
import '../domain/bank_sms_parser.dart';
import '../domain/parsed_sms.dart';
import '../domain/sms_routing.dart';

/// The SMS import screen: link senders to accounts, sweep the inbox, and
/// answer whatever the sweep could not decide on its own.
///
/// Nothing here imports money silently — a message becomes a transaction only
/// through a learned rule or a human answer in the review queue.
class SmsImportScreen extends ConsumerStatefulWidget {
  const SmsImportScreen({super.key});

  @override
  ConsumerState<SmsImportScreen> createState() => _SmsImportScreenState();
}

class _SmsImportScreenState extends ConsumerState<SmsImportScreen> {
  void _bumpSms() => ref.read(smsRefreshProvider.notifier).state++;

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    final scan = ref.watch(smsScanControllerProvider);
    final linksAsync = ref.watch(smsLinksProvider);
    final inboxAsync = ref.watch(smsInboxProvider);
    final rulesAsync = ref.watch(smsRulesProvider);
    final accounts = ref.watch(activeAccountsProvider).value ?? const <Account>[];

    final links = linksAsync.value ?? const <SmsAccountLink>[];
    final inbox = inboxAsync.value ?? const <SmsInboxItem>[];
    final rules = rulesAsync.value ?? const <SmsRoutingRule>[];

    return Scaffold(
      backgroundColor: t.canvas,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                alignment: Alignment.centerLeft,
                onPressed: () =>
                    context.canPop() ? context.pop() : context.go('/settings'),
                icon: Icon(Icons.arrow_back, size: 22, color: t.inkMuted),
              ),
            ),
            const SizedBox(height: 12),
            Text('SMS import', style: AppType.title.copyWith(color: t.ink)),
            const SizedBox(height: 8),
            Text(
              'Read the alerts your bank and MoMo already send and put them '
              'on the books. Money is imported only when a learned rule says '
              'where it belongs; everything else waits below for your answer.',
              style: AppType.bodySmall.copyWith(height: 1.55, color: t.inkMuted),
            ),

            const SizedBox(height: 18),
            const GroupLabel('Senders'),
            RowGroup(
              children: [
                for (final parser in kBankSmsParsers)
                  _SenderRow(
                    parser: parser,
                    link: links.where((l) => l.parserId == parser.id).firstOrNull,
                    accounts: accounts,
                    onChanged: _bumpSms,
                  ),
              ],
            ),

            const SizedBox(height: 18),
            const GroupLabel('Inbox'),
            CediCard(
              child: Padding(
                padding: const EdgeInsets.all(15),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Scanning reads messages from your linked senders — '
                      'nothing else. It needs permission to read SMS and to '
                      'send notifications, runs in the background while you '
                      'use the rest of the app, and running it twice records '
                      'nothing twice.',
                      style: AppType.bodySmall
                          .copyWith(height: 1.5, color: t.inkMuted),
                    ),
                    const SizedBox(height: 14),
                    PrimaryButton(
                      label: scan.isRunning
                          ? 'Scanning — you can leave this page'
                          : 'Scan messages now',
                      loading: scan.isRunning,
                      onPressed: scan.isRunning
                          ? null
                          : () =>
                              ref.read(smsScanControllerProvider.notifier).start(),
                    ),
                    if (scan.phase == SmsScanPhase.done && scan.result != null) ...[
                      const SizedBox(height: 12),
                      Text(scan.result!.summaryLine,
                          textAlign: TextAlign.center,
                          style: AppType.bodySmall
                              .copyWith(height: 1.4, color: t.ink)),
                    ],
                    if (scan.phase == SmsScanPhase.failed && scan.error != null) ...[
                      const SizedBox(height: 12),
                      Text('Scan stopped: ${scan.error}',
                          textAlign: TextAlign.center,
                          style: AppType.bodySmall
                              .copyWith(height: 1.4, color: t.expense.ink)),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 18),
            GroupLabel('Needs review${inbox.isEmpty ? '' : ' · ${inbox.length}'}'),
            if (inboxAsync.isLoading)
              const CediCard(child: _CenteredNote('Reading the queue…'))
            else if (inbox.isEmpty)
              const CediCard(
                child: _CenteredNote(
                    'Nothing waiting. Scan your inbox and anything the rules '
                    'can\u2019t place lands here.'),
              )
            else
              for (final item in inbox.take(12))
                _ReviewCard(
                  item: item,
                  accounts: accounts,
                  onChanged: () {
                    _bumpSms();
                    bumpTransactions(ref);
                    bumpAccounts(ref);
                  },
                ),

            const SizedBox(height: 18),
            GroupLabel('Learned rules${rules.isEmpty ? '' : ' · ${rules.length}'}'),
            if (rules.isEmpty)
              const CediCard(
                child: _CenteredNote(
                    'Rules are learned when you tick \u2018remember\u2019 '
                    'while reviewing. After that, the same payee imports '
                    'itself.'),
              )
            else
              RowGroup(
                children: [
                  for (final rule in rules)
                    _RuleRow(
                      rule: rule,
                      accounts: accounts,
                      onChanged: _bumpSms,
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _CenteredNote extends StatelessWidget {
  final String text;
  const _CenteredNote(this.text);

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 18),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: AppType.bodySmall.copyWith(height: 1.5, color: t.inkMuted),
      ),
    );
  }
}

/// One sender in the Senders group: its name, and the account it speaks for.
class _SenderRow extends StatelessWidget {
  final BankSmsParser parser;
  final SmsAccountLink? link;
  final List<Account> accounts;
  final VoidCallback onChanged;

  const _SenderRow({
    required this.parser,
    required this.link,
    required this.accounts,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final account = link == null
        ? null
        : accounts.where((a) => a.id == link!.accountId).firstOrNull;
    return InkWell(
      onTap: () => _openLinkSheet(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(parser.displayName,
                      style: AppType.rowTitle
                          .copyWith(fontSize: 15, color: CediTokens.of(context).ink)),
                  const SizedBox(height: 3),
                  Text(
                    account == null
                        ? 'Not linked'
                        : 'Records into ${account.name}',
                    style: AppType.rowSub
                        .copyWith(color: CediTokens.of(context).inkMuted),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: CediTokens.of(context).inkMuted),
          ],
        ),
      ),
    );
  }

  Future<void> _openLinkSheet(BuildContext context) async {
    await showEditorSheet(
      context: context,
      builder: (ctx) => _LinkSheet(
        parser: parser,
        link: link,
        accounts: accounts,
        onChanged: onChanged,
      ),
    );
  }
}

/// The sheet that ties one sender to one account.
class _LinkSheet extends ConsumerStatefulWidget {
  final BankSmsParser parser;
  final SmsAccountLink? link;
  final List<Account> accounts;
  final VoidCallback onChanged;

  const _LinkSheet({
    required this.parser,
    required this.link,
    required this.accounts,
    required this.onChanged,
  });

  @override
  ConsumerState<_LinkSheet> createState() => _LinkSheetState();
}

class _LinkSheetState extends ConsumerState<_LinkSheet> {
  late String? _accountId = widget.link?.accountId;
  late final TextEditingController _identifiers = TextEditingController(
    text: widget.link?.identifiers.join(', '),
  );
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _identifiers.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_accountId == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(smsImportRepositoryProvider).saveLink(
            parserId: widget.parser.id,
            accountId: _accountId!,
            identifiers: _identifiers.text
                .split(',')
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toList(),
          );
      widget.onChanged();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not save: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _unlink() async {
    final link = widget.link;
    if (link == null) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(smsImportRepositoryProvider).deleteLink(link.id);
      widget.onChanged();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not unlink: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetHeader(title: widget.parser.displayName),
        const SizedBox(height: 10),
        Text(
          'Every alert from this sender that scans pick up is recorded into '
          'the linked account.',
          style: AppType.bodySmall.copyWith(height: 1.5, color: t.inkMuted),
        ),
        const SizedBox(height: 16),
        ChipGroup(
          label: 'Records into',
          options: [for (final a in widget.accounts) a.name],
          selected: _accountId == null
              ? null
              : widget.accounts
                  .where((a) => a.id == _accountId)
                  .map((a) => a.name)
                  .firstOrNull,
          onChanged: (name) => setState(() => _accountId = widget.accounts
              .where((a) => a.name == name)
              .map((a) => a.id)
              .firstOrNull),
        ),
        const SizedBox(height: 13),
        SheetField(
          label: 'Your identifiers (optional)',
          controller: _identifiers,
          hint: widget.parser.identifiersHint,
          textCapitalization: TextCapitalization.none,
        ),
        const SizedBox(height: 20),
        if (_error != null) ...[
          Text(_error!,
              style: AppType.bodySmall.copyWith(color: t.expense.ink)),
          const SizedBox(height: 10),
        ],
        PrimaryButton(
          label: _accountId == null ? 'Pick an account' : 'Save',
          loading: _busy,
          onPressed: _accountId == null || _busy ? null : _save,
        ),
        if (widget.link != null) ...[
          const SizedBox(height: 8),
          SecondaryButton(
              label: 'Stop importing this sender',
              onPressed: _busy ? null : _unlink),
        ],
      ],
    );
  }
}

/// One queued message, with the two answers it can get.
class _ReviewCard extends ConsumerWidget {
  final SmsInboxItem item;
  final List<Account> accounts;
  final VoidCallback onChanged;

  const _ReviewCard({
    required this.item,
    required this.accounts,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = CediTokens.of(context);
    final parsed = item.parsed;
    final headline = item.isUnparsed
        ? 'Could not read this message'
        : parsed?.summary ?? 'Needs a category';
    final figure = parsed?.amount == null
        ? null
        : formatMoney(parsed!.amount!);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: CediCard(
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${item.sender} · ${dayMonthFmt.format(item.receivedAt)}'
                      ' · ${timeFmt.format(item.receivedAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          AppType.label.copyWith(fontSize: 12, color: t.inkMuted),
                    ),
                  ),
                  if (figure != null)
                    Text(figure,
                        style: AppType.figure.copyWith(fontSize: 14, color: t.ink)),
                ],
              ),
              const SizedBox(height: 6),
              Text(headline,
                  style: AppType.rowTitle.copyWith(fontSize: 15, color: t.ink)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: t.canvas,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: t.hairline),
                ),
                child: Text(
                  item.body,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.bodySmall.copyWith(
                      fontSize: 12, height: 1.45, color: t.inkMuted),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: SecondaryButton(
                      label: 'Not money',
                      filled: true,
                      onPressed: () async {
                        try {
                          await ref
                              .read(smsImportRepositoryProvider)
                              .ignoreInboxItem(item.id);
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Could not update: $e')));
                          }
                          return;
                        }
                        onChanged();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: PrimaryButton(
                      label: 'Review',
                      onPressed: () => showEditorSheet(
                        context: context,
                        builder: (ctx) => _ReviewSheet(
                          item: item,
                          accounts: accounts,
                          onChanged: onChanged,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The sheet where a queued message becomes a transaction — and, if the user
/// lets it, a rule so its siblings never come back here.
class _ReviewSheet extends ConsumerStatefulWidget {
  final SmsInboxItem item;
  final List<Account> accounts;
  final VoidCallback onChanged;

  const _ReviewSheet({
    required this.item,
    required this.accounts,
    required this.onChanged,
  });

  @override
  ConsumerState<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends ConsumerState<_ReviewSheet> {
  late TxnType _type = _guessType();
  String? _category;
  String? _toAccountId;
  late final TextEditingController _amount = TextEditingController(
    text: widget.item.parsed?.amount == null
        ? ''
        : widget.item.parsed!.amount!.toStringAsFixed(2),
  );
  late DateTime _date = widget.item.receivedAt;
  late bool _remember = widget.item.parsed?.counterparty != null;
  bool _saving = false;
  String? _error;

  TxnType _guessType() {
    final d = widget.item.parsed?.direction;
    if (d == SmsDirection.credit) return TxnType.income;
    if (d == SmsDirection.debit) return TxnType.expense;
    return TxnType.expense;
  }

  /// The account the linked sender records into — the sender's own address
  /// matched back through the links table is overkill here; the parsed
  /// parser_id carries it.
  String? get _fromAccountId => widget.item.parsed == null
      ? null
      : ref
          .read(smsLinksProvider)
          .value
          ?.where((l) => l.parserId == widget.item.parsed!.parserId)
          .map((l) => l.accountId)
          .firstOrNull;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  List<Category> _categoriesForType(List<Category> all) {
    final kind = _type == TxnType.income
        ? CategoryKind.income
        : CategoryKind.expense;
    return all.where((c) => c.kind == kind && !c.isHidden).toList();
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amount.text.replaceAll(',', ''));
    if (amount == null || amount <= 0) return;
    final fromId = _fromAccountId;
    if (fromId == null) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(smsImportRepositoryProvider).resolveReview(
            item: widget.item,
            type: _type,
            accountId: fromId,
            counterpartAccountId:
                _type == TxnType.transfer ? _toAccountId : null,
            amount: amount,
            date: _date,
            category: _type == TxnType.transfer ? null : _category,
            description: widget.item.parsed?.summary,
            rememberRule: _remember,
          );
      widget.onChanged();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not save: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    final categories = _categoriesForType(
        ref.watch(allCategoriesProvider).value ?? const <Category>[]);
    final transferAccounts =
        widget.accounts.where((a) => a.id != _fromAccountId).toList();
    final canSave = (double.tryParse(_amount.text.replaceAll(',', '')) ?? 0) > 0 &&
        (_type != TxnType.transfer || _toAccountId != null) &&
        (_type == TxnType.transfer || _category != null) &&
        _fromAccountId != null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetHeader(title: 'Review message'),
        const SizedBox(height: 10),
        Text(
          widget.item.isUnparsed
              ? 'This message could not be read automatically. Enter what it '
                  'says happened.'
              : widget.item.parsed?.summary ?? 'Confirm where this belongs.',
          style: AppType.bodySmall.copyWith(height: 1.5, color: t.inkMuted),
        ),
        const SizedBox(height: 14),
        MoneyField(label: 'Amount', controller: _amount),
        const SizedBox(height: 6),
        PickerRow(
          label: 'Date',
          value: dateLongFmt.format(_date),
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _date,
              firstDate: DateTime(2000),
              lastDate: DateTime.now().add(const Duration(days: 1)),
            );
            if (picked != null) setState(() => _date = picked);
          },
        ),
        const SizedBox(height: 10),
        SegmentedChips<TxnType>(
          label: 'What happened',
          selected: _type,
          options: const [
            (TxnType.expense, 'Expense'),
            (TxnType.income, 'Income'),
            (TxnType.transfer, 'Transfer'),
          ],
          onChanged: (v) => setState(() {
            _type = v;
            _category = null;
            _toAccountId = null;
          }),
        ),
        const SizedBox(height: 10),
        if (_type == TxnType.transfer) ...[
          ChipGroup(
            label: 'To account',
            options: [for (final a in transferAccounts) a.name],
            selected: transferAccounts
                .where((a) => a.id == _toAccountId)
                .map((a) => a.name)
                .firstOrNull,
            onChanged: (name) => setState(() => _toAccountId = transferAccounts
                .where((a) => a.name == name)
                .map((a) => a.id)
                .firstOrNull),
          ),
        ] else ...[
          ChipGroup(
            label: 'Category',
            options: [for (final c in categories) c.name],
            selected: _category,
            onChanged: (c) => setState(() => _category = c),
          ),
        ],
        if (widget.item.parsed?.counterparty != null) ...[
          const SizedBox(height: 10),
          InkWell(
            onTap: () => setState(() => _remember = !_remember),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Icon(
                    _remember
                        ? Icons.check_box
                        : Icons.check_box_outline_blank,
                    size: 20,
                    color: _remember ? t.brandInk : t.inkMuted,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Remember ${widget.item.parsed!.counterparty} — next '
                      'time this imports itself',
                      style:
                          AppType.bodySmall.copyWith(color: t.inkBody, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        if (_error != null) ...[
          Text(_error!,
              style: AppType.bodySmall.copyWith(color: t.expense.ink)),
          const SizedBox(height: 10),
        ],
        PrimaryButton(
          label: 'Add to records',
          loading: _saving,
          onPressed: canSave && !_saving ? _save : null,
        ),
      ],
    );
  }
}

/// One learned rule, stated in words: who it matches and where it puts money.
class _RuleRow extends ConsumerWidget {
  final SmsRoutingRule rule;
  final List<Account> accounts;
  final VoidCallback onChanged;

  const _RuleRow({
    required this.rule,
    required this.accounts,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = CediTokens.of(context);
    final counterpart = rule.counterpartAccountId == null
        ? null
        : accounts
            .where((a) => a.id == rule.counterpartAccountId)
            .map((a) => a.name)
            .firstOrNull;
    final destination = rule.txnType == TxnType.transfer
        ? 'Transfer ${counterpart == null ? '' : '· $counterpart'}'
        : '${rule.txnType == TxnType.income ? 'Income' : 'Expense'} · ${rule.category}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(rule.matchText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.rowTitle.copyWith(fontSize: 14, color: t.ink)),
                const SizedBox(height: 3),
                Text(destination,
                    style: AppType.rowSub.copyWith(color: t.inkMuted)),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.delete_outline, size: 19, color: t.inkMuted),
            onPressed: () async {
              try {
                await ref.read(smsImportRepositoryProvider).deleteRule(rule.id);
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text('Could not delete: $e')));
                }
                return;
              }
              onChanged();
            },
          ),
        ],
      ),
    );
  }
}
