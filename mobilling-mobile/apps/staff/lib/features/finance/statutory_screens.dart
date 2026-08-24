import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';
import '../common/paged_list.dart';
import '../crm/crm_ui.dart' show CrmAsyncView;
import 'finance_providers.dart';

/// Statutory obligations — TRA, NSSF, licences and the like.
///
/// Status, days remaining and payment progress are all computed server-side
/// off the obligation's *current* bill, so nothing here re-derives them.
class StatutoryScreen extends ConsumerStatefulWidget {
  const StatutoryScreen({super.key});

  @override
  ConsumerState<StatutoryScreen> createState() => _StatutoryScreenState();
}

class _StatutoryScreenState extends ConsumerState<StatutoryScreen> {
  final _listKey = GlobalKey<PagedListViewState>();
  final _search = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => _listKey.currentState?.reload(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: ShellTopBar(
        eyebrow: 'Statutory',
        title: 'Obligations',
        bottom: InkSearchField(
          controller: _search,
          hint: 'Search obligation',
          onChanged: _onSearchChanged,
        ),
      ),
      body: PagedListView(
        key: _listKey,
        fetch: (page) => ref
            .read(financeServiceProvider)
            .statutories(
              search: _search.text.trim().isEmpty ? null : _search.text.trim(),
              page: page,
            ),
        itemBuilder: (context, statutory) =>
            StatutoryCard(statutory: statutory),
        emptyIcon: Icons.gavel_outlined,
        emptyTitle: 'No obligations configured',
        emptyMessage: 'Set up obligations from the web app to track them here.',
      ),
    );
  }
}

/// The same obligations, grouped by urgency with counters — the view someone
/// checks to know what to pay this week.
class StatutoryScheduleScreen extends ConsumerWidget {
  const StatutoryScheduleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schedule = ref.watch(statutoryScheduleProvider);
    final status = context.statusColors;

    return Scaffold(
      appBar: const ShellTopBar(eyebrow: 'Statutory', title: 'Schedule'),
      body: CrmAsyncView(
        value: schedule,
        errorTitle: 'Could not load the schedule',
        onRetry: () => ref.invalidate(statutoryScheduleProvider),
        builder: (data) {
          final overdue = data.items
              .where((s) => s.status == 'overdue')
              .toList();
          final dueSoon = data.items
              .where((s) => s.status == 'due_soon')
              .toList();
          final upcoming = data.items
              .where((s) => s.status == 'upcoming')
              .toList();
          final paid = data.items.where((s) => s.status == 'paid').toList();

          return RefreshIndicator(
            onRefresh: () => ref.refresh(statutoryScheduleProvider.future),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(Spacing.md),
              children: [
                // Three small counts: one rail, not three cards.
                StatRail(
                  items: [
                    StatRailItem(
                      label: 'Overdue',
                      value: Formatting.integer(data.stats.overdue),
                      emphasis: data.stats.overdue > 0 ? status.overdue : null,
                    ),
                    StatRailItem(
                      label: 'Due soon',
                      value: Formatting.integer(data.stats.dueSoon),
                      emphasis: data.stats.dueSoon > 0
                          ? status.attention
                          : null,
                    ),
                    StatRailItem(
                      label: 'Paid',
                      value: Formatting.integer(data.stats.paid),
                      emphasis: data.stats.paid > 0 ? status.settled : null,
                    ),
                  ],
                ),
                for (final (label, items) in [
                  ('Overdue', overdue),
                  ('Due soon', dueSoon),
                  ('Upcoming', upcoming),
                  ('Paid', paid),
                ])
                  if (items.isNotEmpty) ...[
                    const SizedBox(height: Spacing.lg),
                    SectionHeader(label),
                    const SizedBox(height: Spacing.sm),
                    Card(
                      child: Column(
                        children: [
                          for (final (i, statutory) in items.indexed) ...[
                            if (i > 0) const Divider(height: 1),
                            _StatutoryTile(statutory: statutory),
                          ],
                        ],
                      ),
                    ),
                  ],
                if (data.items.isEmpty) ...[
                  const SizedBox(height: Spacing.lg),
                  const StateMessage(
                    icon: Icons.event_available_outlined,
                    title: 'Nothing scheduled',
                    message: 'Obligations appear here once they are set up.',
                  ),
                ],
                const SizedBox(height: Spacing.xl),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// One obligation on its own card — the paged list's row.
class StatutoryCard extends StatelessWidget {
  const StatutoryCard({super.key, required this.statutory});

  final Statutory statutory;

  @override
  Widget build(BuildContext context) =>
      Card(child: _StatutoryTile(statutory: statutory));
}

/// The obligation row: name and amount, then the chip and the mono metadata
/// line, then — only while a bill is part-paid — the progress bar.
class _StatutoryTile extends StatelessWidget {
  const _StatutoryTile({required this.statutory});

  final Statutory statutory;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = context.statusColors;

    final chipStatus = switch (statutory.status) {
      'paid' => 'paid',
      'overdue' => 'overdue',
      'due_soon' => 'partial',
      _ => 'pending',
    };
    final due = statutory.nextDueDate == null
        ? null
        : statutory.isPaid
        ? 'due ${Formatting.date(statutory.nextDueDate)}'
        : statutory.daysRemaining < 0
        ? '${-statutory.daysRemaining}d overdue'
        : 'in ${statutory.daysRemaining}d';
    final partPaid = statutory.paidAmount > 0 && !statutory.isPaid;

    return ListTile(
      title: Text(
        statutory.name,
        style: theme.textTheme.titleSmall,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 2),
          Row(
            children: [
              StatusChip(chipStatus, dense: true),
              const SizedBox(width: Spacing.sm),
              Flexible(
                child: Text(
                  [
                    if (statutory.categoryName != null) statutory.categoryName!,
                    if (statutory.cycle != null)
                      statutory.cycle!.replaceAll('_', ' '),
                    ?due,
                  ].join(' · ').toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: statutory.isOverdue
                        ? status.overdue
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          if (partPaid) ...[
            const SizedBox(height: Spacing.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(Radii.sm),
              child: LinearProgressIndicator(
                value: (statutory.progressPercent / 100).clamp(0.0, 1.0),
                minHeight: 6,
                valueColor: AlwaysStoppedAnimation(status.settled),
              ),
            ),
            const SizedBox(height: Spacing.xs),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Money(
                  statutory.paidAmount,
                  scale: MoneyScale.dense,
                  showCode: false,
                  color: status.settled,
                ),
                Text(' paid', style: theme.textTheme.bodySmall),
                const Spacer(),
                Money(
                  statutory.remainingAmount,
                  scale: MoneyScale.dense,
                  showCode: false,
                ),
                Text(' remaining', style: theme.textTheme.bodySmall),
              ],
            ),
          ],
        ],
      ),
      trailing: Money(statutory.amount),
    );
  }
}

/// Recurring bills — the payables behind the obligations.
class BillsScreen extends ConsumerStatefulWidget {
  const BillsScreen({super.key});

  @override
  ConsumerState<BillsScreen> createState() => _BillsScreenState();
}

class _BillsScreenState extends ConsumerState<BillsScreen> {
  final _listKey = GlobalKey<PagedListViewState>();
  final _search = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => _listKey.currentState?.reload(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = context.statusColors;

    return Scaffold(
      appBar: ShellTopBar(
        eyebrow: 'Statutory',
        title: 'Bills',
        bottom: InkSearchField(
          controller: _search,
          hint: 'Search bill',
          onChanged: _onSearchChanged,
        ),
      ),
      body: PagedListView(
        key: _listKey,
        fetch: (page) => ref
            .read(financeServiceProvider)
            .bills(
              search: _search.text.trim().isEmpty ? null : _search.text.trim(),
              page: page,
            ),
        itemBuilder: (context, bill) => Card(
          child: ListTile(
            title: Text(
              bill.name,
              style: theme.textTheme.titleSmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 2),
                Row(
                  children: [
                    StatusChip(bill.status, dense: true),
                    const SizedBox(width: Spacing.sm),
                    Flexible(
                      child: Text(
                        [
                          if (bill.categoryName != null) bill.categoryName!,
                          if (bill.cycle != null)
                            bill.cycle!.replaceAll('_', ' '),
                          if (bill.dueDate != null)
                            // A settled bill is not overdue, however old.
                            bill.isPaid
                                ? 'Paid${bill.paidAt == null ? '' : ' ${Formatting.date(bill.paidAt)}'}'
                                : Formatting.dueDescription(bill.dueDate),
                        ].join(' · ').toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: bill.isOverdue
                              ? status.overdue
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                if (bill.remaining > 0) ...[
                  const SizedBox(height: Spacing.xs),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Money(
                        bill.remaining,
                        scale: MoneyScale.dense,
                        showCode: false,
                        color: bill.isOverdue ? status.overdue : null,
                      ),
                      Text(' remaining', style: theme.textTheme.bodySmall),
                    ],
                  ),
                ],
              ],
            ),
            trailing: Money(bill.amount),
          ),
        ),
        emptyIcon: Icons.request_page_outlined,
        emptyTitle: 'No bills configured',
        emptyMessage: 'Bills appear here once an obligation raises one.',
      ),
    );
  }
}

/// Bill categories, nested one level deep.
class BillCategoriesScreen extends ConsumerWidget {
  const BillCategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(billCategoriesProvider);
    final canCreate =
        ref
            .watch(sessionControllerProvider)
            .session
            ?.can(FinancePermissions.billsCreate) ??
        false;

    return Scaffold(
      appBar: ShellTopBar(
        eyebrow: 'Statutory',
        title: 'Bill categories',
        trailing: !canCreate
            ? null
            : InkActionButton(
                icon: Icons.add_rounded,
                tooltip: 'Add category',
                onPressed: () => _add(context, ref),
              ),
      ),
      body: CrmAsyncView(
        value: categories,
        errorTitle: 'Could not load categories',
        onRetry: () => ref.invalidate(billCategoriesProvider),
        builder: (items) => items.isEmpty
            ? StateMessage(
                icon: Icons.category_outlined,
                title: 'No bill categories',
                message: 'Categories group bills so reports can total them.',
                actionLabel: canCreate ? 'Add category' : null,
                onAction: canCreate ? () => _add(context, ref) : null,
              )
            : ListView(
                padding: const EdgeInsets.all(Spacing.md),
                children: [
                  Card(
                    child: Column(
                      children: [
                        for (final (i, category) in items.indexed) ...[
                          if (i > 0) const Divider(height: 1),
                          if (category.children.isEmpty)
                            _CategoryTile(
                              name: category.name,
                              detail: category.billingCycle?.replaceAll(
                                '_',
                                ' ',
                              ),
                            )
                          else
                            ExpansionTile(
                              shape: const Border(),
                              collapsedShape: const Border(),
                              title: Text(
                                category.name,
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              subtitle: _MetaLine(
                                '${Formatting.integer(category.children.length)} '
                                'sub-categor${category.children.length == 1 ? 'y' : 'ies'}',
                              ),
                              children: [
                                for (final child in category.children)
                                  _CategoryTile(
                                    name: child.name,
                                    detail: child.billingCycle?.replaceAll(
                                      '_',
                                      ' ',
                                    ),
                                    nested: true,
                                  ),
                              ],
                            ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: Spacing.xl),
                ],
              ),
      ),
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);
    final parents =
        ref.read(billCategoriesProvider).valueOrNull ?? const <BillCategory>[];
    String? parentId;

    final saved = await _CategoryDialog.show(
      context,
      title: 'New bill category',
      name: name,
      parents: [for (final p in parents) (p.id, p.name)],
      onParentChanged: (v) => parentId = v,
    );

    if (saved != true || name.text.trim().isEmpty) return;

    try {
      await ref
          .read(financeServiceProvider)
          .createBillCategory(name: name.text.trim(), parentId: parentId);
      ref.invalidate(billCategoriesProvider);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

/// Expense categories, same nested shape.
class ExpenseCategoriesScreen extends ConsumerWidget {
  const ExpenseCategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(expenseCategoriesProvider);
    final theme = Theme.of(context);
    final canCreate =
        ref
            .watch(sessionControllerProvider)
            .session
            ?.can(FinancePermissions.expenseCategoriesCreate) ??
        false;

    return Scaffold(
      appBar: ShellTopBar(
        eyebrow: 'Expenses',
        title: 'Expense categories',
        trailing: !canCreate
            ? null
            : InkActionButton(
                icon: Icons.add_rounded,
                tooltip: 'Add category',
                onPressed: () => _add(context, ref),
              ),
      ),
      body: CrmAsyncView(
        value: categories,
        errorTitle: 'Could not load categories',
        onRetry: () => ref.invalidate(expenseCategoriesProvider),
        builder: (items) => items.isEmpty
            ? StateMessage(
                icon: Icons.category_outlined,
                title: 'No expense categories',
                message:
                    'Expenses attach to sub-categories, so add a category and then its sub-categories.',
                actionLabel: canCreate ? 'Add category' : null,
                onAction: canCreate ? () => _add(context, ref) : null,
              )
            : ListView(
                padding: const EdgeInsets.all(Spacing.md),
                children: [
                  Card(
                    child: Column(
                      children: [
                        for (final (i, category) in items.indexed) ...[
                          if (i > 0) const Divider(height: 1),
                          ExpansionTile(
                            shape: const Border(),
                            collapsedShape: const Border(),
                            title: Text(
                              category.name,
                              style: theme.textTheme.titleSmall,
                            ),
                            subtitle: _MetaLine(
                              '${Formatting.integer(category.subCategories.length)} '
                              'sub-categor${category.subCategories.length == 1 ? 'y' : 'ies'}',
                            ),
                            children: [
                              for (final sub in category.subCategories)
                                _CategoryTile(name: sub.name, nested: true),
                              if (category.subCategories.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    Spacing.md,
                                    0,
                                    Spacing.md,
                                    Spacing.md,
                                  ),
                                  child: Text(
                                    'No sub-categories yet — expenses attach to sub-categories only.',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: Spacing.xl),
                ],
              ),
      ),
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);
    final parents =
        ref.read(expenseCategoriesProvider).valueOrNull ??
        const <ExpenseCategory>[];
    String? parentId;

    final saved = await _CategoryDialog.show(
      context,
      title: 'New expense category',
      name: name,
      parents: [for (final p in parents) (p.id, p.name)],
      onParentChanged: (v) => parentId = v,
    );

    if (saved != true || name.text.trim().isEmpty) return;

    try {
      await ref
          .read(financeServiceProvider)
          .createExpenseCategory(name: name.text.trim(), parentId: parentId);
      ref.invalidate(expenseCategoriesProvider);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

// ---------------------------------------------------------------------------
// Private building blocks (candidates for mobilling_ui)
// ---------------------------------------------------------------------------

/// A mono metadata line under a list title.
class _MetaLine extends StatelessWidget {
  const _MetaLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text.toUpperCase(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// A category row; [nested] indents it under its parent.
class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.name, this.detail, this.nested = false});

  final String name;
  final String? detail;
  final bool nested;

  @override
  Widget build(BuildContext context) => ListTile(
    dense: nested,
    contentPadding: nested
        ? const EdgeInsets.only(left: Spacing.xl, right: Spacing.md)
        : null,
    title: Text(
      name,
      style: nested
          ? Theme.of(context).textTheme.bodyMedium
          : Theme.of(context).textTheme.titleSmall,
    ),
    subtitle: detail == null ? null : _MetaLine(detail!),
  );
}

/// The "new category" dialog shared by bills and expenses: a name and an
/// optional parent. Returns true when the form was confirmed.
class _CategoryDialog {
  static Future<bool?> show(
    BuildContext context, {
    required String title,
    required TextEditingController name,
    required List<(String, String)> parents,
    required ValueChanged<String?> onParentChanged,
  }) {
    final scheme = Theme.of(context).colorScheme;
    String? parentId;

    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(title, style: Type.display(22, color: scheme.onSurface)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const FieldLabel('Name'),
              const SizedBox(height: Spacing.sm),
              TextField(
                controller: name,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  hintText: 'What the category is called',
                ),
              ),
              const SizedBox(height: Spacing.md),
              const FieldLabel('Parent (optional)'),
              const SizedBox(height: Spacing.sm),
              DropdownButtonFormField<String?>(
                initialValue: parentId,
                isExpanded: true,
                decoration: const InputDecoration(
                  helperText: 'Leave as top level for a new group',
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Top level')),
                  for (final (id, label) in parents)
                    DropdownMenuItem(value: id, child: Text(label)),
                ],
                onChanged: (v) {
                  setDialogState(() => parentId = v);
                  onParentChanged(v);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Create category'),
            ),
          ],
        ),
      ),
    );
  }
}
