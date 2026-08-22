import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';
import 'crm_providers.dart';
import 'crm_ui.dart';

/// Collection follow-up calls: who to ring, and what came of it.
///
/// The write action that matters is "log call" — an outcome plus, when the
/// client commits, a promise date and amount. The server tracks broken
/// promises and may escalate, which it reports back on the log response.
class FollowupsScreen extends ConsumerStatefulWidget {
  const FollowupsScreen({super.key});

  @override
  ConsumerState<FollowupsScreen> createState() => _FollowupsScreenState();
}

class _FollowupsScreenState extends ConsumerState<FollowupsScreen> {
  String? _status;

  static const _filters = <(String?, String)>[
    // `Followup.status` values; `promised` is an outcome, not a status.
    (null, 'All'),
    ('pending', 'Pending'),
    ('open', 'Open'),
    ('broken', 'Broken promise'),
    ('fulfilled', 'Fulfilled'),
    ('escalated', 'Escalated'),
    ('cancelled', 'Cancelled'),
  ];

  @override
  Widget build(BuildContext context) {
    final dashboard = ref.watch(followupDashboardProvider);
    final list = ref.watch(followupsProvider(_status));
    final canLog = ref.watch(sessionControllerProvider).session?.can(
              CrmPermissions.followupLog,
            ) ??
        false;

    return Scaffold(
      appBar: AppBar(title: const Text('Follow-ups')),
      body: Column(
        children: [
          // Counters come from the dashboard endpoint; the list below is the
          // filtered full set, so both stay accurate independently.
          dashboard.maybeWhen(
            data: (d) => Padding(
              padding: const EdgeInsets.fromLTRB(
                  Spacing.md, Spacing.sm, Spacing.md, 0),
              child: Row(
                children: [
                  Expanded(
                    child: StatTile(
                      label: 'Due today',
                      value: '${d.stats.dueToday}',
                      icon: Icons.today_outlined,
                    ),
                  ),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: StatTile(
                      label: 'Overdue',
                      value: '${d.stats.overdue}',
                      emphasis: d.stats.overdue > 0
                          ? context.statusColors.overdue
                          : null,
                      icon: Icons.warning_amber_rounded,
                    ),
                  ),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: StatTile(
                      label: 'Active',
                      value: '${d.stats.totalActive}',
                    ),
                  ),
                ],
              ),
            ),
            orElse: () => const SizedBox.shrink(),
          ),
          FilterStrip(
            options: _filters,
            selected: _status,
            onSelect: (v) => setState(() => _status = v),
          ),
          Expanded(
            child: CrmAsyncView(
              value: list,
              errorTitle: 'Could not load follow-ups',
              onRetry: () => ref.invalidate(followupsProvider(_status)),
              builder: (items) => items.isEmpty
                  ? const StateMessage(
                      icon: Icons.phone_in_talk_outlined,
                      title: 'No follow-ups here',
                    )
                  : RefreshIndicator(
                      onRefresh: () async {
                        // Both the counters and the list need re-reading; the
                        // future is awaited so the spinner lasts until data
                        // actually lands.
                        ref.invalidate(followupDashboardProvider);
                        ref.invalidate(followupsProvider(_status));
                        await ref.read(followupsProvider(_status).future);
                      },
                      child: ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(Spacing.md),
                        itemCount: items.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: Spacing.sm),
                        itemBuilder: (context, index) => _FollowupCard(
                          followup: items[index],
                          canLog: canLog,
                          onLogged: () {
                            ref.invalidate(followupDashboardProvider);
                            ref.invalidate(followupsProvider(_status));
                          },
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FollowupCard extends ConsumerWidget {
  const _FollowupCard({
    required this.followup,
    required this.canLog,
    required this.onLogged,
  });

  final FollowupEntry followup;
  final bool canLog;
  final VoidCallback onLogged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                      followup.clientName ??
                          followup.documentNumber ??
                          'Follow-up',
                      style: theme.textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                StatusChip(followup.status, dense: true),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              [
                if (followup.documentNumber != null) followup.documentNumber!,
                'balance ${Formatting.amount(followup.invoiceBalance)}',
                if (followup.callDate != null)
                  'call ${Formatting.date(followup.callDate)}',
                if (followup.callCount != null && followup.callCount! > 0)
                  '${followup.callCount} call${followup.callCount == 1 ? '' : 's'}',
              ].join(' · '),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            if (followup.promiseDate != null) ...[
              const SizedBox(height: Spacing.xs),
              Text(
                'Promised ${Formatting.amount(followup.promiseAmount ?? 0)} by ${Formatting.date(followup.promiseDate)}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: context.statusColors.attention),
              ),
            ],
            if (followup.outcome != null) ...[
              const SizedBox(height: Spacing.xs),
              Text('Last: ${followup.outcome}',
                  style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: Spacing.sm),
            Row(
              children: [
                if (followup.clientPhone != null)
                  ContactRow(phone: followup.clientPhone, compact: true),
                const Spacer(),
                if (canLog && followup.isOpenWork)
                  FilledButton.tonal(
                    onPressed: () => _showLogSheet(context, ref),
                    child: const Text('Log call'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showLogSheet(BuildContext context, WidgetRef ref) async {
    final logged = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
      builder: (_) => _LogCallSheet(followup: followup),
    );
    if (logged == true) onLogged();
  }
}

class _LogCallSheet extends ConsumerStatefulWidget {
  const _LogCallSheet({required this.followup});

  final FollowupEntry followup;

  @override
  ConsumerState<_LogCallSheet> createState() => _LogCallSheetState();
}

class _LogCallSheetState extends ConsumerState<_LogCallSheet> {
  final _notes = TextEditingController();
  final _promiseAmount = TextEditingController();

  /// Exactly what `FollowupController::logCall` validates.
  static const _outcomes = FollowupOutcomes.values;

  String _outcome = 'promised';
  DateTime? _promiseDate;
  DateTime? _nextFollowup;
  bool _submitting = false;
  String? _error;

  bool get _isPromise => FollowupOutcomes.needsPromiseDate(_outcome);
  bool get _needsAmount => FollowupOutcomes.needsAmount(_outcome);

  @override
  void initState() {
    super.initState();
    _promiseAmount.text = widget.followup.invoiceBalance.toStringAsFixed(2);
  }

  @override
  void dispose() {
    _notes.dispose();
    _promiseAmount.dispose();
    super.dispose();
  }

  Future<void> _pick(bool promise) async {
    final now = DateTime.now();
    // Both dates must be strictly after today server-side.
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final picked = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 3)),
      firstDate: tomorrow,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() => promise ? _promiseDate = picked : _nextFollowup = picked);
  }

  Future<void> _submit() async {
    if (_isPromise && _promiseDate == null) {
      setState(() => _error = 'Pick the date they promised to pay.');
      return;
    }
    if (_notes.text.trim().isEmpty) {
      setState(() => _error = 'Add a note about the call — it is required.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final result = await ref.read(crmServiceProvider).logFollowupCall(
            widget.followup.id,
            outcome: _outcome,
            notes: _notes.text.trim(),
            promiseDate: _isPromise ? _promiseDate : null,
            promiseAmount: _needsAmount
                ? double.tryParse(_promiseAmount.text.trim())
                : null,
            nextFollowup: _nextFollowup,
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      showCrmMessage(
        context,
        result.escalated
            ? '${result.message} — escalated.'
            : result.message,
      );
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
            Text('Log call',
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center),
            Text(
              widget.followup.clientName ?? '',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Spacing.md),
            if (_error != null) ...[
              ErrorBanner(message: _error!),
              const SizedBox(height: Spacing.sm),
            ],
            DropdownButtonFormField<String>(
              initialValue: _outcome,
              decoration: const InputDecoration(labelText: 'Outcome'),
              items: [
                for (final (value, label) in _outcomes)
                  DropdownMenuItem(value: value, child: Text(label)),
              ],
              onChanged: _submitting
                  ? null
                  : (v) => setState(() => _outcome = v!),
            ),
            if (_isPromise) ...[
              const SizedBox(height: Spacing.md),
              TextField(
                controller: _promiseAmount,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Amount promised',
                  prefixText: '${Formatting.tenantCurrency} ',
                ),
              ),
              const SizedBox(height: Spacing.md),
              InkWell(
                onTap: _submitting ? null : () => _pick(true),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Promised by',
                    suffixIcon: Icon(Icons.calendar_today_outlined, size: 18),
                  ),
                  child: Text(_promiseDate == null
                      ? 'Choose a date'
                      : Formatting.date(_promiseDate)),
                ),
              ),
            ],
            const SizedBox(height: Spacing.md),
            InkWell(
              onTap: _submitting ? null : () => _pick(false),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Next follow-up (optional)',
                  suffixIcon: Icon(Icons.event_outlined, size: 18),
                ),
                child: Text(_nextFollowup == null
                    ? 'Not scheduled'
                    : Formatting.date(_nextFollowup)),
              ),
            ),
            const SizedBox(height: Spacing.md),
            TextField(
              controller: _notes,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Notes'),
            ),
            const SizedBox(height: Spacing.lg),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save call'),
            ),
          ],
        ),
      ),
    );
  }
}
