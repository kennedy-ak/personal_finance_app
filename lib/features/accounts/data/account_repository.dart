import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../core/supabase_client.dart';
import '../domain/account.dart';

class AccountRepository {
  Future<List<Account>> list() async {
    final rows = await supabase.from('accounts').select().order('name');
    return (rows as List).map((r) => Account.fromJson(r as Map<String, dynamic>)).toList();
  }

  Future<Account> create(String name, double balance) async {
    final userId = supabase.auth.currentUser!.id;
    final row = await supabase
        .from('accounts')
        .insert({'name': name, 'balance': balance, 'user_id': userId})
        .select()
        .single();
    return Account.fromJson(row);
  }

  Future<void> updateBalance(String id, double balance) async {
    await supabase.from('accounts').update({'balance': balance}).eq('id', id);
  }

  Future<void> rename(String id, String name) async {
    await supabase.from('accounts').update({'name': name}).eq('id', id);
  }

  Future<void> delete(String id) async {
    await supabase.from('accounts').delete().eq('id', id);
  }
}

final accountRepositoryProvider = Provider((_) => AccountRepository());

final accountsProvider = FutureProvider<List<Account>>((ref) async {
  ref.watch(accountsRefreshProvider);
  return ref.watch(accountRepositoryProvider).list();
});

final accountsRefreshProvider = StateProvider<int>((_) => 0);

void bumpAccounts(WidgetRef ref) =>
    ref.read(accountsRefreshProvider.notifier).state++;
