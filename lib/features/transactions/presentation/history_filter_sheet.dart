import 'package:flutter/material.dart';

import '../../../core/design/components.dart';
import '../../../core/theme.dart';
import '../domain/transaction.dart';

/// What is currently narrowing the history list.
///
/// Immutable so the sheet can work on a copy and the screen only commits when
/// the user taps the button — backing out of a sheet should leave the list
/// exactly as they found it.
@immutable
class HistoryFilters {
  final TxnType? type;
  final String? accountId;
  final String? category;

  const HistoryFilters({this.type, this.accountId, this.category});

  int get count => [type, accountId, category].where((x) => x != null).length;

  bool matches(Txn t) {
    if (type != null && t.type != type) return false;
    if (accountId != null && t.accountId != accountId) return false;
    if (category != null && t.category != category) return false;
    return true;
  }

  HistoryFilters copyWith({
    TxnType? type,
    String? accountId,
    String? category,
    bool clearType = false,
    bool clearAccount = false,
    bool clearCategory = false,
  }) =>
      HistoryFilters(
        type: clearType ? null : (type ?? this.type),
        accountId: clearAccount ? null : (accountId ?? this.accountId),
        category: clearCategory ? null : (category ?? this.category),
      );
}

/// Type, account, category — three groups of pills and a button that says how
/// many rows the choice will leave.
///
/// The count on the button is the point: it tells you whether the filter you
/// just built is worth applying before you apply it.
Future<HistoryFilters?> showHistoryFilterSheet({
  required BuildContext context,
  required HistoryFilters current,
  required Map<String, String> accounts,
  required List<String> categories,
  required int Function(HistoryFilters) countFor,
}) {
  return showModalBottomSheet<HistoryFilters>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _FilterSheet(
      initial: current,
      accounts: accounts,
      categories: categories,
      countFor: countFor,
    ),
  );
}

class _FilterSheet extends StatefulWidget {
  final HistoryFilters initial;
  final Map<String, String> accounts;
  final List<String> categories;
  final int Function(HistoryFilters) countFor;

  const _FilterSheet({
    required this.initial,
    required this.accounts,
    required this.categories,
    required this.countFor,
  });

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late HistoryFilters _draft = widget.initial;

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    final count = widget.countFor(_draft);
    final accountIds = widget.accounts.keys.toList();

    return SheetSurface(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetHeader(
              title: 'Filter',
              action: _draft.count == 0 ? null : 'Reset',
              onAction: () => setState(() => _draft = const HistoryFilters()),
            ),
            const SizedBox(height: 20),
            const GroupLabel('Type'),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final type in TxnType.values)
                  SelectChip(
                    label: type.label,
                    selected: _draft.type == type,
                    onTap: () => setState(() => _draft = _draft.type == type
                        ? _draft.copyWith(clearType: true)
                        : _draft.copyWith(type: type)),
                  ),
              ],
            ),
            if (accountIds.isNotEmpty) ...[
              const SizedBox(height: 20),
              const GroupLabel('Account'),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  for (final id in accountIds)
                    SelectChip(
                      label: widget.accounts[id]!,
                      selected: _draft.accountId == id,
                      onTap: () => setState(() =>
                          _draft = _draft.accountId == id
                              ? _draft.copyWith(clearAccount: true)
                              : _draft.copyWith(accountId: id)),
                    ),
                ],
              ),
            ],
            if (widget.categories.isNotEmpty) ...[
              const SizedBox(height: 20),
              const GroupLabel('Category'),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  for (final c in widget.categories)
                    SelectChip(
                      label: c,
                      selected: _draft.category == c,
                      onTap: () => setState(() => _draft = _draft.category == c
                          ? _draft.copyWith(clearCategory: true)
                          : _draft.copyWith(category: c)),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 24),
            PrimaryButton(
              label: count == 0
                  ? 'No transactions match'
                  : 'Show $count transaction${count == 1 ? '' : 's'}',
              // A filter that would empty the list can still be applied — the
              // no-results screen explains itself and offers the way back.
              onPressed: () => Navigator.pop(context, _draft),
            ),
            if (count == 0) ...[
              const SizedBox(height: 8),
              Text(
                'Applying this shows the no-results screen.',
                textAlign: TextAlign.center,
                style: AppType.bodySmall
                    .copyWith(fontSize: 12, color: t.inkFaint),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
