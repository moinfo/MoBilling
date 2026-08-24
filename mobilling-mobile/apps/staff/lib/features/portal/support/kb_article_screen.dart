import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../portal_providers.dart';

/// A knowledgebase article, rendered as readable plain text.
///
/// The one screen in the portal that is prose, so it is set like prose: the
/// title as the headline, a mono line naming when it was written and how many
/// people have read it, and the body at reading measure.
class KbArticleScreen extends ConsumerWidget {
  const KbArticleScreen({super.key, required this.slug});

  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final article = ref.watch(portalKbArticleProvider(slug));
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: ShellTopBar(
        eyebrow: 'Support',
        title: article.valueOrNull?.categoryName ?? 'Help',
      ),
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
            Reveal(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    a.title,
                    style: Type.display(26, color: scheme.onSurface),
                  ),
                  if (a.updatedAt != null || a.views != null) ...[
                    const SizedBox(height: Spacing.sm),
                    Text(
                      [
                        if (a.updatedAt != null)
                          'updated ${Formatting.date(a.updatedAt)}',
                        if (a.views != null)
                          '${Formatting.integer(a.views)} views',
                      ].join(' · ').toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Divider(height: Spacing.xl, color: scheme.outlineVariant),
            SelectableText(
              htmlToPlainText(a.body),
              style: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
            ),
            const SizedBox(height: Spacing.xxl),
          ],
        ),
      ),
    );
  }
}
