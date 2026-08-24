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
    final status = context.statusColors;
    final canLog =
        ref
            .watch(sessionControllerProvider)
            .session
            ?.can(CrmPermissions.followupLog) ??
        false;

    return Scaffold(
      appBar: const ShellTopBar(eyebrow: 'Billing', title: 'Follow-ups'),
      body: Column(
        children: [
          // Counters come from the dashboard endpoint; the list below is the
          // filtered full set, so both stay accurate independently.
          dashboard.maybeWhen(
            data: (d) => Padding(
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
                      label: 'Due today',
                      value: Formatting.integer(d.stats.dueToday),
                    ),
                    StatRailItem(
                      label: 'Overdue',
                      value: Formatting.integer(d.stats.overdue),
                      emphasis: d.stats.overdue > 0 ? status.overdue : null,
                    ),
                    StatRailItem(
                      label: 'Active',
                      value: Formatting.integer(d.stats.totalActive),
                    ),
                  ],
                ),
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
                      message:
                          'Invoices scheduled for a collection call appear here.',
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
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(
                          Spacing.md,
                          Spacing.sm,
                          Spacing.md,
                          Spacing.xl,
                        ),
                        children: [
                          CrmCardList(
                            children: [
                              for (final followup in items)
                                _FollowupRow(
                                  followup: followup,
                                  canLog: canLog,
                                  onLogged: () {
                                    ref.invalidate(followupDashboardProvider);
                                    ref.invalidate(followupsProvider(_status));
                                  },
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One invoice being chased: the balance as the trailing figure, the
/// reference and call history in the metadata line, the promise (if any)
/// in gold, and the call-and-log actions on the last row.
class _FollowupRow extends ConsumerWidget {
  const _FollowupRow({
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
    final status = context.statusColors;
    final canAct = canLog && followup.isOpenWork;
    final hasPhone = followup.clientPhone != null;

    final meta = [
      if (followup.documentNumber != null) followup.documentNumber!,
      if (followup.callDate != null)
        'call ${Formatting.date(followup.callDate)}',
      if (followup.callCount != null && followup.callCount! > 0)
        '${Formatting.integer(followup.callCount)} '
            '${followup.callCount == 1 ? 'call' : 'calls'}',
    ].join(' · ');

    return Padding(
      padding: EdgeInsets.fromLTRB(
        Spacing.md,
        Spacing.md,
        Spacing.md,
        hasPhone || canAct ? Spacing.xs : Spacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  followup.clientName ?? followup.documentNumber ?? 'Follow-up',
                  style: theme.textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: Spacing.sm),
              Money(followup.invoiceBalance),
            ],
          ),
          const SizedBox(height: Spacing.xs),
          CrmStatusLine(status: followup.status, meta: meta),
          if (followup.promiseDate != null) ...[
            const SizedBox(height: Spacing.xs),
            Row(
              children: [
                Text(
                  'Promised',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: status.attention,
                  ),
                ),
                const SizedBox(width: Spacing.xs),
                Money(
                  followup.promiseAmount ?? 0,
                  scale: MoneyScale.dense,
                  color: status.attention,
                ),
                const SizedBox(width: Spacing.xs),
                Text(
                  'by ${Formatting.date(followup.promiseDate)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: status.attention,
                  ),
                ),
              ],
            ),
          ],
          if (followup.outcome != null) ...[
            const SizedBox(height: Spacing.xs),
            Text(
              'Last outcome: ${followup.outcome}',
              style: theme.textTheme.bodySmall,
            ),
          ],
          if (hasPhone || canAct) ...[
            const SizedBox(height: Spacing.xs),
            Row(
              children: [
                ContactRow(phone: followup.clientPhone, compact: true),
                const Spacer(),
                if (canAct)
                  TextButton.icon(
                    icon: const Icon(Icons.phone_in_talk_outlined, size: 18),
                    label: const Text('Log call'),
                    onPressed: () => _showLogSheet(context, ref),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showLogSheet(BuildContext context, WidgetRef ref) async {
    final logged = await showCrmSheet<bool>(
      context: context,
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
      final result = await ref
          .read(crmServiceProvider)
          .logFollowupCall(
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
        result.escalated ? '${result.message} — escalated.' : result.message,
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
    return CrmSheet(
      eyebrow: widget.followup.clientName ?? widget.followup.documentNumber,
      title: 'Log call',
      children: [
        if (_error != null) ...[
          ErrorBanner(message: _error!),
          const SizedBox(height: Spacing.md),
        ],
        CrmField(
          label: 'Outcome',
          child: DropdownButtonFormField<String>(
            initialValue: _outcome,
            items: [
              for (final (value, label) in _outcomes)
                DropdownMenuItem(value: value, child: Text(label)),
            ],
            onChanged: _submitting
                ? null
                : (v) => setState(() => _outcome = v!),
          ),
        ),
        if (_isPromise) ...[
          const SizedBox(height: Spacing.md),
          CrmField(
            label: 'Amount promised',
            child: TextField(
              controller: _promiseAmount,
              enabled: !_submitting,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                prefixText: '${Formatting.tenantCurrency} ',
                hintText: '0.00',
              ),
            ),
          ),
          const SizedBox(height: Spacing.md),
          CrmPickerField(
            label: 'Promised by',
            value: _promiseDate == null
                ? 'Choose a date'
                : Formatting.date(_promiseDate),
            placeholder: _promiseDate == null,
            onTap: _submitting ? null : () => _pick(true),
          ),
        ],
        const SizedBox(height: Spacing.md),
        CrmPickerField(
          label: 'Next follow-up (optional)',
          value: _nextFollowup == null
              ? 'Not scheduled'
              : Formatting.date(_nextFollowup),
          placeholder: _nextFollowup == null,
          icon: Icons.event_outlined,
          onTap: _submitting ? null : () => _pick(false),
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Notes',
          child: TextField(
            controller: _notes,
            enabled: !_submitting,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'What was said, and what happens next',
            ),
          ),
        ),
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
