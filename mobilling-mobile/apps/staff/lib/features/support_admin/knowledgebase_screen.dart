import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../crm/crm_ui.dart' show CrmAsyncView, CrmDetailRow;
import 'support_admin_providers.dart';

/// Knowledgebase management: the articles clients read, and the categories
/// they are filed under.
///
/// Two tabs rather than two screens — a category only matters in terms of the
/// articles inside it, so moving between them should cost one tap.
class KnowledgebaseScreen extends ConsumerStatefulWidget {
  const KnowledgebaseScreen({super.key});

  @override
  ConsumerState<KnowledgebaseScreen> createState() =>
      _KnowledgebaseScreenState();
}

class _KnowledgebaseScreenState extends ConsumerState<KnowledgebaseScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  /// The masthead's add button creates whatever the visible tab lists, so it
  /// has to know which tab that is. Tracked rather than read straight off the
  /// controller because the controller also notifies on every frame of a
  /// swipe, and only the settled index changes what the button does.
  int _tabIndex = 0;

  bool get _onArticles => _tabIndex == 0;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this)
      ..addListener(() {
        if (_tabs.index != _tabIndex) setState(() => _tabIndex = _tabs.index);
      });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: ShellTopBar(
        eyebrow: 'Support',
        title: 'Knowledgebase',
        trailing: InkActionButton(
          icon: Icons.add_rounded,
          tooltip: _onArticles ? 'New article' : 'New category',
          onPressed: () => _onArticles
              ? _editArticle(context, null)
              : _editCategory(context, null),
        ),
        bottom: InkTabBar(
          controller: _tabs,
          tabs: const ['Articles', 'Categories'],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [_ArticlesTab(), _CategoriesTab()],
      ),
    );
  }

  Future<void> _editArticle(
    BuildContext context,
    StaffKbArticle? existing,
  ) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
      builder: (_) => _ArticleForm(existing: existing),
    );
    if (saved ?? false) {
      ref.invalidate(kbArticlesProvider(null));
      ref.invalidate(kbCategoriesProvider);
    }
  }

  Future<void> _editCategory(
    BuildContext context,
    StaffKbCategory? existing,
  ) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
      builder: (_) => _CategoryForm(existing: existing),
    );
    if (saved ?? false) ref.invalidate(kbCategoriesProvider);
  }
}

// ---------------------------------------------------------------------------
// Articles
// ---------------------------------------------------------------------------

class _ArticlesTab extends ConsumerWidget {
  const _ArticlesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final articles = ref.watch(kbArticlesProvider(null));
    final status = context.statusColors;

    return CrmAsyncView(
      value: articles,
      errorTitle: 'Could not load articles',
      onRetry: () => ref.invalidate(kbArticlesProvider(null)),
      builder: (items) {
        if (items.isEmpty) {
          return const StateMessage(
            icon: Icons.menu_book_outlined,
            title: 'No articles yet',
            message: 'Published articles appear in the client portal.',
          );
        }

        final drafts = [
          for (final a in items)
            if (!a.isPublished) a,
        ];
        final views = items.fold<int>(0, (sum, a) => sum + a.views);

        return RefreshIndicator(
          onRefresh: () => ref.refresh(kbArticlesProvider(null).future),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              Spacing.md,
              Spacing.md,
              Spacing.md,
              Spacing.xl,
            ),
            children: [
              StatRail(
                items: [
                  StatRailItem(
                    label: 'Articles',
                    value: Formatting.integer(items.length),
                  ),
                  StatRailItem(
                    label: 'Drafts',
                    value: Formatting.integer(drafts.length),
                    emphasis: drafts.isEmpty ? null : status.attention,
                  ),
                  StatRailItem(
                    label: 'Views',
                    value: Formatting.integer(views),
                  ),
                ],
              ),
              const SizedBox(height: Spacing.lg),
              const SectionHeader('All articles'),
              const SizedBox(height: Spacing.sm),
              // One card, rows divided by hairlines.
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (final (i, article) in items.indexed) ...[
                      if (i > 0) const Divider(height: 1),
                      _ArticleRow(article: article),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// One article: the state chip beside the category it is filed under, with
/// the read count as the aligned trailing figure — the only number an
/// article has, and the one that says whether it is earning its place.
class _ArticleRow extends ConsumerWidget {
  const _ArticleRow({required this.article});

  final StaffKbArticle article;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final meta = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return ListTile(
      onTap: () => _openArticleActions(context, ref, article),
      title: Text(
        article.title,
        style: theme.textTheme.titleSmall,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(
          children: [
            StatusChip(article.status, dense: true),
            const SizedBox(width: Spacing.sm),
            Flexible(
              child: Text(
                article.categoryName ?? 'uncategorised',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: meta,
              ),
            ),
          ],
        ),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            Formatting.integer(article.views),
            style: theme.textTheme.labelMedium,
          ),
          const SizedBox(height: 2),
          Text('VIEWS', style: meta),
        ],
      ),
    );
  }
}

Future<void> _openArticleActions(
  BuildContext context,
  WidgetRef ref,
  StaffKbArticle article,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
    builder: (context) {
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;

      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.lg,
                0,
                Spacing.lg,
                Spacing.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ARTICLE',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: Spacing.xs),
                  Text(
                    article.title,
                    style: Type.display(22, color: scheme.onSurface),
                  ),
                  const SizedBox(height: Spacing.sm),
                  StatusChip(article.status, dense: true),
                  const SizedBox(height: Spacing.md),
                  CrmDetailRow(
                    'Category',
                    article.categoryName ?? 'Uncategorised',
                  ),
                  CrmDetailRow('Views', Formatting.integer(article.views)),
                  if (article.slug != null) CrmDetailRow('Slug', article.slug!),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit article'),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: scheme.error),
              title: Text(
                'Delete article',
                style: TextStyle(color: scheme.error),
              ),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      );
    },
  );
  if (action == null || !context.mounted) return;

  try {
    switch (action) {
      case 'edit':
        final saved = await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
          builder: (_) => _ArticleForm(existing: article),
        );
        if (!(saved ?? false)) return;
      case 'delete':
        if (!await _confirmDelete(
          context,
          'Delete “${article.title}”?',
          'Clients will no longer find it in the knowledgebase.',
        )) {
          return;
        }
        await ref.read(supportAdminServiceProvider).deleteKbArticle(article.id);
        messenger.showSnackBar(
          const SnackBar(content: Text('Article deleted.')),
        );
    }
    ref.invalidate(kbArticlesProvider(null));
    ref.invalidate(kbCategoriesProvider);
  } on ApiException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  }
}

// ---------------------------------------------------------------------------
// Categories
// ---------------------------------------------------------------------------

class _CategoriesTab extends ConsumerWidget {
  const _CategoriesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(kbCategoriesProvider);

    return CrmAsyncView(
      value: categories,
      errorTitle: 'Could not load categories',
      onRetry: () => ref.invalidate(kbCategoriesProvider),
      builder: (items) => items.isEmpty
          ? const StateMessage(
              icon: Icons.category_outlined,
              title: 'No categories yet',
              message:
                  'Categories group articles in the portal; uncategorised '
                  'ones are filed under General.',
            )
          : RefreshIndicator(
              onRefresh: () => ref.refresh(kbCategoriesProvider.future),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(
                  Spacing.md,
                  Spacing.md,
                  Spacing.md,
                  Spacing.xl,
                ),
                children: [
                  const SectionHeader('Categories'),
                  const SizedBox(height: Spacing.sm),
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        for (final (i, category) in items.indexed) ...[
                          if (i > 0) const Divider(height: 1),
                          _CategoryRow(category: category),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

/// One category: the active chip beside its description, with the number of
/// articles inside it as the aligned trailing figure.
class _CategoryRow extends ConsumerWidget {
  const _CategoryRow({required this.category});

  final StaffKbCategory category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final meta = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return ListTile(
      onTap: () => _openCategoryActions(context, ref, category),
      title: Text(
        category.name,
        style: theme.textTheme.titleSmall,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(
          children: [
            StatusChip(category.isActive ? 'active' : 'draft', dense: true),
            if (category.description != null) ...[
              const SizedBox(width: Spacing.sm),
              Flexible(
                child: Text(
                  category.description!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: meta,
                ),
              ),
            ],
          ],
        ),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            Formatting.integer(category.articlesCount),
            style: theme.textTheme.labelMedium,
          ),
          const SizedBox(height: 2),
          Text('ARTICLES', style: meta),
        ],
      ),
    );
  }
}

Future<void> _openCategoryActions(
  BuildContext context,
  WidgetRef ref,
  StaffKbCategory category,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
    builder: (context) {
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;

      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.lg,
                0,
                Spacing.lg,
                Spacing.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'CATEGORY',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: Spacing.xs),
                  Text(
                    category.name,
                    style: Type.display(22, color: scheme.onSurface),
                  ),
                  const SizedBox(height: Spacing.sm),
                  StatusChip(
                    category.isActive ? 'active' : 'draft',
                    dense: true,
                  ),
                  const SizedBox(height: Spacing.md),
                  CrmDetailRow(
                    'Articles',
                    Formatting.integer(category.articlesCount),
                  ),
                  if (category.description != null)
                    CrmDetailRow('Description', category.description!),
                  if (category.slug != null)
                    CrmDetailRow('Slug', category.slug!),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit category'),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: scheme.error),
              title: Text(
                'Delete category',
                style: TextStyle(color: scheme.error),
              ),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      );
    },
  );
  if (action == null || !context.mounted) return;

  try {
    switch (action) {
      case 'edit':
        final saved = await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
          builder: (_) => _CategoryForm(existing: category),
        );
        if (!(saved ?? false)) return;
      case 'delete':
        if (!await _confirmDelete(
          context,
          'Delete “${category.name}”?',
          category.articlesCount == 0
              ? 'The category is empty.'
              : 'Its ${Formatting.integer(category.articlesCount)} '
                    'article(s) become uncategorised.',
        )) {
          return;
        }
        await ref
            .read(supportAdminServiceProvider)
            .deleteKbCategory(category.id);
        messenger.showSnackBar(
          const SnackBar(content: Text('Category deleted.')),
        );
    }
    ref.invalidate(kbCategoriesProvider);
    ref.invalidate(kbArticlesProvider(null));
  } on ApiException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  }
}

Future<bool> _confirmDelete(
  BuildContext context,
  String title,
  String body,
) async {
  final sure = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return sure ?? false;
}

// ---------------------------------------------------------------------------
// Editors
// ---------------------------------------------------------------------------

class _ArticleForm extends ConsumerStatefulWidget {
  const _ArticleForm({this.existing});

  final StaffKbArticle? existing;

  @override
  ConsumerState<_ArticleForm> createState() => _ArticleFormState();
}

class _ArticleFormState extends ConsumerState<_ArticleForm> {
  late final TextEditingController _title;
  late final TextEditingController _body;
  String? _categoryId;
  late bool _published;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.existing?.title ?? '');
    _body = TextEditingController(text: widget.existing?.body ?? '');
    _categoryId = widget.existing?.categoryId;
    _published = widget.existing?.isPublished ?? false;
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_title.text.trim().isEmpty || _body.text.trim().isEmpty) {
      setState(() => _error = 'A title and body are required.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final service = ref.read(supportAdminServiceProvider);
      final existing = widget.existing;
      if (existing == null) {
        await service.createKbArticle(
          title: _title.text.trim(),
          body: _body.text.trim(),
          categoryId: _categoryId,
          isPublished: _published,
        );
      } else {
        await service.updateKbArticle(
          existing.id,
          title: _title.text.trim(),
          body: _body.text.trim(),
          categoryId: _categoryId,
          isPublished: _published,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.errorFor('title') ?? e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final categories =
        ref.watch(kbCategoriesProvider).valueOrNull ??
        const <StaffKbCategory>[];
    final isHtml = _body.text.contains('<');

    return Padding(
      padding: EdgeInsets.fromLTRB(
        Spacing.lg,
        0,
        Spacing.lg,
        MediaQuery.viewInsetsOf(context).bottom + Spacing.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'KNOWLEDGEBASE',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Spacing.xs),
            Text(
              widget.existing == null ? 'New article' : 'Edit article',
              style: Type.display(22, color: scheme.onSurface),
            ),
            const SizedBox(height: Spacing.lg),
            if (_error != null) ...[
              ErrorBanner(message: _error!),
              const SizedBox(height: Spacing.md),
            ],
            const FieldLabel('Title'),
            const SizedBox(height: Spacing.sm),
            TextField(
              controller: _title,
              enabled: !_submitting,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'The question this answers',
              ),
            ),
            const SizedBox(height: Spacing.md),
            const FieldLabel('Category'),
            const SizedBox(height: Spacing.sm),
            DropdownButtonFormField<String?>(
              initialValue: _categoryId,
              isExpanded: true,
              decoration: const InputDecoration(hintText: 'Uncategorised'),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('Uncategorised'),
                ),
                for (final category in categories)
                  DropdownMenuItem(
                    value: category.id,
                    child: Text(category.name, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: _submitting
                  ? null
                  : (v) => setState(() => _categoryId = v),
            ),
            const SizedBox(height: Spacing.md),
            const FieldLabel('Body'),
            const SizedBox(height: Spacing.sm),
            TextField(
              controller: _body,
              enabled: !_submitting,
              maxLines: 10,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                alignLabelWithHint: true,
                hintText: 'The answer, in full',
                // Honest about the trade-off rather than quietly mangling it.
                helperText: isHtml
                    ? 'Contains HTML from the web editor — edit carefully'
                    : 'Plain text',
              ),
            ),
            const SizedBox(height: Spacing.sm),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Published'),
              subtitle: const Text('Readable in the client portal'),
              value: _published,
              onChanged: _submitting
                  ? null
                  : (v) => setState(() => _published = v),
            ),
            const SizedBox(height: Spacing.lg),
            PrimaryButton(
              label: _submitting ? 'Saving…' : 'Save article',
              busy: _submitting,
              onPressed: _submitting ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryForm extends ConsumerStatefulWidget {
  const _CategoryForm({this.existing});

  final StaffKbCategory? existing;

  @override
  ConsumerState<_CategoryForm> createState() => _CategoryFormState();
}

class _CategoryFormState extends ConsumerState<_CategoryForm> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late bool _active;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.existing?.name ?? '');
    _description = TextEditingController(
      text: widget.existing?.description ?? '',
    );
    _active = widget.existing?.isActive ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'A name is required.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final service = ref.read(supportAdminServiceProvider);
      final existing = widget.existing;
      final description = _description.text.trim().isEmpty
          ? null
          : _description.text.trim();
      if (existing == null) {
        await service.createKbCategory(
          name: _name.text.trim(),
          description: description,
          isActive: _active,
        );
      } else {
        await service.updateKbCategory(
          existing.id,
          name: _name.text.trim(),
          description: description,
          isActive: _active,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.errorFor('name') ?? e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        Spacing.lg,
        0,
        Spacing.lg,
        MediaQuery.viewInsetsOf(context).bottom + Spacing.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'KNOWLEDGEBASE',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Spacing.xs),
            Text(
              widget.existing == null ? 'New category' : 'Edit category',
              style: Type.display(22, color: scheme.onSurface),
            ),
            const SizedBox(height: Spacing.lg),
            if (_error != null) ...[
              ErrorBanner(message: _error!),
              const SizedBox(height: Spacing.md),
            ],
            const FieldLabel('Name'),
            const SizedBox(height: Spacing.sm),
            TextField(
              controller: _name,
              enabled: !_submitting,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(hintText: 'Billing, Hosting…'),
            ),
            const SizedBox(height: Spacing.md),
            const FieldLabel('Description'),
            const SizedBox(height: Spacing.sm),
            TextField(
              controller: _description,
              enabled: !_submitting,
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                alignLabelWithHint: true,
                hintText: 'What belongs in here (optional)',
              ),
            ),
            const SizedBox(height: Spacing.sm),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Active'),
              subtitle: const Text('Shown in the client portal'),
              value: _active,
              onChanged: _submitting
                  ? null
                  : (v) => setState(() => _active = v),
            ),
            const SizedBox(height: Spacing.lg),
            PrimaryButton(
              label: _submitting ? 'Saving…' : 'Save category',
              busy: _submitting,
              onPressed: _submitting ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}

