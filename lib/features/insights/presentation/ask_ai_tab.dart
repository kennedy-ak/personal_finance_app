import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/components.dart';
import '../../../core/design/sheets.dart';
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

  return out.take(4).toList();
}

/// A coach that remembers the conversation and can hand you a button.
class AskAiTab extends ConsumerStatefulWidget {
  // Kept for call-site compatibility; the coach now reads everything it needs
  // through coachContextProvider so it and the dashboard cannot disagree.
  final List<Account> accounts;
  final List<Txn> txns;

  /// The way back, since the segmented control is hidden while chatting.
  final VoidCallback? onBackToOverview;

  const AskAiTab({
    super.key,
    required this.accounts,
    required this.txns,
    this.onBackToOverview,
  });

  @override
  ConsumerState<AskAiTab> createState() => _AskAiTabState();
}

class _AskAiTabState extends ConsumerState<AskAiTab> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();

  String? _pendingQuestion;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    // The send button lights up the moment there is something to send.
    _ctrl.addListener(() => setState(() {}));
  }

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
      _ctrl.clear();
    });
    FocusScope.of(context).unfocus();
    _scrollToBottom();

    try {
      // The server runs the tools, answers and saves the turn; invalidating
      // the cache is what renders the finished messages.
      final threadId = await ref.read(coachThreadIdProvider.future);
      await CoachService(ask: ref.read(serverCoachTransportProvider).ask).send(
        question: question,
        threadId: threadId,
      );

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
    final ok = await showDeleteConfirmation(
      context: context,
      title: 'Start a new conversation?',
      message: 'The coach will forget what you have discussed so far. The old '
          'conversation stays in your history.',
      confirmLabel: 'Start fresh',
      cancelLabel: 'Keep going',
    );
    if (ok != true) return;

    await ref.read(coachRepositoryProvider).startNewThread();
    if (!mounted) return;
    bumpCoachThread(ref);
  }

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
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

    return messagesAsync.when(
      loading: () => Center(child: CircularProgressIndicator(color: t.brandInk)),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: ErrorCard(
          title: 'Could not load your conversation',
          message: 'Check your connection and try again.',
          onRetry: () => ref.invalidate(coachMessagesProvider),
        ),
      ),
      data: (messages) {
        final visible = messages.where((m) => m.isVisible).toList();
        final empty = visible.isEmpty && _pendingQuestion == null;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _TopBar(
              empty: empty,
              onBack: widget.onBackToOverview,
              onNewChat: _startFresh,
              onHistory: () => context.push('/ai-history'),
            ),
            Expanded(
              child: empty
                  ? _EmptyChat(
                      suggestions: suggestions,
                      accountCount: widget.accounts.length,
                      obligationCount: (ref
                                  .watch(obligationsProvider)
                                  .value
                                  ?.where((o) => o.isActive)
                                  .length ??
                              0),
                      onAsk: _loading ? null : _ask,
                    )
                  : ListView(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                      children: [
                        for (final m in visible) ...[
                          _Bubble(message: m),
                          const SizedBox(height: 12),
                        ],
                        if (_pendingQuestion != null) ...[
                          _Bubble.pendingUser(_pendingQuestion!),
                          const SizedBox(height: 12),
                        ],
                        if (_loading) const _Thinking(),
                        if (_error != null)
                          _CoachError(
                            onRetry: () {
                              final q = _pendingQuestion;
                              setState(() => _error = null);
                              if (q != null) _ask(q);
                            },
                          ),
                      ],
                    ),
            ),
            _ComposeBar(
              controller: _ctrl,
              loading: _loading,
              onSend: () => _ask(),
            ),
          ],
        );
      },
    );
  }
}

/// The coach's identity plate — violet, so the coach is the same colour
/// wherever it speaks.
class _CoachAvatar extends StatelessWidget {
  final double size;
  const _CoachAvatar({this.size = 32});

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: t.accent.surface,
        borderRadius: BorderRadius.circular(size * 0.34),
        border: Border.all(color: t.accent.border),
      ),
      child: Icon(Icons.auto_awesome, size: size * 0.5, color: t.accent.ink),
    );
  }
}

class _TopBar extends StatelessWidget {
  final bool empty;
  final VoidCallback? onBack;
  final VoidCallback onNewChat;
  final VoidCallback onHistory;

  const _TopBar({
    required this.empty,
    required this.onBack,
    required this.onNewChat,
    required this.onHistory,
  });

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.hairline)),
      ),
      child: Row(
        children: [
          if (onBack != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: IconButton(
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: onBack,
                icon: Icon(Icons.arrow_back, size: 20, color: t.inkMuted),
              ),
            ),
          const _CoachAvatar(size: 28),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Your coach',
                style: AppType.cardTitle.copyWith(fontSize: 15, color: t.ink)),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: empty ? onHistory : onNewChat,
            child: Text(
              empty ? 'History' : 'New chat',
              style: AppType.label.copyWith(
                fontSize: 12,
                color: empty ? t.brandInk : t.inkMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// What the coach can see, and four questions worth asking about it.
class _EmptyChat extends StatelessWidget {
  final List<String> suggestions;
  final int accountCount;
  final int obligationCount;
  final ValueChanged<String>? onAsk;

  const _EmptyChat({
    required this.suggestions,
    required this.accountCount,
    required this.obligationCount,
    required this.onAsk,
  });

  /// Says exactly what the coach reads, in the user's own numbers. A vague
  /// promise about "your data" is what makes people distrust it.
  String get _explainer {
    final parts = <String>[
      if (accountCount > 0)
        'your $accountCount account${accountCount == 1 ? '' : 's'}',
      if (obligationCount > 0)
        '$obligationCount commitment${obligationCount == 1 ? '' : 's'}',
      "this month's transactions",
    ];
    return 'It reads the same numbers the dashboard does — ${parts.join(', ')}. '
        'It can propose a transfer or a new bill, but nothing moves until you '
        'approve it.';
  }

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      children: [
        CediCard(
          radius: 18,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const _CoachAvatar(),
                  const SizedBox(width: 10),
                  Text('Your coach',
                      style:
                          AppType.cardTitle.copyWith(fontSize: 15, color: t.ink)),
                ],
              ),
              const SizedBox(height: 11),
              Text(_explainer,
                  style: AppType.body.copyWith(height: 1.5, color: t.inkMuted)),
            ],
          ),
        ),
        if (suggestions.isNotEmpty) ...[
          const SizedBox(height: 18),
          Eyebrow('From your position right now',
              size: 11, color: t.inkFaint),
          const SizedBox(height: 11),
          for (final s in suggestions) ...[
            _SuggestionRow(text: s, onTap: onAsk == null ? null : () => onAsk!(s)),
            const SizedBox(height: 8),
          ],
        ],
      ],
    );
  }
}

class _SuggestionRow extends StatelessWidget {
  final String text;
  final VoidCallback? onTap;

  const _SuggestionRow({required this.text, this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    final radius = BorderRadius.circular(13);

    return Material(
      color: t.accent.surface,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: t.accent.border),
          ),
          child: Text(text,
              style: AppType.label.copyWith(
                  fontSize: 14, height: 1.35, color: t.accent.ink)),
        ),
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
    final t = CediTokens.of(context);
    final isUser = pendingUserText != null || message?.role == CoachRole.user;
    final text = pendingUserText ?? message?.content ?? '';
    final actions = message?.actions ?? const <CoachAction>[];

    if (isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
            decoration: BoxDecoration(
              color: t.brand,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(6),
              ),
            ),
            child: Text(text,
                style: AppType.body.copyWith(color: t.onBrand)),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (text.trim().isNotEmpty)
          ConstrainedBox(
            constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * 0.86),
            child: Container(
              padding: const EdgeInsets.fromLTRB(13, 12, 13, 4),
              decoration: BoxDecoration(
                color: t.card,
                border: Border.all(color: t.hairline),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                  bottomLeft: Radius.circular(6),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: MarkdownBody(
                data: text,
                styleSheet: MarkdownStyleSheet(
                  p: AppType.body.copyWith(height: 1.55, color: t.inkBody),
                  listBullet:
                      AppType.body.copyWith(height: 1.55, color: t.inkBody),
                  strong: AppType.body.copyWith(
                      height: 1.55,
                      fontWeight: FontWeight.w700,
                      color: t.ink),
                  code: AppType.monoCaption
                      .copyWith(fontSize: 13, color: t.ink),
                ),
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

/// Shows waiting as work happening rather than as a stalled spinner. The
/// server runs the whole loop now, so per-tool labels never reach the app.
class _Thinking extends StatelessWidget {
  const _Thinking();

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    const label = 'Thinking';

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        decoration: BoxDecoration(
          color: t.card,
          border: Border.all(color: t.hairline),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(6),
            bottomRight: Radius.circular(16),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 13,
              height: 13,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: t.accent.ink,
                backgroundColor: t.accent.ink.withValues(alpha: 0.3),
              ),
            ),
            const SizedBox(width: 10),
            Text('$label…',
                style: AppType.body.copyWith(height: 1.0, color: t.inkMuted)),
          ],
        ),
      ),
    );
  }
}

/// The coach could not be reached.
///
/// The reassurance is the content: nothing was sent, nothing was charged,
/// nothing about the user's money changed. A raw exception string says none of
/// that, so it does not appear.
class _CoachError extends StatelessWidget {
  final VoidCallback onRetry;

  const _CoachError({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);

    return TintCard(
      tint: t.expense,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Eyebrow('Could not reach the coach', color: t.expense.muted),
          const SizedBox(height: 8),
          Text(
            'Your question was not sent, so nothing was charged. Your numbers '
            'are unchanged.',
            style: AppType.body.copyWith(height: 1.5, color: t.expense.body),
          ),
          const SizedBox(height: 13),
          Row(
            children: [
              Material(
                color: Colors.transparent,
                borderRadius: Radii.sm,
                child: InkWell(
                  borderRadius: Radii.sm,
                  onTap: onRetry,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 11),
                    decoration: BoxDecoration(
                      borderRadius: Radii.sm,
                      border: Border.all(
                          color: t.expense.ink.withValues(alpha: 0.5)),
                    ),
                    child: Text('Retry',
                        style: AppType.button
                            .copyWith(fontSize: 14, color: t.expense.ink)),
                  ),
                ),
              ),
            ],
          ),
        ],
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
    final t = CediTokens.of(context);
    final canSend = controller.text.trim().isNotEmpty && !loading;

    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: t.hairline)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 4,
                enabled: !loading,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                style: AppType.body
                    .copyWith(fontSize: 14, height: 1.3, color: t.ink),
                cursorColor: t.brandInk,
                decoration: InputDecoration(
                  hintText: 'Ask about your money',
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: t.fieldBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: t.fieldBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: t.brandInk, width: 1.4),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 9),
            // Dead until there is something to send, so the button never
            // promises an action it will not perform.
            Material(
              color: canSend ? t.brand : t.disabledFill,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: canSend ? onSend : null,
                child: SizedBox(
                  width: 46,
                  height: 46,
                  child: loading
                      ? Center(
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: t.inkMuted),
                          ),
                        )
                      : Icon(Icons.arrow_upward,
                          size: 20,
                          color: canSend ? t.onBrand : t.disabledInk),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
