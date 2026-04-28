import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../core/formatters.dart';
import '../../../core/supabase_client.dart';
import '../domain/transaction.dart';

class TransactionRepository {
  Future<List<Txn>> list({DateTime? from, DateTime? to}) async {
    var q = supabase.from('transactions').select();
    if (from != null) q = q.gte('date', dateFmt.format(from));
    if (to != null) q = q.lte('date', dateFmt.format(to));
    final rows = await q.order('date', ascending: false).order('created_at', ascending: false);
    return (rows as List).map((r) => Txn.fromJson(r as Map<String, dynamic>)).toList();
  }

  Future<Txn> create({
    required String accountId,
    required TxnType type,
    required double amount,
    required String category,
    String? description,
    required DateTime date,
  }) async {
    final userId = supabase.auth.currentUser!.id;
    final row = await supabase
        .from('transactions')
        .insert({
          'user_id': userId,
          'account_id': accountId,
          'type': type.label,
          'amount': amount,
          'category': category,
          'description': description,
          'date': dateFmt.format(date),
        })
        .select()
        .single();
    return Txn.fromJson(row);
  }

  Future<void> delete(String id) async {
    await supabase.from('transactions').delete().eq('id', id);
  }
}

final transactionRepositoryProvider = Provider((_) => TransactionRepository());

final transactionsRefreshProvider = StateProvider<int>((_) => 0);

final transactionsProvider = FutureProvider<List<Txn>>((ref) async {
  ref.watch(transactionsRefreshProvider);
  return ref.watch(transactionRepositoryProvider).list();
});

void bumpTransactions(WidgetRef ref) =>
    ref.read(transactionsRefreshProvider.notifier).state++;
