import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme.dart';
import '../../accounts/domain/account.dart';
import '../../transactions/domain/transaction.dart';
import '../data/api_key_store.dart';
import '../data/chat_repository.dart';
import '../data/openai_service.dart';

const _suggestions = <String>[
  'What are my biggest spending leaks this month?',
  'Build me a 30-day plan to save more.',
  'Am I on track for a 3-month emergency fund?',
  'Suggest realistic budgets per category.',
  'Where can I cut back without changing my lifestyle much?',
];

class AskAiTab extends ConsumerStatefulWidget {
  final List<Account> accounts;
  final List<Txn> txns;
  const AskAiTab({super.key, required this.accounts, required this.txns});

  @override
  ConsumerState<AskAiTab> createState() => _AskAiTabState();
}

class _AskAiTabState extends ConsumerState<AskAiTab> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  String? _streamingQuestion;
  String? _error;
  bool _loading = false;

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _ask([String? prefilled]) async {
    final q = (prefilled ?? _ctrl.text).trim();
    if (q.isEmpty) return;
    final key = await ref.read(apiKeyStoreProvider).getKey();
    if (key == null || key.isEmpty) {
      _showKeyDialog();
      return;
    }
    final model = await ref.read(apiKeyStoreProvider).getModel();
    setState(() {
      _loading = true;
      _error = null;
      _streamingQuestion = q;
      _ctrl.clear();
    });
    FocusScope.of(context).unfocus();
    _scrollToBottom();
    try {
      final svc = OpenAIService(apiKey: key, model: model);
      final answer = await svc.ask(
        question: q,
        accounts: widget.accounts,
        txns: widget.txns,
      );
      try {
        await ref.read(chatRepositoryProvider).create(question: q, answer: answer);
        bumpChats(ref);
      } catch (e) {
        // Save error is non-fatal — still show the answer.
        debugPrint('Chat save failed: $e');
      }
      if (!mounted) return;
      setState(() {
        _streamingQuestion = null;
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _showKeyDialog() async {
    final existing = await ref.read(apiKeyStoreProvider).getKey() ?? '';
    final model = await ref.read(apiKeyStoreProvider).getModel();
    if (!mounted) return;
    final keyCtrl = TextEditingController(text: existing);
    final modelCtrl = TextEditingController(text: model);
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('OpenAI settings'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: keyCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'API key', hintText: 'sk-…', prefixIcon: Icon(Icons.key)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: modelCtrl,
              decoration: const InputDecoration(
                labelText: 'Model', prefixIcon: Icon(Icons.psychology)),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (saved == true) {
      final store = ref.read(apiKeyStoreProvider);
      await store.setKey(keyCtrl.text.trim());
      await store.setModel(modelCtrl.text.trim().isEmpty ? 'gpt-4o-mini' : modelCtrl.text.trim());
      if (mounted) bumpApiKey(ref);
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyAsync = ref.watch(apiKeyProvider);
    final hasKey = keyAsync.value?.isNotEmpty == true;
    final historyAsync = ref.watch(chatHistoryProvider);

    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              children: [
                _Header(onSettings: _showKeyDialog),
                const SizedBox(height: 14),
                if (!hasKey) _NoKeyCard(onSet: _showKeyDialog),
                const SizedBox(height: 8),
                const Text('Try asking',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final s in _suggestions)
                      ActionChip(
                        avatar: const Icon(Icons.lightbulb_outline, size: 16),
                        label: Text(s),
                        onPressed: _loading ? null : () => _ask(s),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                if (_streamingQuestion != null && _loading)
                  _PendingCard(question: _streamingQuestion!),
                if (_error != null)
                  _ErrorCard(message: _error!, onRetry: () {
                    if (_streamingQuestion != null) _ask(_streamingQuestion);
                  }),
                const SizedBox(height: 12),
                historyAsync.when(
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                  data: (chats) => chats.isEmpty
                      ? const SizedBox.shrink()
                      : OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(46),
                          ),
                          onPressed: () => context.push('/ai-history'),
                          icon: const Icon(Icons.history, size: 18),
                          label: Text(
                            'View past conversations (${chats.length})',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                ),
              ],
            ),
          ),
          _ComposeBar(
            controller: _ctrl,
            loading: _loading,
            onSend: () => _ask(),
            onSettings: _showKeyDialog,
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final VoidCallback onSettings;
  const _Header({required this.onSettings});

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
        boxShadow: [
          BoxShadow(
            color: AppColors.netGradEnd.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
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
                Text('Ask your money coach',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800)),
                SizedBox(height: 4),
                Text('Powered by OpenAI. Conversations are saved to your account.',
                    style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NoKeyCard extends StatelessWidget {
  final VoidCallback onSet;
  const _NoKeyCard({required this.onSet});
  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.warning.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.warning.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const Icon(Icons.key, color: AppColors.warning),
            const SizedBox(width: 10),
            const Expanded(
              child: Text('Add your OpenAI API key to start chatting.', style: TextStyle(fontSize: 13)),
            ),
            TextButton(onPressed: onSet, child: const Text('Set key')),
          ],
        ),
      ),
    );
  }
}

class _PendingCard extends StatelessWidget {
  final String question;
  const _PendingCard({required this.question});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(Icons.person, size: 14, color: cs.primary),
                  const SizedBox(width: 6),
                  Text('You',
                      style: TextStyle(
                          fontSize: 11, color: cs.primary, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(question, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 12),
            const Row(
              children: [
                SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 10),
                Text('Coach is thinking…',
                    style: TextStyle(fontSize: 12.5, fontStyle: FontStyle.italic)),
              ],
            ),
          ],
        ),
      ),
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
                const Text('Something went wrong',
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
  final VoidCallback onSettings;
  const _ComposeBar({
    required this.controller,
    required this.loading,
    required this.onSend,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: 'OpenAI settings',
              onPressed: onSettings,
            ),
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
                  contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 6),
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
                          width: 20, height: 20,
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

