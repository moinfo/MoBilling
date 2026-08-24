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

class _ServedCustomersScreenState extends ConsumerState<ServedCustomersScreen> {
  final _listKey = GlobalKey<PagedListViewState>();

  @override
  Widget build(BuildContext context) {
    final summary = ref.watch(servedWeeklySummaryProvider);
    final status = context.statusColors;
    final canCreate =
        ref
            .watch(sessionControllerProvider)
            .session
            ?.can(CrmPermissions.servedCreate) ??
        false;

    return Scaffold(
      appBar: ShellTopBar(
        eyebrow: 'Engagement',
        title: 'Served customers',
        trailing: canCreate
            ? InkActionButton(
                icon: Icons.person_add_alt_1_outlined,
                tooltip: 'Record a customer',
                onPressed: () => _recordCustomer(context),
              )
            : null,
      ),
      body: Column(
        children: [
          summary.maybeWhen(
            data: (s) {
              final metTarget =
                  s.newCustomersTarget != null &&
                  s.newCustomersAchieved >= s.newCustomersTarget!;
              return Padding(
                padding: const EdgeInsets.fromLTRB(
                  Spacing.md,
                  Spacing.md,
                  Spacing.md,
                  0,
                ),
                child: Reveal(
                  child: StatRail(
                    items: [
                      StatRailItem(
                        label: 'New this week',
                        value: s.newCustomersTarget == null
                            ? Formatting.integer(s.newCustomersAchieved)
                            : '${Formatting.integer(s.newCustomersAchieved)}'
                                  '/${Formatting.integer(s.newCustomersTarget)}',
                        emphasis: metTarget ? status.settled : null,
                      ),
                      StatRailItem(
                        label: 'Calls this week',
                        value: s.callsTarget == null
                            ? Formatting.integer(s.callsAchieved)
                            : '${Formatting.integer(s.callsAchieved)}'
                                  '/${Formatting.integer(s.callsTarget)}',
                      ),
                    ],
                  ),
                ),
              );
            },
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
    final saved = await showCrmSheet<bool>(
      context: context,
      builder: (_) => const _RecordServedSheet(),
    );
    if (saved == true) {
      _listKey.currentState?.reload();
      ref.invalidate(servedWeeklySummaryProvider);
    }
  }
}

/// One customer served: who and when, what they came for, and — once a
/// follow-up call has been made — how it went.
class _CustomerCard extends ConsumerWidget {
  const _CustomerCard({required this.customer, required this.onFeedbackLogged});

  final ServedCustomer customer;
  final VoidCallback onFeedbackLogged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final lastFeedback = customer.feedbacks.isEmpty
        ? null
        : customer.feedbacks.first;
    final hasPhone = customer.phone != null;
    final needsCall = lastFeedback == null;

    return Card(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          Spacing.md,
          Spacing.md,
          Spacing.md,
          hasPhone || needsCall ? Spacing.xs : Spacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    customer.name,
                    style: theme.textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (lastFeedback?.rating != null) ...[
                  const SizedBox(width: Spacing.sm),
                  RatingStars(rating: lastFeedback!.rating, compact: true),
                ],
              ],
            ),
            const SizedBox(height: Spacing.xs),
            CrmMetaLine(
              [
                if (customer.servedDate != null)
                  Formatting.date(customer.servedDate),
                if (customer.createdByName != null)
                  'by ${customer.createdByName}',
              ].join(' · '),
            ),
            if (customer.services.isNotEmpty) ...[
              const SizedBox(height: Spacing.sm),
              Wrap(
                spacing: Spacing.xs,
                runSpacing: Spacing.xs,
                children: [
                  for (final service in customer.services)
                    Chip(
                      label: Text(service.name.toUpperCase()),
                      labelStyle: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                      backgroundColor: scheme.surfaceContainerHighest,
                      side: BorderSide.none,
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                ],
              ),
            ],
            if (lastFeedback?.outcome != null) ...[
              const SizedBox(height: Spacing.sm),
              Text(
                'Last call: ${lastFeedback!.outcome}',
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (hasPhone || needsCall) ...[
              const SizedBox(height: Spacing.xs),
              Row(
                children: [
                  ContactRow(phone: customer.phone, compact: true),
                  const Spacer(),
                  if (needsCall)
                    TextButton.icon(
                      icon: const Icon(Icons.phone_in_talk_outlined, size: 18),
                      label: const Text('Log follow-up call'),
                      onPressed: () async {
                        final saved = await showCrmSheet<bool>(
                          context: context,
                          builder: (_) => _FeedbackSheet(customer: customer),
                        );
                        if (saved == true) onFeedbackLogged();
                      },
                    ),
                ],
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
  ConsumerState<_RecordServedSheet> createState() => _RecordServedSheetState();
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

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await ref
          .read(crmServiceProvider)
          .recordServedCustomer(
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

    return CrmSheet(
      eyebrow: 'Served customers',
      title: 'Record a customer',
      children: [
        if (_error != null) ...[
          ErrorBanner(message: _error!),
          const SizedBox(height: Spacing.md),
        ],
        CrmField(
          label: 'Name',
          child: TextField(
            controller: _name,
            enabled: !_submitting,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(hintText: 'Customer’s name'),
          ),
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Phone (optional)',
          child: TextField(
            controller: _phone,
            enabled: !_submitting,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(hintText: '0712 345 678'),
          ),
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Services',
          child: services.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(Spacing.md),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, stack) => Text(
              'Could not load services. Close this sheet and try again.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            data: (items) => Wrap(
              spacing: Spacing.sm,
              runSpacing: Spacing.sm,
              children: [
                for (final service in items.where((s) => s.isActive))
                  FilterChip(
                    label: Text(service.name.toUpperCase()),
                    selected: _serviceIds.contains(service.id),
                    showCheckmark: false,
                    onSelected: _submitting
                        ? null
                        : (on) => setState(
                            () => on
                                ? _serviceIds.add(service.id)
                                : _serviceIds.remove(service.id),
                          ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Notes (optional)',
          child: TextField(
            controller: _notes,
            enabled: !_submitting,
            maxLines: 2,
            decoration: const InputDecoration(
              hintText: 'Anything worth remembering',
            ),
          ),
        ),
        const SizedBox(height: Spacing.lg),
        PrimaryButton(
          label: _submitting ? 'Saving…' : 'Save customer',
          busy: _submitting,
          onPressed: _submitting ? null : _submit,
        ),
      ],
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

  String _outcome = 'satisfied';
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
      await ref
          .read(crmServiceProvider)
          .recordServedFeedback(
            widget.customer.id,
            outcome: _outcome,
            rating: _rating,
            feedback: _feedback.text.trim().isEmpty
                ? null
                : _feedback.text.trim(),
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
    final reached = _outcome == 'reached';

    return CrmSheet(
      eyebrow: widget.customer.name,
      title: 'Follow-up call',
      children: [
        if (_error != null) ...[
          ErrorBanner(message: _error!),
          const SizedBox(height: Spacing.md),
        ],
        CrmField(
          label: 'Outcome',
          child: DropdownButtonFormField<String>(
            initialValue: _outcome,
            // What `storeFeedback` validates.
            items: [
              for (final (value, label) in ServedFeedbackOutcomes.values)
                DropdownMenuItem(value: value, child: Text(label)),
            ],
            onChanged: _submitting
                ? null
                : (v) => setState(() => _outcome = v!),
          ),
        ),
        if (reached) ...[
          const SizedBox(height: Spacing.md),
          CrmField(
            label: 'Rating',
            child: Align(
              alignment: Alignment.centerLeft,
              child: RatingStars(
                rating: _rating,
                onChanged: (v) => setState(() => _rating = v),
              ),
            ),
          ),
          const SizedBox(height: Spacing.md),
          CrmField(
            label: 'Feedback',
            child: TextField(
              controller: _feedback,
              enabled: !_submitting,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'How was the service they received?',
              ),
            ),
          ),
          const SizedBox(height: Spacing.md),
          CrmField(
            label: 'Challenges they mentioned',
            child: TextField(
              controller: _challenges,
              enabled: !_submitting,
              maxLines: 2,
              decoration: const InputDecoration(
                hintText: 'Anything that got in their way',
              ),
            ),
          ),
        ],
        const SizedBox(height: Spacing.lg),
        PrimaryButton(
          label: _submitting ? 'Saving…' : 'Save call',
          busy: _submitting,
          onPressed: _submitting ? null : _submit,
        ),
      ],
    );
  }
}
