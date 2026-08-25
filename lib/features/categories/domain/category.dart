import '../../transactions/domain/transaction.dart';

/// Which side of the ledger a category belongs to.
///
/// An expense 'Other' and an income 'Other' are two different categories that
/// happen to share a label, which is why every lookup is keyed by kind as well
/// as name.
enum CategoryKind {
  expense('expense', 'Expense'),
  income('income', 'Income');

  final String value;
  final String label;
  const CategoryKind(this.value, this.label);

  static CategoryKind fromValue(String s) =>
      values.firstWhere((k) => k.value == s, orElse: () => CategoryKind.expense);

  static CategoryKind forTxn(TxnType t) =>
      t == TxnType.income ? CategoryKind.income : CategoryKind.expense;
}

class Category {
  final String id;
  final String name;
  final CategoryKind kind;

  /// Key into kPickableIcons — a slug, not a codepoint. Null falls back to the
  /// name-based guess in iconForCategory.
  final String? icon;

  /// Kept out of the pickers without being removed from history.
  final bool isHidden;

  /// One of the categories seeded at signup rather than one the user wrote.
  final bool isBuiltin;

  final int sortOrder;

  const Category({
    required this.id,
    required this.name,
    required this.kind,
    required this.icon,
    required this.isHidden,
    required this.isBuiltin,
    required this.sortOrder,
  });

  factory Category.fromJson(Map<String, dynamic> j) => Category(
        id: j['id'] as String,
        name: j['name'] as String,
        kind: CategoryKind.fromValue((j['kind'] as String?) ?? 'expense'),
        icon: j['icon'] as String?,
        isHidden: (j['is_hidden'] as bool?) ?? false,
        isBuiltin: (j['is_builtin'] as bool?) ?? false,
        sortOrder: (j['sort_order'] as int?) ?? 0,
      );
}
