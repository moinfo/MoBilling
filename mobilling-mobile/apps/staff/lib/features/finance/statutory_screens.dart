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
    _debounce = Timer(const Duration(milliseconds: 400),
        () => _listKey.currentState?.reload());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Obligations')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                Spacing.md, Spacing.sm, Spacing.md, Spacing.xs),
            child: TextField(
              controller: _search,
              onChanged: _onSearchChanged,
              decoration: const InputDecoration(
                hintText: 'Search obligation',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
            ),
          ),
          Expanded(
            child: PagedListView(
              key: _listKey,
              fetch: (page) => ref.read(financeServiceProvider).statutories(
                    search: _search.text.trim().isEmpty
                        ? null
                        : _search.text.trim(),
                    page: page,
                  ),
              itemBuilder: (context, statutory) =>
                  StatutoryCard(statutory: statutory),
              emptyIcon: Icons.gavel_outlined,
              emptyTitle: 'No obligations configured',
            ),
          ),
        ],
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
    final theme = Theme.of(context);
    final status = context.statusColors;

    return Scaffold(
      appBar: AppBar(title: const Text('Statutory schedule')),
      body: CrmAsyncView(
        value: schedule,
        errorTitle: 'Could not load the schedule',
        onRetry: () => ref.invalidate(statutoryScheduleProvider),
        builder: (data) {
          final overdue =
              data.items.where((s) => s.status == 'overdue').toList();
          final dueSoon =
              data.items.where((s) => s.status == 'due_soon').toList();
          final upcoming =
              data.items.where((s) => s.status == 'upcoming').toList();
          final paid = data.items.where((s) => s.status == 'paid').toList();

          return RefreshIndicator(
            onRefresh: () => ref.refresh(statutoryScheduleProvider.future),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(Spacing.md),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: StatTile(
                        label: 'Overdue',
                        value: '${data.stats.overdue}',
                        emphasis: data.stats.overdue > 0
                            ? status.overdue
                            : null,
                      ),
                    ),
                    const SizedBox(width: Spacing.sm),
                    Expanded(
                      child: StatTile(
                        label: 'Due soon',
                        value: '${data.stats.dueSoon}',
                        emphasis: data.stats.dueSoon > 0
                            ? status.attention
                            : null,
                      ),
                    ),
                    const SizedBox(width: Spacing.sm),
                    Expanded(
                      child: StatTile(
                        label: 'Paid',
                        value: '${data.stats.paid}',
                        emphasis: status.settled,
                      ),
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
                    Text(label, style: theme.textTheme.titleSmall),
                    const SizedBox(height: Spacing.sm),
                    for (final statutory in items)
                      StatutoryCard(statutory: statutory),
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

class StatutoryCard extends StatelessWidget {
  const StatutoryCard({super.key, required this.statutory});

  final Statutory statutory;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = context.statusColors;

    final chipStatus = switch (statutory.status) {
      'paid' => 'paid',
      'overdue' => 'overdue',
      'due_soon' => 'partial',
      _ => 'pending',
    };

    return Card(
      margin: const EdgeInsets.only(bottom: Spacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(statutory.name,
                      style: theme.textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                Money(statutory.amount),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              [
                if (statutory.categoryName != null) statutory.categoryName!,
                if (statutory.cycle != null)
                  statutory.cycle!.replaceAll('_', ' '),
                if (statutory.nextDueDate != null)
                  statutory.isPaid
                      ? 'due ${Formatting.date(statutory.nextDueDate)}'
                      : statutory.daysRemaining < 0
                          ? '${-statutory.daysRemaining}d overdue'
                          : 'in ${statutory.daysRemaining}d',
              ].join(' · '),
              style: theme.textTheme.bodySmall?.copyWith(
                color: statutory.isOverdue
                    ? status.overdue
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (statutory.paidAmount > 0 && !statutory.isPaid) ...[
              const SizedBox(height: Spacing.xs),
              ClipRRect(
                borderRadius: BorderRadius.circular(Radii.sm),
                child: LinearProgressIndicator(
                  value: (statutory.progressPercent / 100).clamp(0.0, 1.0),
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${Formatting.amount(statutory.paidAmount)} paid · ${Formatting.amount(statutory.remainingAmount)} remaining',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: Spacing.xs),
            StatusChip(chipStatus, dense: true),
          ],
        ),
      ),
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
    _debounce = Timer(const Duration(milliseconds: 400),
        () => _listKey.currentState?.reload());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Bills')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                Spacing.md, Spacing.sm, Spacing.md, Spacing.xs),
            child: TextField(
              controller: _search,
              onChanged: _onSearchChanged,
              decoration: const InputDecoration(
                hintText: 'Search bill',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
            ),
          ),
          Expanded(
            child: PagedListView(
              key: _listKey,
              fetch: (page) => ref.read(financeServiceProvider).bills(
                    search: _search.text.trim().isEmpty
                        ? null
                        : _search.text.trim(),
                    page: page,
                  ),
              itemBuilder: (context, bill) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(Spacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(bill.name,
                                style: theme.textTheme.titleSmall,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                          ),
                          Money(bill.amount),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (bill.categoryName != null) bill.categoryName!,
                          if (bill.cycle != null)
                            bill.cycle!.replaceAll('_', ' '),
                          if (bill.dueDate != null)
                            Formatting.dueDescription(bill.dueDate),
                        ].join(' · '),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: bill.isOverdue
                              ? context.statusColors.overdue
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: Spacing.xs),
                      Row(
                        children: [
                          StatusChip(bill.status, dense: true),
                          const Spacer(),
                          if (bill.remaining > 0)
                            Text(
                              '${Formatting.amount(bill.remaining)} remaining',
                              style: theme.textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              emptyIcon: Icons.request_page_outlined,
              emptyTitle: 'No bills configured',
            ),
          ),
        ],
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
    final theme = Theme.of(context);
    final canCreate = ref.watch(sessionControllerProvider).session?.can(
              FinancePermissions.billsCreate,
            ) ??
        false;

    return Scaffold(
      appBar: AppBar(title: const Text('Bill categories')),
      floatingActionButton: !canCreate
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _add(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('Category'),
            ),
      body: CrmAsyncView(
        value: categories,
        errorTitle: 'Could not load categories',
        onRetry: () => ref.invalidate(billCategoriesProvider),
        builder: (items) => items.isEmpty
            ? const StateMessage(
                icon: Icons.category_outlined,
                title: 'No bill categories',
              )
            : ListView.separated(
                padding: const EdgeInsets.all(Spacing.md),
                itemCount: items.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: Spacing.sm),
                itemBuilder: (context, index) {
                  final category = items[index];
                  return Card(
                    child: category.children.isEmpty
                        ? ListTile(
                            title: Text(category.name),
                            subtitle: category.billingCycle == null
                                ? null
                                : Text(
                                    category.billingCycle!
                                        .replaceAll('_', ' '),
                                    style: theme.textTheme.bodySmall),
                          )
                        : ExpansionTile(
                            shape: const Border(),
                            collapsedShape: const Border(),
                            title: Text(category.name),
                            subtitle: Text(
                                '${category.children.length} sub-categor${category.children.length == 1 ? 'y' : 'ies'}',
                                style: theme.textTheme.bodySmall),
                            children: [
                              for (final child in category.children)
                                ListTile(
                                  dense: true,
                                  contentPadding: const EdgeInsets.only(
                                      left: Spacing.xl, right: Spacing.md),
                                  title: Text(child.name),
                                  subtitle: child.billingCycle == null
                                      ? null
                                      : Text(
                                          child.billingCycle!
                                              .replaceAll('_', ' '),
                                          style: theme.textTheme.bodySmall),
                                ),
                            ],
                          ),
                  );
                },
              ),
      ),
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);
    final parents = ref.read(billCategoriesProvider).valueOrNull ??
        const <BillCategory>[];
    String? parentId;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('New bill category'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: Spacing.md),
              DropdownButtonFormField<String?>(
                initialValue: parentId,
                isExpanded: true,
                decoration:
                    const InputDecoration(labelText: 'Parent (optional)'),
                items: [
                  const DropdownMenuItem(
                      value: null, child: Text('Top level')),
                  for (final parent in parents)
                    DropdownMenuItem(
                        value: parent.id, child: Text(parent.name)),
                ],
                onChanged: (v) => setDialogState(() => parentId = v),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Create')),
          ],
        ),
      ),
    );

    if (saved != true || name.text.trim().isEmpty) return;

    try {
      await ref.read(financeServiceProvider).createBillCategory(
            name: name.text.trim(),
            parentId: parentId,
          );
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
    final canCreate = ref.watch(sessionControllerProvider).session?.can(
              FinancePermissions.expenseCategoriesCreate,
            ) ??
        false;

    return Scaffold(
      appBar: AppBar(title: const Text('Expense categories')),
      floatingActionButton: !canCreate
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _add(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('Category'),
            ),
      body: CrmAsyncView(
        value: categories,
        errorTitle: 'Could not load categories',
        onRetry: () => ref.invalidate(expenseCategoriesProvider),
        builder: (items) => items.isEmpty
            ? const StateMessage(
                icon: Icons.category_outlined,
                title: 'No expense categories',
              )
            : ListView.separated(
                padding: const EdgeInsets.all(Spacing.md),
                itemCount: items.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: Spacing.sm),
                itemBuilder: (context, index) {
                  final category = items[index];
                  return Card(
                    child: ExpansionTile(
                      shape: const Border(),
                      collapsedShape: const Border(),
                      title: Text(category.name),
                      subtitle: Text(
                        '${category.subCategories.length} sub-categor${category.subCategories.length == 1 ? 'y' : 'ies'}',
                        style: theme.textTheme.bodySmall,
                      ),
                      children: [
                        for (final sub in category.subCategories)
                          ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.only(
                                left: Spacing.xl, right: Spacing.md),
                            title: Text(sub.name),
                          ),
                        if (category.subCategories.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(Spacing.md),
                            child: Text(
                              'No sub-categories — expenses attach to sub-categories only.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);
    final parents = ref.read(expenseCategoriesProvider).valueOrNull ??
        const <ExpenseCategory>[];
    String? parentId;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('New expense category'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: Spacing.md),
              DropdownButtonFormField<String?>(
                initialValue: parentId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Parent',
                  helperText: 'Leave blank to create a top-level category',
                ),
                items: [
                  const DropdownMenuItem(
                      value: null, child: Text('Top level')),
                  for (final parent in parents)
                    DropdownMenuItem(
                        value: parent.id, child: Text(parent.name)),
                ],
                onChanged: (v) => setDialogState(() => parentId = v),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Create')),
          ],
        ),
      ),
    );

    if (saved != true || name.text.trim().isEmpty) return;

    try {
      await ref.read(financeServiceProvider).createExpenseCategory(
            name: name.text.trim(),
            parentId: parentId,
          );
      ref.invalidate(expenseCategoriesProvider);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}
