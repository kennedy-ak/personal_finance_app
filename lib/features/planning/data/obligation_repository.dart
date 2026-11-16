import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../core/api_client.dart';
import '../../../core/formatters.dart';
import '../domain/obligation.dart';

class ObligationRepository {
  Future<List<Obligation>> list() async {
    final rows = await api.get('/obligations');
    return (rows as List)
        .map((r) => Obligation.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<Obligation> create({
    required String name,
    required double amount,
    required DateTime nextDue,
    ObligationDirection direction = ObligationDirection.out,
    Cadence cadence = Cadence.monthly,
    String? accountId,
    String? category,
  }) async {
    final row = await api.post('/obligations', body: {
      'name': name,
      'direction': direction.value,
      'amount': amount,
      'cadence': cadence.value,
      'next_due': dateFmt.format(nextDue),
      'account_id': accountId,
      'category': category,
    });
    return Obligation.fromJson(row as Map<String, dynamic>);
  }

  Future<void> update(
    String id, {
    String? name,
    double? amount,
    DateTime? nextDue,
    ObligationDirection? direction,
    Cadence? cadence,
    String? accountId,
    String? category,
    bool? isActive,
  }) async {
    final patch = <String, dynamic>{
      'name': ?name,
      'amount': ?amount,
      if (nextDue != null) 'next_due': dateFmt.format(nextDue),
      if (direction != null) 'direction': direction.value,
      if (cadence != null) 'cadence': cadence.value,
      if (accountId != null) 'account_id': accountId.isEmpty ? null : accountId,
      if (category != null) 'category': category.isEmpty ? null : category,
      'is_active': ?isActive,
    };
    if (patch.isEmpty) return;
    await api.patch('/obligations/$id', body: patch);
  }

  Future<void> delete(String id) async {
    await api.delete('/obligations/$id');
  }
}

final obligationRepositoryProvider = Provider((_) => ObligationRepository());

final obligationsRefreshProvider = StateProvider<int>((_) => 0);

final obligationsProvider = FutureProvider<List<Obligation>>((ref) async {
  ref.watch(obligationsRefreshProvider);
  return ref.watch(obligationRepositoryProvider).list();
});

void bumpObligations(WidgetRef ref) =>
    ref.read(obligationsRefreshProvider.notifier).state++;
