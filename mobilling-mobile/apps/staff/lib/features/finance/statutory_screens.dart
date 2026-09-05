import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';
import '../common/paged_list.dart';
import '../crm/crm_ui.dart'
    show CrmAsyncView, CrmField, CrmPickerField, CrmSheet, showCrmSheet;
import 'finance_providers.dart';

/// The five cycles a statutory obligation or a bill can carry, in the same
/// vocabulary the catalog's billing-cycle picker uses.
const _cycles = [
  ('once', 'One-time'),
  ('monthly', 'Monthly'),
  ('quarterly', 'Quarterly'),
  ('half_yearly', 'Half-yearly'),
  ('yearly', 'Yearly'),
];

/// Bill categories nest one level; flattened here as `(id, label)` pairs for
/// a plain dropdown, the child indented under its parent's name.
List<(String, String)> _flattenBillCategories(List<BillCategory> categories) =>
    [
      for (final category in categories) ...[
        (category.id, category.name),
        for (final child in category.children)
          (child.id, '${category.name} › ${child.name}'),
      ],
    ];

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

  /// A create, edit or delete all change what the schedule screen counts, so
  /// both are refreshed together rather than trusting whichever loads first.
  void _reload() {
    _listKey.currentState?.reload();
    ref.invalidate(statutoryScheduleProvider);
  }

  Future<void> _create(BuildContext context) async {
    final saved = await showCrmSheet<bool>(
      context: context,
      builder: (_) => const _StatutoryFormSheet(),
    );
    if (saved == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(sessionControllerProvider).session;
    final canCreate = auth?.can(FinancePermissions.statutoriesCreate) ?? false;
    final canUpdate = auth?.can(FinancePermissions.statutoriesUpdate) ?? false;
    final canDelete = auth?.can(FinancePermissions.statutoriesDelete) ?? false;

    return Scaffold(
      appBar: ShellTopBar(
        eyebrow: 'Statutory',
        title: 'Obligations',
        trailing: !canCreate
            ? null
            : InkActionButton(
                icon: Icons.add_rounded,
                tooltip: 'Add obligation',
                onPressed: () => _create(context),
              ),
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
        itemBuilder: (context, statutory) => StatutoryCard(
          statutory: statutory,
          canUpdate: canUpdate,
          canDelete: canDelete,
          onChanged: _reload,
        ),
        emptyIcon: Icons.gavel_outlined,
        emptyTitle: 'No obligations yet',
        emptyMessage: canCreate
            ? 'Add one with the + button above.'
            : 'Nothing matches this search.',
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
                // Four small counts: one rail, not four cards.
                StatRail(
                  items: [
                    StatRailItem(
                      label: 'Total active',
                      value: Formatting.integer(data.stats.total),
                    ),
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

/// One obligation on its own card — the paged list's row. Read-only unless
/// [canUpdate] or [canDelete] grants an action, in which case a tap opens
/// them; [onChanged] tells the list to reload afterwards.
class StatutoryCard extends ConsumerWidget {
  const StatutoryCard({
    super.key,
    required this.statutory,
    this.canUpdate = false,
    this.canDelete = false,
    this.onChanged,
  });

  final Statutory statutory;
  final bool canUpdate;
  final bool canDelete;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Card(
    child: _StatutoryTile(
      statutory: statutory,
      onTap: (canUpdate || canDelete) ? () => _showActions(context, ref) : null,
    ),
  );

  Future<void> _showActions(BuildContext context, WidgetRef ref) async {
    final scheme = Theme.of(context).colorScheme;
    final choice = await showCrmSheet<String>(
      context: context,
      builder: (context) => CrmSheet(
        eyebrow: Formatting.currency(statutory.amount),
        title: statutory.name,
        children: [
          Card(
            child: Column(
              children: [
                if (canUpdate)
                  ListTile(
                    leading: const Icon(Icons.edit_outlined),
                    title: const Text('Edit'),
                    onTap: () => Navigator.pop(context, 'edit'),
                  ),
                if (canDelete)
                  ListTile(
                    leading: Icon(Icons.delete_outline, color: scheme.error),
                    title: Text(
                      'Delete',
                      style: TextStyle(color: scheme.error),
                    ),
                    onTap: () => Navigator.pop(context, 'delete'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (choice == null || !context.mounted) return;

    switch (choice) {
      case 'edit':
        await _edit(context);
      case 'delete':
        await _delete(context, ref);
    }
  }

  Future<void> _edit(BuildContext context) async {
    final saved = await showCrmSheet<bool>(
      context: context,
      builder: (_) => _StatutoryFormSheet(statutory: statutory),
    );
    if (saved == true) onChanged?.call();
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final scheme = Theme.of(context).colorScheme;
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete "${statutory.name}"?'),
        content: const Text(
          'Its current bill goes with it. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: scheme.error),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(financeServiceProvider).deleteStatutory(statutory.id);
      onChanged?.call();
      messenger.showSnackBar(
        const SnackBar(content: Text('Obligation deleted.')),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

/// The obligation row: name and amount, then the chip and the mono metadata
/// line, then — only while a bill is part-paid — the progress bar.
///
/// [onTap] is left null on the schedule screen, which stays a read-only
/// report; only the obligations list wires it to open actions.
class _StatutoryTile extends StatelessWidget {
  const _StatutoryTile({required this.statutory, this.onTap});

  final Statutory statutory;
  final VoidCallback? onTap;

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
      onTap: onTap,
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

  Future<void> _create(BuildContext context) async {
    final saved = await showCrmSheet<bool>(
      context: context,
      builder: (_) => const _BillFormSheet(),
    );
    if (saved == true) _listKey.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(sessionControllerProvider).session;
    final canCreate = auth?.can(FinancePermissions.billsCreate) ?? false;
    final canUpdate = auth?.can(FinancePermissions.billsUpdate) ?? false;
    final canDelete = auth?.can(FinancePermissions.billsDelete) ?? false;

    return Scaffold(
      appBar: ShellTopBar(
        eyebrow: 'Statutory',
        title: 'Bills',
        trailing: !canCreate
            ? null
            : InkActionButton(
                icon: Icons.add_rounded,
                tooltip: 'Add bill',
                onPressed: () => _create(context),
              ),
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
        itemBuilder: (context, bill) => _BillCard(
          bill: bill,
          canUpdate: canUpdate,
          canDelete: canDelete,
          onChanged: () => _listKey.currentState?.reload(),
        ),
        emptyIcon: Icons.request_page_outlined,
        emptyTitle: 'No bills yet',
        emptyMessage: canCreate
            ? 'Add one with the + button above.'
            : 'Bills appear here once an obligation raises one.',
      ),
    );
  }
}

/// One bill on its own card — tapping opens edit / delete / mark-paid.
class _BillCard extends ConsumerWidget {
  const _BillCard({
    required this.bill,
    this.canUpdate = false,
    this.canDelete = false,
    this.onChanged,
  });

  final StaffBill bill;
  final bool canUpdate;
  final bool canDelete;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = context.statusColors;

    return Card(
      child: ListTile(
        onTap: (canUpdate || canDelete || !bill.isPaid)
            ? () => _showActions(context, ref)
            : null,
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
                      if (bill.cycle != null) bill.cycle!.replaceAll('_', ' '),
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
    );
  }

  Future<void> _showActions(BuildContext context, WidgetRef ref) async {
    final scheme = Theme.of(context).colorScheme;
    final choice = await showCrmSheet<String>(
      context: context,
      builder: (context) => CrmSheet(
        eyebrow: Formatting.currency(bill.amount),
        title: bill.name,
        children: [
          Card(
            child: Column(
              children: [
                if (!bill.isPaid)
                  ListTile(
                    leading: const Icon(Icons.payments_outlined),
                    title: const Text('Mark paid'),
                    subtitle: const Text('Record a payment against this bill.'),
                    onTap: () => Navigator.pop(context, 'pay'),
                  ),
                if (canUpdate)
                  ListTile(
                    leading: const Icon(Icons.edit_outlined),
                    title: const Text('Edit'),
                    onTap: () => Navigator.pop(context, 'edit'),
                  ),
                if (canDelete)
                  ListTile(
                    leading: Icon(Icons.delete_outline, color: scheme.error),
                    title: Text(
                      'Delete',
                      style: TextStyle(color: scheme.error),
                    ),
                    onTap: () => Navigator.pop(context, 'delete'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (choice == null || !context.mounted) return;

    switch (choice) {
      case 'pay':
        await _pay(context);
      case 'edit':
        await _edit(context);
      case 'delete':
        await _delete(context, ref);
    }
  }

  /// Pays this bill through the same flow Payment History's "Pay a bill"
  /// button uses, preselected so it jumps straight to the payment form
  /// instead of the picker.
  Future<void> _pay(BuildContext context) async {
    final paid = await context.push<bool>('/payments-out/new', extra: bill);
    if (paid == true) onChanged?.call();
  }

  Future<void> _edit(BuildContext context) async {
    final saved = await showCrmSheet<bool>(
      context: context,
      builder: (_) => _BillFormSheet(bill: bill),
    );
    if (saved == true) onChanged?.call();
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final scheme = Theme.of(context).colorScheme;
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete "${bill.name}"?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: scheme.error),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(financeServiceProvider).deleteBill(bill.id);
      onChanged?.call();
      messenger.showSnackBar(const SnackBar(content: Text('Bill deleted.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

/// Bill categories, nested one level deep.
class BillCategoriesScreen extends ConsumerWidget {
  const BillCategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(billCategoriesProvider);
    final auth = ref.watch(sessionControllerProvider).session;
    final canCreate = auth?.can(FinancePermissions.billsCreate) ?? false;
    final canUpdate = auth?.can(FinancePermissions.billsUpdate) ?? false;
    final canDelete = auth?.can(FinancePermissions.billsDelete) ?? false;

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
                              isActive: category.isActive,
                              onTap: (canUpdate || canDelete)
                                  ? () => _actions(
                                      context,
                                      ref,
                                      category: category,
                                      parentId: null,
                                      canUpdate: canUpdate,
                                      canDelete: canDelete,
                                    )
                                  : null,
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
                              trailing: (canUpdate || canDelete)
                                  ? IconButton(
                                      icon: const Icon(Icons.more_vert),
                                      onPressed: () => _actions(
                                        context,
                                        ref,
                                        category: category,
                                        parentId: null,
                                        canUpdate: canUpdate,
                                        canDelete: canDelete,
                                      ),
                                    )
                                  : null,
                              children: [
                                for (final child in category.children)
                                  _CategoryTile(
                                    name: child.name,
                                    detail: child.billingCycle?.replaceAll(
                                      '_',
                                      ' ',
                                    ),
                                    nested: true,
                                    isActive: child.isActive,
                                    onTap: (canUpdate || canDelete)
                                        ? () => _actions(
                                            context,
                                            ref,
                                            category: child,
                                            parentId: category.id,
                                            canUpdate: canUpdate,
                                            canDelete: canDelete,
                                          )
                                        : null,
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

  /// Edit / Delete for one row — [parentId] is null for a top-level category
  /// (it cannot itself have a parent) and set for a sub-category.
  Future<void> _actions(
    BuildContext context,
    WidgetRef ref, {
    required BillCategory category,
    required String? parentId,
    required bool canUpdate,
    required bool canDelete,
  }) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: Spacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (canUpdate)
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Edit'),
                  onTap: () => Navigator.pop(sheetContext, 'edit'),
                ),
              if (canDelete)
                ListTile(
                  leading: Icon(
                    Icons.delete_outline,
                    color: Theme.of(sheetContext).colorScheme.error,
                  ),
                  title: Text(
                    'Delete',
                    style: TextStyle(
                      color: Theme.of(sheetContext).colorScheme.error,
                    ),
                  ),
                  onTap: () => Navigator.pop(sheetContext, 'delete'),
                ),
            ],
          ),
        ),
      ),
    );
    if (!context.mounted || choice == null) return;

    switch (choice) {
      case 'edit':
        await _edit(context, ref, category: category, parentId: parentId);
      case 'delete':
        await _delete(context, ref, id: category.id, name: category.name);
    }
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref, {
    required BillCategory category,
    required String? parentId,
  }) async {
    final nameController = TextEditingController(text: category.name);
    final parents =
        ref.read(billCategoriesProvider).valueOrNull ?? const <BillCategory>[];
    var newParentId = parentId;
    var billingCycle = category.billingCycle;

    // A sub-category can move to another parent; a top-level category has no
    // parent field at all — it would have to become a sub-category of itself
    // otherwise.
    final saved = await _CategoryDialog.show(
      context,
      title: 'Edit bill category',
      name: nameController,
      parents: parentId == null
          ? const []
          : [for (final p in parents) (p.id, p.name)],
      initialParentId: parentId,
      onParentChanged: (v) => newParentId = v,
      initialBillingCycle: billingCycle,
      onBillingCycleChanged: (v) => billingCycle = v,
      confirmLabel: 'Save changes',
    );
    if (saved != true || !context.mounted) return;
    await _save(
      context,
      ref,
      id: category.id,
      name: nameController.text.trim(),
      parentId: newParentId,
      billingCycle: billingCycle,
    );
  }

  Future<void> _save(
    BuildContext context,
    WidgetRef ref, {
    required String id,
    required String name,
    required String? parentId,
    required String? billingCycle,
  }) async {
    if (name.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(financeServiceProvider)
          .updateBillCategory(
            id,
            name: name,
            parentId: parentId,
            billingCycle: billingCycle,
          );
      ref.invalidate(billCategoriesProvider);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref, {
    required String id,
    required String name,
  }) async {
    final scheme = Theme.of(context).colorScheme;
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete "$name"?'),
        content: const Text(
          'Refused while any bill, or a sub-category, still points at it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: scheme.error),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final message = await ref
          .read(financeServiceProvider)
          .deleteBillCategory(id);
      ref.invalidate(billCategoriesProvider);
      messenger.showSnackBar(
        SnackBar(content: Text(message ?? '"$name" deleted.')),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

/// Create or edit a statutory obligation. The server computes `next_due_date`
/// and (on create) generates the first bill itself — nothing else to send.
class _StatutoryFormSheet extends ConsumerStatefulWidget {
  const _StatutoryFormSheet({this.statutory});

  /// The obligation being edited, or null to create one.
  final Statutory? statutory;

  @override
  ConsumerState<_StatutoryFormSheet> createState() =>
      _StatutoryFormSheetState();
}

class _StatutoryFormSheetState extends ConsumerState<_StatutoryFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.statutory?.name ?? '');
  late final _amount = TextEditingController(
    text: widget.statutory == null
        ? ''
        : widget.statutory!.amount.toStringAsFixed(2),
  );
  late final _remindDays = TextEditingController(
    text: widget.statutory?.remindDaysBefore?.toString() ?? '',
  );
  late final _notes = TextEditingController(
    text: widget.statutory?.notes ?? '',
  );

  late String _cycle = widget.statutory?.cycle ?? 'monthly';
  late DateTime _issueDate = widget.statutory?.issueDate ?? DateTime.now();
  late String? _categoryId = widget.statutory?.categoryId;
  late bool _active = widget.statutory?.isActive ?? true;

  bool _submitting = false;
  String? _error;

  Statutory? get _editing => widget.statutory;
  bool get _isEdit => _editing != null;

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _remindDays.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickIssueDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _issueDate,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) setState(() => _issueDate = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });

    final remindDays = _remindDays.text.trim().isEmpty
        ? null
        : int.tryParse(_remindDays.text.trim());
    final notes = _notes.text.trim().isEmpty ? null : _notes.text.trim();

    try {
      final service = ref.read(financeServiceProvider);
      final editing = _editing;
      if (editing == null) {
        await service.createStatutory(
          name: _name.text.trim(),
          amount: double.parse(_amount.text.trim()),
          cycle: _cycle,
          issueDate: _issueDate,
          billCategoryId: _categoryId,
          remindDaysBefore: remindDays,
          isActive: _active,
          notes: notes,
        );
      } else {
        await service.updateStatutory(
          editing.id,
          name: _name.text.trim(),
          amount: double.parse(_amount.text.trim()),
          cycle: _cycle,
          issueDate: _issueDate,
          billCategoryId: _categoryId,
          remindDaysBefore: remindDays,
          isActive: _active,
          notes: notes,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(
        () => _error =
            e.errorFor('name') ??
            e.errorFor('amount') ??
            e.errorFor('issue_date') ??
            e.message,
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categories =
        ref.watch(billCategoriesProvider).valueOrNull ?? const <BillCategory>[];

    return SafeArea(
      child: Form(
        key: _formKey,
        child: CrmSheet(
          eyebrow: 'Statutory',
          title: _isEdit ? 'Edit obligation' : 'New obligation',
          children: [
            if (_error != null) ...[
              ErrorBanner(message: _error!),
              const SizedBox(height: Spacing.md),
            ],
            CrmField(
              label: 'Name',
              child: TextFormField(
                controller: _name,
                enabled: !_submitting,
                autofocus: !_isEdit,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  hintText: 'e.g. VAT, NSSF, Trading licence',
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Name is required' : null,
              ),
            ),
            const SizedBox(height: Spacing.md),
            CrmField(
              label: 'Amount',
              child: TextFormField(
                controller: _amount,
                enabled: !_submitting,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontFeatures: Type.figures,
                ),
                decoration: InputDecoration(
                  hintText: '0.00',
                  prefixText: '${Formatting.tenantCurrency} ',
                ),
                validator: (v) {
                  final parsed = double.tryParse(v?.trim() ?? '');
                  return (parsed == null || parsed < 0.01)
                      ? 'Enter a valid amount'
                      : null;
                },
              ),
            ),
            const SizedBox(height: Spacing.md),
            CrmField(
              label: 'Cycle',
              child: DropdownButtonFormField<String>(
                initialValue: _cycle,
                items: [
                  for (final (value, label) in _cycles)
                    DropdownMenuItem(value: value, child: Text(label)),
                ],
                onChanged: _submitting
                    ? null
                    : (v) => setState(() => _cycle = v!),
              ),
            ),
            const SizedBox(height: Spacing.md),
            CrmPickerField(
              label: 'Issue date',
              value: Formatting.date(_issueDate),
              onTap: _submitting ? null : _pickIssueDate,
            ),
            const SizedBox(height: Spacing.md),
            CrmField(
              label: 'Bill category (optional)',
              child: DropdownButtonFormField<String?>(
                initialValue: _categoryId,
                isExpanded: true,
                decoration: const InputDecoration(hintText: 'No category'),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('No category'),
                  ),
                  for (final (id, label) in _flattenBillCategories(categories))
                    DropdownMenuItem(
                      value: id,
                      child: Text(label, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: _submitting
                    ? null
                    : (v) => setState(() => _categoryId = v),
              ),
            ),
            const SizedBox(height: Spacing.md),
            CrmField(
              label: 'Remind days before (optional)',
              child: TextFormField(
                controller: _remindDays,
                enabled: !_submitting,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(hintText: 'e.g. 7'),
              ),
            ),
            const SizedBox(height: Spacing.md),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Active'),
              subtitle: const Text(
                'Inactive obligations stop generating new bills.',
              ),
              value: _active,
              onChanged: _submitting
                  ? null
                  : (v) => setState(() => _active = v),
            ),
            const SizedBox(height: Spacing.md),
            CrmField(
              label: 'Notes (optional)',
              child: TextFormField(
                controller: _notes,
                enabled: !_submitting,
                maxLines: 2,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Anything worth remembering',
                ),
              ),
            ),
            const SizedBox(height: Spacing.lg),
            PrimaryButton(
              label: _submitting
                  ? 'Saving…'
                  : _isEdit
                  ? 'Save changes'
                  : 'Create obligation',
              busy: _submitting,
              onPressed: _submitting ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}

/// Create or edit a plain bill. Unlike a statutory obligation, this creates
/// (or edits) exactly one row — no recurrence is generated from it.
class _BillFormSheet extends ConsumerStatefulWidget {
  const _BillFormSheet({this.bill});

  /// The bill being edited, or null to create one.
  final StaffBill? bill;

  @override
  ConsumerState<_BillFormSheet> createState() => _BillFormSheetState();
}

class _BillFormSheetState extends ConsumerState<_BillFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.bill?.name ?? '');
  late final _amount = TextEditingController(
    text: widget.bill == null ? '' : widget.bill!.amount.toStringAsFixed(2),
  );
  late final _remindDays = TextEditingController(
    text: widget.bill?.remindDaysBefore?.toString() ?? '',
  );
  late final _notes = TextEditingController(text: widget.bill?.notes ?? '');

  late String _cycle = widget.bill?.cycle ?? 'once';
  late DateTime? _issueDate = widget.bill?.issueDate;
  late DateTime _dueDate = widget.bill?.dueDate ?? DateTime.now();
  late String? _categoryId = widget.bill?.billCategoryId;
  late bool _active = widget.bill?.isActive ?? true;

  bool _submitting = false;
  String? _error;

  StaffBill? get _editing => widget.bill;
  bool get _isEdit => _editing != null;

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _remindDays.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDueDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) setState(() => _dueDate = picked);
  }

  Future<void> _pickIssueDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _issueDate ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) setState(() => _issueDate = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });

    final remindDays = _remindDays.text.trim().isEmpty
        ? null
        : int.tryParse(_remindDays.text.trim());
    final notes = _notes.text.trim().isEmpty ? null : _notes.text.trim();

    try {
      final service = ref.read(financeServiceProvider);
      final editing = _editing;
      if (editing == null) {
        await service.createBill(
          name: _name.text.trim(),
          amount: double.parse(_amount.text.trim()),
          cycle: _cycle,
          dueDate: _dueDate,
          billCategoryId: _categoryId,
          issueDate: _issueDate,
          remindDaysBefore: remindDays,
          isActive: _active,
          notes: notes,
        );
      } else {
        await service.updateBill(
          editing.id,
          name: _name.text.trim(),
          amount: double.parse(_amount.text.trim()),
          cycle: _cycle,
          dueDate: _dueDate,
          billCategoryId: _categoryId,
          issueDate: _issueDate,
          remindDaysBefore: remindDays,
          isActive: _active,
          notes: notes,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(
        () => _error =
            e.errorFor('name') ??
            e.errorFor('amount') ??
            e.errorFor('due_date') ??
            e.message,
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categories =
        ref.watch(billCategoriesProvider).valueOrNull ?? const <BillCategory>[];

    return SafeArea(
      child: Form(
        key: _formKey,
        child: CrmSheet(
          eyebrow: 'Statutory',
          title: _isEdit ? 'Edit bill' : 'New bill',
          children: [
            if (_error != null) ...[
              ErrorBanner(message: _error!),
              const SizedBox(height: Spacing.md),
            ],
            CrmField(
              label: 'Name',
              child: TextFormField(
                controller: _name,
                enabled: !_submitting,
                autofocus: !_isEdit,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  hintText: 'What the bill is for',
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Name is required' : null,
              ),
            ),
            const SizedBox(height: Spacing.md),
            CrmField(
              label: 'Amount',
              child: TextFormField(
                controller: _amount,
                enabled: !_submitting,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontFeatures: Type.figures,
                ),
                decoration: InputDecoration(
                  hintText: '0.00',
                  prefixText: '${Formatting.tenantCurrency} ',
                ),
                validator: (v) {
                  final parsed = double.tryParse(v?.trim() ?? '');
                  return (parsed == null || parsed < 0.01)
                      ? 'Enter a valid amount'
                      : null;
                },
              ),
            ),
            const SizedBox(height: Spacing.md),
            CrmField(
              label: 'Cycle',
              child: DropdownButtonFormField<String>(
                initialValue: _cycle,
                items: [
                  for (final (value, label) in _cycles)
                    DropdownMenuItem(value: value, child: Text(label)),
                ],
                onChanged: _submitting
                    ? null
                    : (v) => setState(() => _cycle = v!),
              ),
            ),
            const SizedBox(height: Spacing.md),
            CrmPickerField(
              label: 'Due date',
              value: Formatting.date(_dueDate),
              onTap: _submitting ? null : _pickDueDate,
            ),
            const SizedBox(height: Spacing.md),
            _OptionalDateField(
              label: 'Issue date (optional)',
              date: _issueDate,
              onTap: _submitting ? null : _pickIssueDate,
              onClear: _submitting
                  ? null
                  : () => setState(() => _issueDate = null),
            ),
            const SizedBox(height: Spacing.md),
            CrmField(
              label: 'Bill category (optional)',
              child: DropdownButtonFormField<String?>(
                initialValue: _categoryId,
                isExpanded: true,
                decoration: const InputDecoration(hintText: 'No category'),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('No category'),
                  ),
                  for (final (id, label) in _flattenBillCategories(categories))
                    DropdownMenuItem(
                      value: id,
                      child: Text(label, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: _submitting
                    ? null
                    : (v) => setState(() => _categoryId = v),
              ),
            ),
            const SizedBox(height: Spacing.md),
            CrmField(
              label: 'Remind days before (optional)',
              child: TextFormField(
                controller: _remindDays,
                enabled: !_submitting,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(hintText: 'e.g. 7'),
              ),
            ),
            const SizedBox(height: Spacing.md),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Active'),
              subtitle: const Text('Inactive bills drop off the paid list.'),
              value: _active,
              onChanged: _submitting
                  ? null
                  : (v) => setState(() => _active = v),
            ),
            const SizedBox(height: Spacing.md),
            CrmField(
              label: 'Notes (optional)',
              child: TextFormField(
                controller: _notes,
                enabled: !_submitting,
                maxLines: 2,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Anything worth remembering',
                ),
              ),
            ),
            const SizedBox(height: Spacing.lg),
            PrimaryButton(
              label: _submitting
                  ? 'Saving…'
                  : _isEdit
                  ? 'Save changes'
                  : 'Create bill',
              busy: _submitting,
              onPressed: _submitting ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}

/// Expense categories, same nested shape.
class ExpenseCategoriesScreen extends ConsumerWidget {
  const ExpenseCategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(expenseCategoriesProvider);
    final theme = Theme.of(context);
    final auth = ref.watch(sessionControllerProvider).session;
    final canCreate =
        auth?.can(FinancePermissions.expenseCategoriesCreate) ?? false;
    final canUpdate =
        auth?.can(FinancePermissions.expenseCategoriesUpdate) ?? false;
    final canDelete =
        auth?.can(FinancePermissions.expenseCategoriesDelete) ?? false;

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
                            title: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    category.name,
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      color: category.isActive
                                          ? null
                                          : theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                if (!category.isActive) ...[
                                  const SizedBox(width: Spacing.sm),
                                  const StatusChip('inactive', dense: true),
                                ],
                              ],
                            ),
                            subtitle: _MetaLine(
                              '${Formatting.integer(category.subCategories.length)} '
                              'sub-categor${category.subCategories.length == 1 ? 'y' : 'ies'}',
                            ),
                            trailing: (canUpdate || canDelete)
                                ? IconButton(
                                    icon: const Icon(Icons.more_vert),
                                    onPressed: () => _actions(
                                      context,
                                      ref,
                                      id: category.id,
                                      name: category.name,
                                      isActive: category.isActive,
                                      parentId: null,
                                      canUpdate: canUpdate,
                                      canDelete: canDelete,
                                    ),
                                  )
                                : null,
                            children: [
                              for (final sub in category.subCategories)
                                _CategoryTile(
                                  name: sub.name,
                                  nested: true,
                                  isActive: sub.isActive,
                                  onTap: (canUpdate || canDelete)
                                      ? () => _actions(
                                          context,
                                          ref,
                                          id: sub.id,
                                          name: sub.name,
                                          isActive: sub.isActive,
                                          parentId: category.id,
                                          canUpdate: canUpdate,
                                          canDelete: canDelete,
                                        )
                                      : null,
                                ),
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

  /// Edit / Delete for one row — [parentId] is null for a top-level category
  /// (which cannot itself have a parent) and set for a sub-category.
  Future<void> _actions(
    BuildContext context,
    WidgetRef ref, {
    required String id,
    required String name,
    required bool isActive,
    required String? parentId,
    required bool canUpdate,
    required bool canDelete,
  }) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: Spacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (canUpdate)
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Edit'),
                  onTap: () => Navigator.pop(sheetContext, 'edit'),
                ),
              if (canUpdate)
                ListTile(
                  leading: Icon(
                    isActive
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                  title: Text(isActive ? 'Mark inactive' : 'Mark active'),
                  onTap: () => Navigator.pop(sheetContext, 'toggle'),
                ),
              if (canDelete)
                ListTile(
                  leading: Icon(
                    Icons.delete_outline,
                    color: Theme.of(sheetContext).colorScheme.error,
                  ),
                  title: Text(
                    'Delete',
                    style: TextStyle(
                      color: Theme.of(sheetContext).colorScheme.error,
                    ),
                  ),
                  onTap: () => Navigator.pop(sheetContext, 'delete'),
                ),
            ],
          ),
        ),
      ),
    );
    if (!context.mounted || choice == null) return;

    switch (choice) {
      case 'edit':
        await _edit(
          context,
          ref,
          id: id,
          name: name,
          isActive: isActive,
          parentId: parentId,
        );
      case 'toggle':
        await _save(
          context,
          ref,
          id: id,
          name: name,
          isActive: !isActive,
          parentId: parentId,
        );
      case 'delete':
        await _delete(context, ref, id: id, name: name);
    }
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref, {
    required String id,
    required String name,
    required bool isActive,
    required String? parentId,
  }) async {
    final nameController = TextEditingController(text: name);
    final parents =
        ref.read(expenseCategoriesProvider).valueOrNull ??
        const <ExpenseCategory>[];
    var newParentId = parentId;
    var active = isActive;

    // A sub-category can move to another parent; a top-level category has
    // no parent field at all — it would have to become a sub-category of
    // itself otherwise.
    final saved = await _CategoryDialog.show(
      context,
      title: 'Edit category',
      name: nameController,
      parents: parentId == null
          ? const []
          : [for (final p in parents) (p.id, p.name)],
      initialParentId: parentId,
      onParentChanged: (v) => newParentId = v,
      initialActive: active,
      onActiveChanged: (v) => active = v,
      confirmLabel: 'Save changes',
    );
    if (saved != true || !context.mounted) return;
    await _save(
      context,
      ref,
      id: id,
      name: nameController.text.trim(),
      isActive: active,
      parentId: newParentId,
    );
  }

  Future<void> _save(
    BuildContext context,
    WidgetRef ref, {
    required String id,
    required String name,
    required bool isActive,
    required String? parentId,
  }) async {
    if (name.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(financeServiceProvider)
          .updateExpenseCategory(
            id,
            name: name,
            parentId: parentId,
            isActive: isActive,
          );
      ref.invalidate(expenseCategoriesProvider);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref, {
    required String id,
    required String name,
  }) async {
    final scheme = Theme.of(context).colorScheme;
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete "$name"?'),
        content: const Text(
          'Refused while any expense, or a sub-category, still points at it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: scheme.error),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final message = await ref
          .read(financeServiceProvider)
          .deleteExpenseCategory(id);
      ref.invalidate(expenseCategoriesProvider);
      messenger.showSnackBar(
        SnackBar(content: Text(message ?? '"$name" deleted.')),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

// ---------------------------------------------------------------------------
// Private building blocks (candidates for mobilling_ui)
// ---------------------------------------------------------------------------

/// A date field that can be left blank — a bill's optional issue date is the
/// only place in this file that needs one, so [CrmPickerField] (which always
/// shows a value) is not quite enough on its own.
class _OptionalDateField extends StatelessWidget {
  const _OptionalDateField({
    required this.label,
    required this.date,
    required this.onTap,
    required this.onClear,
  });

  final String label;
  final DateTime? date;
  final VoidCallback? onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return CrmField(
      label: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.md),
        onTap: onTap,
        child: InputDecorator(
          decoration: InputDecoration(
            suffixIcon: date == null
                ? const Icon(Icons.calendar_today_outlined, size: 18)
                : IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    tooltip: 'Clear',
                    onPressed: onClear,
                  ),
          ),
          child: Text(
            date == null ? 'Not set' : Formatting.date(date),
            style: theme.textTheme.bodyLarge?.copyWith(
              color: date == null
                  ? scheme.onSurfaceVariant.withValues(alpha: 0.7)
                  : scheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

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
  const _CategoryTile({
    required this.name,
    this.detail,
    this.nested = false,
    this.isActive = true,
    this.onTap,
  });

  final String name;
  final String? detail;
  final bool nested;
  final bool isActive;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      dense: nested,
      contentPadding: nested
          ? const EdgeInsets.only(left: Spacing.xl, right: Spacing.md)
          : null,
      onTap: onTap,
      title: Text(
        name,
        style:
            (nested ? theme.textTheme.bodyMedium : theme.textTheme.titleSmall)
                ?.copyWith(
                  color: isActive ? null : theme.colorScheme.onSurfaceVariant,
                ),
      ),
      subtitle: detail == null ? null : _MetaLine(detail!),
      trailing: !isActive ? const StatusChip('inactive', dense: true) : null,
    );
  }
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
    String? initialParentId,
    // Null keeps the dialog exactly as the create flow has always looked —
    // the active toggle only appears when a caller actually needs it.
    bool? initialActive,
    ValueChanged<bool>? onActiveChanged,
    // Same idea for a bill category's optional default cycle: only the edit
    // flow passes this, so the create dialog is unchanged.
    String? initialBillingCycle,
    ValueChanged<String?>? onBillingCycleChanged,
    String confirmLabel = 'Create category',
  }) {
    final scheme = Theme.of(context).colorScheme;
    String? parentId = initialParentId;
    var active = initialActive ?? true;
    String? billingCycle = initialBillingCycle;

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
              if (onActiveChanged != null) ...[
                const SizedBox(height: Spacing.md),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active'),
                  subtitle: const Text(
                    'Inactive categories stay on old expenses',
                  ),
                  value: active,
                  onChanged: (v) {
                    setDialogState(() => active = v);
                    onActiveChanged(v);
                  },
                ),
              ],
              if (onBillingCycleChanged != null) ...[
                const SizedBox(height: Spacing.md),
                const FieldLabel('Default cycle (optional)'),
                const SizedBox(height: Spacing.sm),
                DropdownButtonFormField<String?>(
                  initialValue: billingCycle,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    helperText: 'What a new bill under it defaults to',
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('None')),
                    for (final (value, label) in _cycles)
                      DropdownMenuItem(value: value, child: Text(label)),
                  ],
                  onChanged: (v) {
                    setDialogState(() => billingCycle = v);
                    onBillingCycleChanged(v);
                  },
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(confirmLabel),
            ),
          ],
        ),
      ),
    );
  }
}
