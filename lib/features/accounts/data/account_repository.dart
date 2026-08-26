import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../core/supabase_client.dart';
import '../domain/account.dart';

class AccountRepository {
  Future<List<Account>> list() async {
    final rows = await supabase
        .from('accounts')
        .select()
        .order('sort_order', ascending: true)
        .order('name', ascending: true);
    return (rows as List).map((r) => Account.fromJson(r as Map<String, dynamic>)).toList();
  }

  Future<Account> create({
    required String name,
    double openingBalance = 0,
    AccountKind kind = AccountKind.bank,
    Liquidity liquidity = Liquidity.liquid,
    double minBalance = 0,
    String? purpose,
    int sortOrder = 0,
  }) async {
    final userId = supabase.auth.currentUser!.id;
    final row = await supabase
        .from('accounts')
        .insert({
          'user_id': userId,
          'name': name,
          // A brand-new account has no transactions, so its balance is exactly
          // its opening balance. The DB trigger keeps them consistent after this.
          'opening_balance': openingBalance,
          'balance': openingBalance,
          'kind': kind.value,
          'liquidity': liquidity.value,
          'min_balance': minBalance,
          'purpose': purpose,
          'sort_order': sortOrder,
        })
        .select()
        .single();
    return Account.fromJson(row);
  }

  Future<void> update(
    String id, {
    String? name,
    AccountKind? kind,
    Liquidity? liquidity,
    double? minBalance,
    String? purpose,
    bool? isArchived,
    int? sortOrder,
  }) async {
    final patch = <String, dynamic>{
      'name': ?name,
      if (kind != null) 'kind': kind.value,
      if (liquidity != null) 'liquidity': liquidity.value,
      'min_balance': ?minBalance,
      if (purpose != null) 'purpose': purpose.isEmpty ? null : purpose,
      'is_archived': ?isArchived,
      'sort_order': ?sortOrder,
    };
    if (patch.isEmpty) return;
    await supabase.from('accounts').update(patch).eq('id', id);
  }

  /// Corrects the balance without inventing a transaction.
  ///
  /// The balance column itself is derived — the database recomputes it from
  /// opening balance plus transactions. To make the displayed balance land on
  /// [newBalance] we adjust the opening balance by the difference and let the
  /// trigger settle it.
  Future<void> reconcileBalance(Account account, double newBalance) async {
    final delta = newBalance - account.balance;
    if (delta.abs() < 0.005) return;
    await supabase
        .from('accounts')
        .update({'opening_balance': account.openingBalance + delta})
        .eq('id', account.id);
  }

  Future<void> rename(String id, String name) => update(id, name: name);

  Future<void> delete(String id) async {
    await supabase.from('accounts').delete().eq('id', id);
  }
}

final accountRepositoryProvider = Provider((_) => AccountRepository());

final accountsProvider = FutureProvider<List<Account>>((ref) async {
  ref.watch(accountsRefreshProvider);
  return ref.watch(accountRepositoryProvider).list();
});

/// Accounts the user actually transacts on — archived ones stay in history but
/// stop cluttering pickers and advice.
final activeAccountsProvider = FutureProvider<List<Account>>((ref) async {
  final all = await ref.watch(accountsProvider.future);
  return all.where((a) => !a.isArchived).toList();
});

final accountsRefreshProvider = StateProvider<int>((_) => 0);

void bumpAccounts(WidgetRef ref) =>
    ref.read(accountsRefreshProvider.notifier).state++;
