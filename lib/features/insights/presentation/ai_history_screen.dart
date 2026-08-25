import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/formatters.dart';
import '../../../core/theme.dart';
import '../data/chat_repository.dart';
import '../domain/chat_message.dart';

class AiHistoryScreen extends ConsumerWidget {
  const AiHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(chatHistoryProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ask AI history'),
        actions: [
          historyAsync.maybeWhen(
            data: (chats) => chats.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    icon: const Icon(Icons.delete_sweep_outlined),
                    tooltip: 'Clear all',
                    onPressed: () => _confirmClear(context, ref),
                  ),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: historyAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (chats) {
          if (chats.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.chat_bubble_outline,
                        size: 48,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                    const SizedBox(height: 12),
                    const Text('No past conversations',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 16)),
                    const SizedBox(height: 6),
                    Text('Questions you ask the coach will appear here.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 12.5,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant)),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
            itemCount: chats.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (_, i) => _HistoryCard(
              message: chats[i],
              onDelete: () async {
                await ref.read(chatRepositoryProvider).delete(chats[i].id);
                bumpChats(ref);
              },
            ),
          );
        },
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear chat history?'),
        content: const Text(
            'All saved AI conversations will be permanently removed.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.expense),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        await ref.read(chatRepositoryProvider).clearAll();
        bumpChats(ref);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('$e')));
        }
      }
    }
  }
}

class _HistoryCard extends StatelessWidget {
  final ChatMessage message;
  final VoidCallback onDelete;
  const _HistoryCard({required this.message, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.schedule, size: 14, color: cs.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(_relTime(message.createdAt),
                    style: TextStyle(
                        fontSize: 11.5,
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w600)),
                const Spacer(),
                IconButton(
                  iconSize: 18,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.copy_outlined),
                  tooltip: 'Copy answer',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: message.answer));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Copied'),
                          behavior: SnackBarBehavior.floating,
                          duration: Duration(seconds: 1)),
                    );
                  },
                ),
                IconButton(
                  iconSize: 18,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Delete',
                  onPressed: onDelete,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('Question',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: cs.primary,
                    letterSpacing: 0.4)),
            const SizedBox(height: 4),
            Text(message.question,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 14, height: 1.35)),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Text('Answer',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.netGradStart,
                    letterSpacing: 0.4)),
            const SizedBox(height: 4),
            MarkdownBody(
              data: message.answer,
              selectable: true,
              styleSheet: _markdownStyle(context),
            ),
          ],
        ),
      ),
    );
  }
}

MarkdownStyleSheet _markdownStyle(BuildContext context) {
  final base = Theme.of(context).textTheme.bodyMedium?.copyWith(
        fontSize: 13.5,
        height: 1.5,
      );
  final cs = Theme.of(context).colorScheme;
  return MarkdownStyleSheet(
    p: base,
    listBullet: base,
    h1: base?.copyWith(fontSize: 17, fontWeight: FontWeight.w800),
    h2: base?.copyWith(fontSize: 15.5, fontWeight: FontWeight.w800),
    h3: base?.copyWith(fontSize: 14.5, fontWeight: FontWeight.w700),
    strong: base?.copyWith(fontWeight: FontWeight.w800),
    em: base?.copyWith(fontStyle: FontStyle.italic),
    code: TextStyle(
      fontFamily: 'monospace',
      fontSize: 12.5,
      backgroundColor: cs.surfaceContainerHighest,
    ),
    blockquoteDecoration: BoxDecoration(
      color: cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
    ),
    blockquotePadding: const EdgeInsets.all(10),
    listIndent: 20,
  );
}

String _relTime(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  if (d.inDays < 7) return '${d.inDays}d ago';
  return dateLongFmt.format(t);
}
