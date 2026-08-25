import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/finance/alerts.dart';
import '../../../core/finance/money_engine.dart';
import '../../../core/finance/snapshot_provider.dart';
import '../../../core/theme.dart';
import '../../accounts/domain/account.dart';
import '../../planning/data/goal_repository.dart';
import '../../planning/data/obligation_repository.dart';
import '../../planning/domain/goal.dart';
import '../../planning/domain/obligation.dart';
import '../../transactions/domain/transaction.dart';
import '../data/coach_repository.dart';
import '../data/coach_service.dart';
import '../data/coach_transport.dart';
import '../domain/coach_action.dart';
import '../domain/coach_message.dart';
import 'coach_action_card.dart';

/// Openers built from the user's actual position.
///
/// A fixed list ages badly: it offers "am I on track for an emergency fund?" to
/// someone with no goal, and never mentions the category that just doubled.
/// These are generated from the same snapshot and alerts the dashboard uses, so
/// they only ever ask about something real.
List<String> _suggestionsFor({
  required MoneySnapshot snapshot,
  required List<MoneyAlert> alerts,
  required List<Goal> goals,
  required List<Obligation> obligations,
  required List<Account> accounts,
}) {
  final out = <String>[];

  if (snapshot.willFallShort) {
    out.add('Why am I running short before payday, and what do I cut?');
  }

  // Lead with whatever actually moved, named and quantified.
  final spike = snapshot.categories
      .where((c) => (c.changeRatio ?? 0) >= kCategorySpikeRatio)
      .where((c) => c.delta >= kCategorySpikeFloor)
      .toList();
  if (spike.isNotEmpty) {
    out.add('Why is ${spike.first.category} up this month?');
  }

  if (snapshot.daysUntilIncome == null) {
    out.add('Help me record my salary and bills.');
  } else if (snapshot.safeToSpend > 0) {
    out.add('How much can I spend a day until my next income?');
  }

  if (accounts.length > 1 && snapshot.liquid > 0) {
    // A round figure the user could plausibly be sending.
    final amount = snapshot.safeToSpend > 1000
        ? 500
        : snapshot.safeToSpend > 200
            ? 100
            : 50;
    out.add('I need to send GHS $amount — which account should it come from?');
  }

  final uncovered =
      alerts.where((a) => a.id.startsWith('bill.uncovered.')).toList();
  if (uncovered.isNotEmpty) {
    out.add('Sort out the bill I cannot cover.');
  } else if (obligations.any((o) => o.isActive && o.isOutflow)) {
    out.add('What is leaving my accounts in the next two weeks?');
  }

  final goal = goals.where((g) => g.isActive && !g.isComplete).firstOrNull;
  if (goal != null) {
    out.add('Am I on track for ${goal.name}?');
  }

  if (snapshot.spend30d > 0) {
    out.add('Where is my money actually going?');
  }

  return out.take(5).toList();
}

/// A coach that remembers the conversation and can hand you a button.
class AskAiTab extends ConsumerStatefulWidget {
  // Kept for call-site compatibility; the coach now reads everything it needs
  // through coachContextProvider so it and the dashboard cannot disagree.
  final List<Account> accounts;
  final List<Txn> txns;

  const AskAiTab({super.key, required this.accounts, required this.txns});

  @override
  ConsumerState<AskAiTab> createState() => _AskAiTabState();
}

class _AskAiTabState extends ConsumerState<AskAiTab> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();

  String? _pendingQuestion;
  List<String> _activeTools = const [];
  String? _error;
  bool _loading = false;

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _ask([String? prefilled]) async {
    final question = (prefilled ?? _ctrl.text).trim();
    if (question.isEmpty || _loading) return;

    setState(() {
      _loading = true;
      _error = null;
      _pendingQuestion = question;
      _activeTools = const [];
      _ctrl.clear();
    });
    FocusScope.of(context).unfocus();
    _scrollToBottom();

    try {
      final transport = await ref.read(coachTransportProvider.future);
      final context_ = await ref.read(coachContextProvider.future);
      final threadId = await ref.read(coachThreadIdProvider.future);
      final history = await ref.read(coachMessagesProvider.future);

      final turn = await CoachService(transport: transport).send(
        question: question,
        history: history,
        context: context_,
      );

      if (mounted) setState(() => _activeTools = turn.toolsUsed);

      try {
        await ref.read(coachRepositoryProvider).saveTurn(threadId, turn.messages);
      } catch (e) {
        // Losing the transcript is not worth losing the answer over, but the
        // coach will not remember this exchange next time.
        debugPrint('Coach: could not save the turn: $e');
      }

      ref.invalidate(coachMessagesProvider);
      if (!mounted) return;
      setState(() => _pendingQuestion = null);
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _startFresh() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Start a new conversation?'),
        content: const Text(
            'The coach will forget what you have discussed so far.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Start fresh')),
        ],
      ),
    );
    if (ok != true) return;

    await ref.read(coachRepositoryProvider).startNewThread();
    if (!mounted) return;
    bumpCoachThread(ref);
  }

  @override
  Widget build(BuildContext context) {
    final messagesAsync = ref.watch(coachMessagesProvider);
    final snapshot = ref.watch(moneySnapshotProvider).value;
    final suggestions = snapshot == null
        ? const <String>[]
        : _suggestionsFor(
            snapshot: snapshot,
            alerts: ref.watch(moneyAlertsProvider).value ?? const [],
            goals: ref.watch(goalsProvider).value ?? const [],
            obligations: ref.watch(obligationsProvider).value ?? const [],
            accounts: widget.accounts,
          );

    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: messagesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => _ErrorCard(message: '$e', onRetry: () {
                ref.invalidate(coachMessagesProvider);
              }),
              data: (messages) {
                final visible = messages.where((m) => m.isVisible).toList();

                return ListView(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  children: [
                    _Header(
                      hasHistory: visible.isNotEmpty,
                      onNewChat: _startFresh,
                    ),
                    const SizedBox(height: 14),
                    if (visible.isEmpty && suggestions.isNotEmpty) ...[
                      const Text('Try asking',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 14)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final s in suggestions)
                            ActionChip(
                              avatar: const Icon(Icons.bolt, size: 16),
                              label: Text(s),
                              onPressed: _loading ? null : () => _ask(s),
                            ),
                        ],
                      ),
                    ],
                    for (final m in visible) ...[
                      _Bubble(message: m),
                      const SizedBox(height: 10),
                    ],
                    if (_pendingQuestion != null && _loading) ...[
                      _Bubble.pendingUser(_pendingQuestion!),
                      const SizedBox(height: 10),
                      _Thinking(tools: _activeTools),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      _ErrorCard(
                        message: _error!,
                        onRetry: () {
                          final q = _pendingQuestion;
                          if (q != null) _ask(q);
                        },
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
          _ComposeBar(
            controller: _ctrl,
            loading: _loading,
            onSend: () => _ask(),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final bool hasHistory;
  final VoidCallback onNewChat;

  const _Header({required this.hasHistory, required this.onNewChat});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [AppColors.netGradStart, AppColors.netGradEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.auto_awesome, color: Colors.white),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Your money manager',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800)),
                SizedBox(height: 4),
                Text(
                  'Reads your real position, remembers the conversation, and '
                  'hands you actions to approve.',
                  style: TextStyle(
                      color: Colors.white70, fontSize: 12, height: 1.35),
                ),
              ],
            ),
          ),
          if (hasHistory)
            IconButton(
              tooltip: 'Start a new conversation',
              icon: const Icon(Icons.edit_note, color: Colors.white),
              onPressed: onNewChat,
            ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final CoachMessage? message;
  final String? pendingUserText;

  const _Bubble({required this.message}) : pendingUserText = null;

  const _Bubble.pendingUser(String text)
      : pendingUserText = text,
        message = null;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isUser =
        pendingUserText != null || message?.role == CoachRole.user;
    final text = pendingUserText ?? message?.content ?? '';
    final actions = message?.actions ?? const <CoachAction>[];

    if (isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 320),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.seed,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
              bottomLeft: Radius.circular(16),
              bottomRight: Radius.circular(4),
            ),
          ),
          child: Text(
            text,
            style: const TextStyle(
                color: Colors.white, fontSize: 13.5, height: 1.4),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
              bottomLeft: Radius.circular(4),
              bottomRight: Radius.circular(16),
            ),
          ),
          child: MarkdownBody(
            data: text,
            styleSheet: MarkdownStyleSheet(
              p: const TextStyle(fontSize: 13.5, height: 1.5),
              listBullet: const TextStyle(fontSize: 13.5, height: 1.5),
            ),
          ),
        ),
        for (final a in actions) ...[
          const SizedBox(height: 8),
          CoachActionCard(action: a),
        ],
      ],
    );
  }
}

/// Shows what the coach is looking up, so waiting feels like work happening
/// rather than a spinner.
class _Thinking extends StatelessWidget {
  final List<String> tools;
  const _Thinking({required this.tools});

  static const _labels = {
    'get_position': 'Checking your position',
    'get_alerts': 'Looking for problems',
    'list_accounts': 'Reading your accounts',
    'list_commitments': 'Checking what you owe',
    'plan_payment': 'Working out where to pay from',
    'get_spending': 'Reviewing your spending',
    'list_transactions': 'Going through transactions',
    'propose_transfer': 'Preparing a transfer',
    'propose_commitment': 'Preparing a record',
  };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final label = tools.isEmpty
        ? 'Thinking'
        : _labels[tools.last] ?? 'Working on it';

    return Row(
      children: [
        const SizedBox(
          width: 15,
          height: 15,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 10),
        Text(
          '$label…',
          style: TextStyle(
            fontSize: 12.5,
            fontStyle: FontStyle.italic,
            color: cs.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorCard({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.expense.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.expense.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.error_outline, color: AppColors.expense),
                const SizedBox(width: 8),
                const Text('The coach could not answer',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const Spacer(),
                TextButton(onPressed: onRetry, child: const Text('Retry')),
              ],
            ),
            const SizedBox(height: 4),
            Text(message, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _ComposeBar extends StatelessWidget {
  final TextEditingController controller;
  final bool loading;
  final VoidCallback onSend;

  const _ComposeBar({
    required this.controller,
    required this.loading,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 10, 10),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: const InputDecoration(
                  hintText: 'Ask anything about your money…',
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Material(
              color: AppColors.seed,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: loading ? null : onSend,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.send, color: Colors.white, size: 20),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
