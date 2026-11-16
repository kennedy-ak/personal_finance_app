import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../core/api_client.dart';
import '../../../core/constants.dart';
import '../../../core/formatters.dart';
import '../domain/transaction.dart';

class TransactionRepository {
  Future<List<Txn>> list({DateTime? from, DateTime? to}) async {
    final rows = await api.get('/transactions', query: {
      if (from != null) 'from': dateFmt.format(from),
      if (to != null) 'to': dateFmt.format(to),
    });
    return (rows as List)
        .map((r) => Txn.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<Txn> create({
    required String accountId,
    required TxnType type,
    required double amount,
    required String category,
    String? description,
    required DateTime date,
  }) async {
    final row = await api.post('/transactions', body: {
      'account_id': accountId,
      'type': type.label,
      'amount': amount,
      'category': category,
      'description': description,
      'date': dateFmt.format(date),
    });
    return Txn.fromJson(row as Map<String, dynamic>);
  }

  /// Records a movement between two of the user's own accounts as a single row.
  ///
  /// One row, not the old Expense + Income pair — so the movement never lands in
  /// income, expenses, or the spending breakdown. Account balances on both sides
  /// are settled by the backend.
  Future<Txn> createTransfer({
    required String fromAccountId,
    required String toAccountId,
    required double amount,
    String? description,
    required DateTime date,
  }) async {
    if (fromAccountId == toAccountId) {
      throw ArgumentError('A transfer needs two different accounts.');
    }
    final row = await api.post('/transactions', body: {
      'account_id': fromAccountId,
      'to_account_id': toAccountId,
      'type': TxnType.transfer.label,
      'amount': amount,
      'category': kTransferCategory,
      'description': description,
      'date': dateFmt.format(date),
    });
    return Txn.fromJson(row as Map<String, dynamic>);
  }

  Future<void> delete(String id) async {
    await api.delete('/transactions/$id');
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
