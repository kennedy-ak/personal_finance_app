import 'package:flutter/material.dart';

import '../../../core/category_icons.dart';
import '../../../core/theme.dart';
import '../domain/transaction.dart';

/// Shared look for a transaction row.
///
/// A transfer is neither red nor green — it is your own money changing seats,
/// and showing it as spending is what made the numbers lie in the first place.

Color colorForTxn(TxnType type) => switch (type) {
      TxnType.income => AppColors.income,
      TxnType.expense => AppColors.expense,
      TxnType.transfer => AppColors.accent,
    };

String signForTxn(TxnType type) => switch (type) {
      TxnType.income => '+',
      TxnType.expense => '-',
      TxnType.transfer => '',
    };

IconData iconForTxn(Txn t) => t.type == TxnType.transfer
    ? Icons.swap_horiz
    : iconForCategory(t.category);

/// Title line for a row: transfers read as a movement, not a category.
String titleForTxn(Txn t, {String? fromName, String? toName}) {
  if (t.type != TxnType.transfer) return t.category;
  if (fromName == null && toName == null) return 'Transfer';
  return '${fromName ?? 'Account'} → ${toName ?? 'Account'}';
}
