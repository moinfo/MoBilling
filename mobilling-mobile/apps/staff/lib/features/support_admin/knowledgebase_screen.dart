import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../crm/crm_ui.dart' show CrmAsyncView;
import 'support_admin_providers.dart';

/// Knowledgebase management: categories and articles.
class KnowledgebaseScreen extends ConsumerStatefulWidget {
  const KnowledgebaseScreen({super.key});

  @override
  ConsumerState<KnowledgebaseScreen> createState() =>
      _KnowledgebaseScreenState();
}

enum _Section { articles, categories }

class _KnowledgebaseScreenState extends ConsumerState<KnowledgebaseScreen> {
  _Section _section = _Section.articles;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Knowledgebase')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _section == _Section.articles
            ? _editArticle(context, null)
            : _editCategory(context, null),
        icon: const Icon(Icons.add),
        label: Text(_section == _Section.articles ? 'Article' : 'Category'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                Spacing.md, Spacing.sm, Spacing.md, Spacing.xs),
            child: SegmentedButton<_Section>(
              segments: const [
                ButtonSegment(
                    value: _Section.articles, label: Text('Articles')),
                ButtonSegment(
                    value: _Section.categories, label: Text('Categories')),
              ],
              selected: {_section},
              onSelectionChanged: (s) => setState(() => _section = s.first),
              showSelectedIcon: false,
            ),
          ),
          Expanded(
            child: _section == _Section.articles
                ? _buildArticles()
                : _buildCategories(),
          ),
        ],
      ),
    );
  }

  Widget _buildArticles() {
    final articles = ref.watch(kbArticlesProvider(null));
    final theme = Theme.of(context);

    return CrmAsyncView(
      value: articles,
      errorTitle: 'Could not load articles',
      onRetry: () => ref.invalidate(kbArticlesProvider(null)),
      builder: (items) => items.isEmpty
          ? const StateMessage(
              icon: Icons.menu_book_outlined,
              title: 'No articles yet',
              message: 'Published articles appear in the client portal.',
            )
          : ListView.separated(
              padding: const EdgeInsets.all(Spacing.md),
              itemCount: items.length,
              separatorBuilder: (context, index) =>
                  const SizedBox(height: Spacing.sm),
              itemBuilder: (context, index) {
                final article = items[index];
                return Card(
                  child: ListTile(
                    title: Text(article.title),
                    subtitle: Text(
                      [
                        article.categoryName ?? 'Uncategorised',
                        '${article.views} view${article.views == 1 ? '' : 's'}',
                      ].join(' · '),
                      style: theme.textTheme.bodySmall,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        StatusChip(article.status, dense: true),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 20),
                          onPressed: () => _deleteArticle(article),
                        ),
                      ],
                    ),
                    onTap: () => _editArticle(context, article),
                  ),
                );
              },
            ),
    );
  }

  Widget _buildCategories() {
    final categories = ref.watch(kbCategoriesProvider);
    final theme = Theme.of(context);

    return CrmAsyncView(
      value: categories,
      errorTitle: 'Could not load categories',
      onRetry: () => ref.invalidate(kbCategoriesProvider),
      builder: (items) => items.isEmpty
          ? const StateMessage(
              icon: Icons.category_outlined,
              title: 'No categories yet',
            )
          : ListView.separated(
              padding: const EdgeInsets.all(Spacing.md),
              itemCount: items.length,
              separatorBuilder: (context, index) =>
                  const SizedBox(height: Spacing.sm),
              itemBuilder: (context, index) {
                final category = items[index];
                return Card(
                  child: ListTile(
                    title: Text(category.name),
                    subtitle: Text(
                      '${category.articlesCount} article${category.articlesCount == 1 ? '' : 's'}',
                      style: theme.textTheme.bodySmall,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        StatusChip(
                            category.isActive ? 'active' : 'draft',
                            dense: true),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 20),
                          onPressed: () => _deleteCategory(category),
                        ),
                      ],
                    ),
                    onTap: () => _editCategory(context, category),
                  ),
                );
              },
            ),
    );
  }

  Future<void> _deleteArticle(StaffKbArticle article) async {
    // Captured before the confirm dialog's await.
    final messenger = ScaffoldMessenger.of(context);
    if (!await _confirm('Delete “${article.title}”?')) return;
    try {
      await ref.read(supportAdminServiceProvider).deleteKbArticle(article.id);
      ref.invalidate(kbArticlesProvider(null));
      ref.invalidate(kbCategoriesProvider);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _deleteCategory(StaffKbCategory category) async {
    final messenger = ScaffoldMessenger.of(context);
    if (!await _confirm('Delete “${category.name}”?')) return;
    try {
      await ref.read(supportAdminServiceProvider).deleteKbCategory(category.id);
      ref.invalidate(kbCategoriesProvider);
      ref.invalidate(kbArticlesProvider(null));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<bool> _confirm(String title) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    return sure == true;
  }

  Future<void> _editArticle(
      BuildContext context, StaffKbArticle? existing) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
      builder: (_) => _ArticleForm(existing: existing),
    );
    if (saved == true) {
      ref.invalidate(kbArticlesProvider(null));
      ref.invalidate(kbCategoriesProvider);
    }
  }

  Future<void> _editCategory(
      BuildContext context, StaffKbCategory? existing) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
      builder: (_) => _CategoryForm(existing: existing),
    );
    if (saved == true) ref.invalidate(kbCategoriesProvider);
  }
}

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
    final categories = ref.watch(kbCategoriesProvider).valueOrNull ??
        const <StaffKbCategory>[];

    return Padding(
      padding: EdgeInsets.only(
        left: Spacing.lg,
        right: Spacing.lg,
        top: Spacing.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + Spacing.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.existing == null ? 'New article' : 'Edit article',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center),
            const SizedBox(height: Spacing.md),
            if (_error != null) ...[
              ErrorBanner(message: _error!),
              const SizedBox(height: Spacing.sm),
            ],
            TextField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: Spacing.md),
            DropdownButtonFormField<String?>(
              initialValue: _categoryId,
              decoration: const InputDecoration(labelText: 'Category'),
              items: [
                const DropdownMenuItem(
                    value: null, child: Text('Uncategorised')),
                for (final category in categories)
                  DropdownMenuItem(
                      value: category.id, child: Text(category.name)),
              ],
              onChanged: _submitting
                  ? null
                  : (v) => setState(() => _categoryId = v),
            ),
            const SizedBox(height: Spacing.md),
            TextField(
              controller: _body,
              maxLines: 10,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Body',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: Spacing.sm),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Published'),
              value: _published,
              onChanged:
                  _submitting ? null : (v) => setState(() => _published = v),
            ),
            const SizedBox(height: Spacing.md),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: Text(_submitting ? 'Saving…' : 'Save'),
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
    _description =
        TextEditingController(text: widget.existing?.description ?? '');
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
      final description =
          _description.text.trim().isEmpty ? null : _description.text.trim();
      if (existing == null) {
        await service.createKbCategory(
            name: _name.text.trim(),
            description: description,
            isActive: _active);
      } else {
        await service.updateKbCategory(existing.id,
            name: _name.text.trim(),
            description: description,
            isActive: _active);
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
    return Padding(
      padding: EdgeInsets.only(
        left: Spacing.lg,
        right: Spacing.lg,
        top: Spacing.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + Spacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.existing == null ? 'New category' : 'Edit category',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center),
          const SizedBox(height: Spacing.md),
          if (_error != null) ...[
            ErrorBanner(message: _error!),
            const SizedBox(height: Spacing.sm),
          ],
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          const SizedBox(height: Spacing.md),
          TextField(
            controller: _description,
            maxLines: 2,
            decoration:
                const InputDecoration(labelText: 'Description (optional)'),
          ),
          const SizedBox(height: Spacing.sm),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Active'),
            value: _active,
            onChanged: _submitting ? null : (v) => setState(() => _active = v),
          ),
          const SizedBox(height: Spacing.md),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            child: Text(_submitting ? 'Saving…' : 'Save'),
          ),
        ],
      ),
    );
  }
}
