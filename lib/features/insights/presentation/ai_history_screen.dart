import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/components.dart';
import '../../../core/design/sheets.dart';
import '../../../core/formatters.dart';
import '../../../core/theme.dart';
import '../data/chat_repository.dart';
import '../domain/chat_message.dart';

/// Past conversations, newest first.
///
/// The list shows the question and when it was asked; the answer opens in a
/// sheet. A wall of expanded markdown makes the list unusable for the one job
/// it has, which is finding the conversation you remember having.
class AiHistoryScreen extends ConsumerWidget {
  const AiHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = CediTokens.of(context);
    final historyAsync = ref.watch(chatHistoryProvider);

    return Scaffold(
      backgroundColor: t.canvas,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
          children: [
            Row(
              children: [
                IconButton(
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  alignment: Alignment.centerLeft,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  onPressed: () =>
                      context.canPop() ? context.pop() : context.go('/insights'),
                  icon: Icon(Icons.arrow_back, size: 22, color: t.inkMuted),
                ),
                const Spacer(),
                historyAsync.maybeWhen(
                  data: (chats) => chats.isEmpty
                      ? const SizedBox.shrink()
                      : GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _confirmClear(context, ref),
                          child: Text('Clear all',
                              style: AppType.label
                                  .copyWith(fontSize: 13, color: t.inkMuted)),
                        ),
                  orElse: () => const SizedBox.shrink(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Past conversations',
                style: AppType.title.copyWith(color: t.ink)),
            const SizedBox(height: 16),
            historyAsync.when(
              loading: () => Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Center(
                    child: CircularProgressIndicator(color: t.brandInk)),
              ),
              error: (e, _) => ErrorCard(
                title: 'Could not load your conversations',
                message: 'Check your connection and try again.',
                onRetry: () => bumpChats(ref),
              ),
              data: (chats) {
                if (chats.isEmpty) {
                  return const EmptyCard(
                    title: 'No past conversations',
                    message: 'Questions you ask the coach are kept here so you '
                        'can go back to what it told you.',
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    RowGroup(
                      children: [
                        for (final chat in chats)
                          _HistoryRow(
                            message: chat,
                            onTap: () => _openConversation(context, ref, chat),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Conversations stay here until you clear them. Clearing '
                      'is permanent.',
                      style: AppType.bodySmall
                          .copyWith(fontSize: 12, height: 1.5, color: t.inkFaint),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openConversation(
      BuildContext context, WidgetRef ref, ChatMessage chat) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ConversationSheet(
        message: chat,
        onDelete: () async {
          final ok = await showDeleteConfirmation(
            context: ctx,
            title: 'Delete this conversation?',
            message: 'The question and the coach\'s answer are removed. Your '
                'accounts and transactions are untouched.',
          );
          if (ok != true) return;
          await ref.read(chatRepositoryProvider).delete(chat.id);
          bumpChats(ref);
          if (ctx.mounted) Navigator.pop(ctx);
        },
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    final ok = await showDeleteConfirmation(
      context: context,
      title: 'Clear every conversation?',
      message: 'All saved conversations are removed permanently. Your accounts '
          'and transactions are untouched.',
      confirmLabel: 'Clear all',
    );
    if (ok != true) return;
    try {
      await ref.read(chatRepositoryProvider).clearAll();
      bumpChats(ref);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not clear your history.')),
        );
      }
    }
  }
}

class _HistoryRow extends StatelessWidget {
  final ChatMessage message;
  final VoidCallback onTap;

  const _HistoryRow({required this.message, required this.onTap});

  /// TODAY, YESTERDAY, then the date. The relative form is only useful for
  /// the last day or two; after that people think in dates.
  static String _stamp(DateTime t) {
    final now = DateTime.now();
    final days = DateTime(now.year, now.month, now.day)
        .difference(DateTime(t.year, t.month, t.day))
        .inDays;
    if (days == 0) return 'Today';
    if (days == 1) return 'Yesterday';
    return dayMonthFmt.format(t);
  }

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    final words = message.answer.trim().split(RegExp(r'\s+')).length;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(message.question,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.rowTitle
                          .copyWith(height: 1.35, color: t.ink)),
                ),
                const SizedBox(width: 10),
                Text(_stamp(message.createdAt).toUpperCase(),
                    softWrap: false,
                    style: AppType.monoCaption.copyWith(color: t.inkFaint)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '$words word${words == 1 ? '' : 's'} · '
              '${timeFmt.format(message.createdAt)}',
              style: AppType.rowSub.copyWith(height: 1.45, color: t.inkMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConversationSheet extends StatelessWidget {
  final ChatMessage message;
  final Future<void> Function() onDelete;

  const _ConversationSheet({required this.message, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);

    return SheetSurface(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Eyebrow(dateLongFmt.format(message.createdAt), color: t.inkFaint),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                    maxWidth: MediaQuery.sizeOf(context).width * 0.8),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                  decoration: BoxDecoration(
                    color: t.brand,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                      bottomLeft: Radius.circular(16),
                      bottomRight: Radius.circular(6),
                    ),
                  ),
                  child: Text(message.question,
                      style: AppType.body.copyWith(color: t.onBrand)),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Container(
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
                data: message.answer,
                selectable: true,
                styleSheet: MarkdownStyleSheet(
                  p: AppType.body.copyWith(height: 1.55, color: t.inkBody),
                  listBullet:
                      AppType.body.copyWith(height: 1.55, color: t.inkBody),
                  strong: AppType.body.copyWith(
                      height: 1.55, fontWeight: FontWeight.w700, color: t.ink),
                  h1: AppType.cardTitle.copyWith(fontSize: 17, color: t.ink),
                  h2: AppType.cardTitle.copyWith(fontSize: 15, color: t.ink),
                  h3: AppType.cardTitle.copyWith(fontSize: 14, color: t.ink),
                  code:
                      AppType.monoCaption.copyWith(fontSize: 13, color: t.ink),
                  listIndent: 20,
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: SecondaryButton(
                    label: 'Copy answer',
                    filled: Theme.of(context).brightness == Brightness.light,
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: message.answer));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Copied'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DangerButton(label: 'Delete', onPressed: onDelete),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
