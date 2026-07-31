import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';
import '../common/paged_list.dart';
import 'crm_providers.dart';
import 'crm_ui.dart';

/// Walk-in customers served at the counter, plus this week's progress against
/// target. Recording someone served is a counter-staff action, so the form is
/// deliberately short: name, what they came for, optional phone.
class ServedCustomersScreen extends ConsumerStatefulWidget {
  const ServedCustomersScreen({super.key});

  @override
  ConsumerState<ServedCustomersScreen> createState() =>
      _ServedCustomersScreenState();
}

class _ServedCustomersScreenState
    extends ConsumerState<ServedCustomersScreen> {
  final _listKey = GlobalKey<PagedListViewState>();

  @override
  Widget build(BuildContext context) {
    final summary = ref.watch(servedWeeklySummaryProvider);
    final canCreate = ref.watch(sessionControllerProvider).session?.can(
              CrmPermissions.servedCreate,
            ) ??
        false;

    return Scaffold(
      appBar: AppBar(title: const Text('Served customers')),
      floatingActionButton: !canCreate
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _recordCustomer(context),
              icon: const Icon(Icons.person_add_alt_1_outlined),
              label: const Text('Record'),
            ),
      body: Column(
        children: [
          summary.maybeWhen(
            data: (s) => Padding(
              padding: const EdgeInsets.fromLTRB(
                  Spacing.md, Spacing.sm, Spacing.md, 0),
              child: Row(
                children: [
                  Expanded(
                    child: StatTile(
                      label: 'New this week',
                      value: s.newCustomersTarget == null
                          ? '${s.newCustomersAchieved}'
                          : '${s.newCustomersAchieved}/${s.newCustomersTarget}',
                      icon: Icons.how_to_reg_outlined,
                      emphasis: s.newCustomersTarget != null &&
                              s.newCustomersAchieved >= s.newCustomersTarget!
                          ? context.statusColors.settled
                          : null,
                    ),
                  ),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: StatTile(
                      label: 'Calls this week',
                      value: s.callsTarget == null
                          ? '${s.callsAchieved}'
                          : '${s.callsAchieved}/${s.callsTarget}',
                      icon: Icons.call_outlined,
                    ),
                  ),
                ],
              ),
            ),
            orElse: () => const SizedBox.shrink(),
          ),
          Expanded(
            child: PagedListView(
              key: _listKey,
              padding: const EdgeInsets.all(Spacing.md),
              fetch: (page) =>
                  ref.read(crmServiceProvider).servedCustomers(page: page),
              itemBuilder: (context, customer) => _CustomerCard(
                customer: customer,
                onFeedbackLogged: () => _listKey.currentState?.reload(),
              ),
              emptyIcon: Icons.how_to_reg_outlined,
              emptyTitle: 'Nobody logged yet',
              emptyMessage: 'Walk-in customers you serve appear here.',
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _recordCustomer(BuildContext context) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
      builder: (_) => const _RecordServedSheet(),
    );
    if (saved == true) {
      _listKey.currentState?.reload();
      ref.invalidate(servedWeeklySummaryProvider);
    }
  }
}

class _CustomerCard extends ConsumerWidget {
  const _CustomerCard({required this.customer, required this.onFeedbackLogged});

  final ServedCustomer customer;
  final VoidCallback onFeedbackLogged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final lastFeedback =
        customer.feedbacks.isEmpty ? null : customer.feedbacks.first;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(customer.name,
                      style: theme.textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                if (customer.phone != null)
                  ContactRow(phone: customer.phone, compact: true),
              ],
            ),
            Text(
              [
                if (customer.servedDate != null)
                  Formatting.date(customer.servedDate),
                if (customer.createdByName != null) customer.createdByName!,
              ].join(' · '),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            if (customer.services.isNotEmpty) ...[
              const SizedBox(height: Spacing.xs),
              Wrap(
                spacing: Spacing.xs,
                runSpacing: Spacing.xs,
                children: [
                  for (final service in customer.services)
                    Chip(
                      label: Text(service.name,
                          style: theme.textTheme.labelSmall),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize:
                          MaterialTapTargetSize.shrinkWrap,
                    ),
                ],
              ),
            ],
            if (lastFeedback != null) ...[
              const SizedBox(height: Spacing.xs),
              Row(
                children: [
                  if (lastFeedback.rating != null)
                    RatingStars(rating: lastFeedback.rating),
                  if (lastFeedback.outcome != null)
                    Text(lastFeedback.outcome!,
                        style: theme.textTheme.bodySmall),
                ],
              ),
            ] else ...[
              const SizedBox(height: Spacing.xs),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.rate_review_outlined, size: 16),
                  label: const Text('Log follow-up call'),
                  onPressed: () async {
                    final saved = await showModalBottomSheet<bool>(
                      context: context,
                      isScrollControlled: true,
                      shape: const RoundedRectangleBorder(
                          borderRadius: Radii.sheet),
                      builder: (_) => _FeedbackSheet(customer: customer),
                    );
                    if (saved == true) onFeedbackLogged();
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RecordServedSheet extends ConsumerStatefulWidget {
  const _RecordServedSheet();

  @override
  ConsumerState<_RecordServedSheet> createState() =>
      _RecordServedSheetState();
}

class _RecordServedSheetState extends ConsumerState<_RecordServedSheet> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _notes = TextEditingController();
  final Set<String> _serviceIds = {};

  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Enter the customer name.');
      return;
    }
    if (_serviceIds.isEmpty) {
      setState(() => _error = 'Pick at least one service.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await ref.read(crmServiceProvider).recordServedCustomer(
            name: _name.text.trim(),
            serviceIds: _serviceIds.toList(),
            phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      showCrmMessage(context, 'Customer recorded.');
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
    final services = ref.watch(servedServicesProvider);

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
            Text('Record a customer',
                style: theme.textTheme.titleLarge,
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
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration:
                  const InputDecoration(labelText: 'Phone (optional)'),
            ),
            const SizedBox(height: Spacing.md),
            Text('Services', style: theme.textTheme.labelMedium),
            services.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(Spacing.md),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, stack) => Text('Could not load services.',
                  style: theme.textTheme.bodySmall),
              data: (items) => Wrap(
                spacing: Spacing.xs,
                runSpacing: Spacing.xs,
                children: [
                  for (final service in items.where((s) => s.isActive))
                    FilterChip(
                      label: Text(service.name),
                      selected: _serviceIds.contains(service.id),
                      onSelected: _submitting
                          ? null
                          : (on) => setState(() => on
                              ? _serviceIds.add(service.id)
                              : _serviceIds.remove(service.id)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: Spacing.md),
            TextField(
              controller: _notes,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
            ),
            const SizedBox(height: Spacing.lg),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeedbackSheet extends ConsumerStatefulWidget {
  const _FeedbackSheet({required this.customer});

  final ServedCustomer customer;

  @override
  ConsumerState<_FeedbackSheet> createState() => _FeedbackSheetState();
}

class _FeedbackSheetState extends ConsumerState<_FeedbackSheet> {
  final _feedback = TextEditingController();
  final _challenges = TextEditingController();

  String _outcome = 'reached';
  int? _rating;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _feedback.dispose();
    _challenges.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(crmServiceProvider).recordServedFeedback(
            widget.customer.id,
            outcome: _outcome,
            rating: _rating,
            feedback:
                _feedback.text.trim().isEmpty ? null : _feedback.text.trim(),
            challenges: _challenges.text.trim().isEmpty
                ? null
                : _challenges.text.trim(),
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      showCrmMessage(context, 'Feedback saved.');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reached = _outcome == 'reached';

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
            Text('Follow-up call',
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center),
            Text(widget.customer.name,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center),
            const SizedBox(height: Spacing.md),
            if (_error != null) ...[
              ErrorBanner(message: _error!),
              const SizedBox(height: Spacing.sm),
            ],
            DropdownButtonFormField<String>(
              initialValue: _outcome,
              decoration: const InputDecoration(labelText: 'Outcome'),
              items: const [
                DropdownMenuItem(
                    value: 'reached', child: Text('Reached and spoke')),
                DropdownMenuItem(value: 'no_answer', child: Text('No answer')),
                DropdownMenuItem(
                    value: 'wrong_number', child: Text('Wrong number')),
              ],
              onChanged:
                  _submitting ? null : (v) => setState(() => _outcome = v!),
            ),
            if (reached) ...[
              const SizedBox(height: Spacing.md),
              Text('Rating', style: theme.textTheme.labelMedium),
              Center(
                child: RatingStars(
                  rating: _rating,
                  onChanged: (v) => setState(() => _rating = v),
                ),
              ),
              const SizedBox(height: Spacing.sm),
              TextField(
                controller: _feedback,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Feedback'),
              ),
              const SizedBox(height: Spacing.md),
              TextField(
                controller: _challenges,
                maxLines: 2,
                decoration: const InputDecoration(
                    labelText: 'Challenges they mentioned'),
              ),
            ],
            const SizedBox(height: Spacing.lg),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
