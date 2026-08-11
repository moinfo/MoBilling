import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../portal_providers.dart';

/// A knowledgebase article, rendered as readable plain text.
class KbArticleScreen extends ConsumerWidget {
  const KbArticleScreen({super.key, required this.slug});

  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final article = ref.watch(portalKbArticleProvider(slug));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(article.valueOrNull?.categoryName ?? 'Help')),
      body: article.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => StateMessage(
          icon: Icons.cloud_off_outlined,
          title: 'Could not load this article',
          message: error is ApiException ? error.message : null,
          actionLabel: 'Retry',
          onAction: () => ref.invalidate(portalKbArticleProvider(slug)),
        ),
        data: (a) => ListView(
          padding: const EdgeInsets.all(Spacing.md),
          children: [
            Text(a.title, style: theme.textTheme.headlineSmall),
            const SizedBox(height: Spacing.xs),
            Text(
              [
                if (a.updatedAt != null)
                  'Updated ${Formatting.date(a.updatedAt)}',
                if (a.views != null) '${a.views} views',
              ].join(' · '),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const Divider(height: Spacing.xl),
            SelectableText(
              htmlToPlainText(a.body),
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
            ),
            const SizedBox(height: Spacing.xl),
          ],
        ),
      ),
    );
  }
}
