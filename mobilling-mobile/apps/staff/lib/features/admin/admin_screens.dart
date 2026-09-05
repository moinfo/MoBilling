import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_auth/mobilling_auth.dart';
import 'package:mobilling_ui/mobilling_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/theme_mode.dart';
import '../../providers.dart';
import '../common/paged_list.dart';
import '../common/share_pdf.dart';
import '../crm/crm_ui.dart'
    show
        CrmAsyncView,
        CrmCardList,
        CrmDetailRow,
        CrmField,
        CrmMetaLine,
        CrmPickerField,
        CrmSheet,
        FilterStrip,
        CrmStatusLine,
        showCrmSheet;
import '../staff_self/staff_self_providers.dart';
import 'admin_providers.dart';
import 'employee_profile_screen.dart';
import 'role_editor_sheet.dart';

// ---------------------------------------------------------------------------
// Subscription — the tenant's own MoBilling plan
// ---------------------------------------------------------------------------

/// The tenant's plan with MoBilling.
///
/// Not to be confused with client subscriptions — money flows the other way
/// here. Checkout hands off to the payment gateway in a browser, same as the
/// client app's invoice payment.
class SubscriptionScreen extends ConsumerWidget {
  const SubscriptionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subscription = ref.watch(currentSubscriptionProvider);
    final history = ref.watch(subscriptionHistoryProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: const ShellTopBar(eyebrow: 'Account', title: 'Subscription'),
      body: CrmAsyncView(
        value: subscription,
        errorTitle: 'Could not load your subscription',
        onRetry: () => ref.invalidate(currentSubscriptionProvider),
        builder: (sub) => RefreshIndicator(
          onRefresh: () => ref.refresh(currentSubscriptionProvider.future),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              Spacing.md,
              Spacing.md,
              Spacing.md,
              Spacing.xl,
            ),
            children: [
              // The days left are what this screen is about — an expiring
              // plan locks a whole company out — so they are the hero.
              Reveal(child: _PlanCard(sub: sub)),
              const SizedBox(height: Spacing.md),
              PrimaryButton(
                label: sub.isExpired ? 'Renew now' : 'Change plan',
                onPressed: () => _choosePlan(context, ref),
              ),
              if (sub.subscriptionId != null) ...[
                const SizedBox(height: Spacing.sm),
                OutlinedButton.icon(
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                  label: const Text('Download invoice'),
                  onPressed: () => sharePdf(
                    context,
                    fetch: () => ref
                        .read(adminServiceProvider)
                        .subscriptionInvoicePdf(sub.subscriptionId!),
                    filename: 'subscription-${sub.subscriptionId}.pdf',
                  ),
                ),
              ],
              const SizedBox(height: Spacing.lg),
              const SectionHeader('Payment history'),
              const SizedBox(height: Spacing.sm),
              history.maybeWhen(
                data: (entries) => entries.isEmpty
                    ? Text(
                        'No payments yet.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      )
                    : CrmCardList(
                        children: [
                          for (final entry in entries)
                            ListTile(
                              dense: true,
                              title: Text(
                                entry.planName ?? 'Subscription',
                                style: theme.textTheme.titleSmall,
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: CrmStatusLine(
                                  status: entry.status,
                                  meta: [
                                    if (entry.paidAt != null)
                                      Formatting.date(entry.paidAt),
                                    if (entry.startsAt != null &&
                                        entry.endsAt != null)
                                      '${Formatting.date(entry.startsAt)} – '
                                          '${Formatting.date(entry.endsAt)}',
                                  ].join(' · '),
                                ),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Money(entry.amount),
                                  const SizedBox(width: Spacing.xs),
                                  Icon(
                                    Icons.chevron_right,
                                    size: 18,
                                    color: scheme.outline,
                                  ),
                                ],
                              ),
                              onTap: () =>
                                  _openHistoryActions(context, ref, entry),
                            ),
                        ],
                      ),
                orElse: () => const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// A payment's own actions: the invoice PDF for any record, plus proof
  /// upload while the record is still awaiting a bank-transfer confirmation.
  Future<void> _openHistoryActions(
    BuildContext context,
    WidgetRef ref,
    SubscriptionHistoryEntry entry,
  ) async {
    final pending = entry.status.toLowerCase() == 'pending';

    final action = await showCrmSheet<_HistoryAction>(
      context: context,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return CrmSheet(
          eyebrow: 'Payment',
          title: entry.planName ?? 'Subscription',
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(Spacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CrmDetailRow('Amount', Formatting.currency(entry.amount)),
                    CrmDetailRow('Status', StatusColors.label(entry.status)),
                    if (entry.paidAt != null)
                      CrmDetailRow('Paid', Formatting.date(entry.paidAt)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: Spacing.md),
            CrmCardList(
              children: [
                ListTile(
                  leading: const Icon(Icons.picture_as_pdf_outlined),
                  title: Text(
                    'Download invoice',
                    style: theme.textTheme.titleSmall,
                  ),
                  onTap: () =>
                      Navigator.of(sheetContext).pop(_HistoryAction.invoice),
                ),
                if (pending)
                  ListTile(
                    leading: const Icon(Icons.upload_file_outlined),
                    title: Text(
                      'Upload payment proof',
                      style: theme.textTheme.titleSmall,
                    ),
                    subtitle: Text(
                      'For a bank transfer awaiting confirmation',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    onTap: () => Navigator.of(
                      sheetContext,
                    ).pop(_HistoryAction.proof),
                  ),
              ],
            ),
          ],
        );
      },
    );
    if (!context.mounted || action == null) return;

    switch (action) {
      case _HistoryAction.invoice:
        await sharePdf(
          context,
          fetch: () =>
              ref.read(adminServiceProvider).subscriptionInvoicePdf(entry.id),
          filename: 'subscription-${entry.id}.pdf',
        );
      case _HistoryAction.proof:
        await _uploadProof(context, ref, entry.id);
    }
  }

  /// Picks a receipt/screenshot (PDF/JPG/PNG, capped at 5 MB — the server's
  /// own limit) and attaches it to the given subscription record. 422s from
  /// the server (a subscription that moved past `pending`, an oversized or
  /// wrong-type file) surface via the normal [ApiException] path.
  Future<void> _uploadProof(
    BuildContext context,
    WidgetRef ref,
    String tenantSubscriptionId,
  ) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
    );
    final file = result?.files.singleOrNull;
    if (file?.path == null || !context.mounted) return;

    const maxBytes = 5 * 1024 * 1024;
    if (file!.size > maxBytes) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That file is over the 5 MB limit.')),
      );
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('Uploading…')));
    try {
      await ref
          .read(adminServiceProvider)
          .uploadSubscriptionProof(tenantSubscriptionId, file.path!);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        const SnackBar(content: Text('Payment proof uploaded.')),
      );
      ref.invalidate(subscriptionHistoryProvider);
      ref.invalidate(currentSubscriptionProvider);
    } on ApiException catch (e) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _choosePlan(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final plans = await ref.read(plansProvider.future);
    if (!context.mounted) return;

    final chosen = await showCrmSheet<SubscriptionPlan>(
      context: context,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return CrmSheet(
          eyebrow: 'Subscription',
          title: 'Choose a plan',
          children: [
            CrmCardList(
              children: [
                for (final plan in plans)
                  ListTile(
                    title: Text(plan.name, style: theme.textTheme.titleSmall),
                    subtitle: plan.billingCycle == null
                        ? null
                        : Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: CrmMetaLine(
                              plan.billingCycle!.replaceAll('_', ' '),
                            ),
                          ),
                    trailing: Money(plan.price),
                    onTap: () => Navigator.of(sheetContext).pop(plan),
                  ),
              ],
            ),
          ],
        );
      },
    );
    if (chosen == null) return;

    try {
      final url = await ref
          .read(adminServiceProvider)
          .checkoutSubscription(chosen.id);
      if (url == null || url.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Could not start checkout.')),
        );
        return;
      }
      // Hosted gateway page; the webhook settles it server-side.
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      ref.invalidate(currentSubscriptionProvider);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

enum _HistoryAction { invoice, proof }

/// The plan, with the days left as the one figure on the screen. The card
/// takes a 6% wash of the status colour only when the answer is bad — a
/// healthy subscription is not news and should not be coloured like it is.
class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.sub});

  final TenantSubscription sub;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = context.statusColors;

    final tone = sub.isExpired
        ? status.overdue
        : sub.expiringSoon
        ? status.attention
        : null;
    final days = sub.isExpired ? -sub.daysRemaining : sub.daysRemaining;

    return Card(
      color: tone == null
          ? null
          : Color.alphaBlend(tone.withValues(alpha: 0.06), scheme.surface),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    sub.planName ?? 'No active plan',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                StatusChip(sub.chipStatus, dense: true),
              ],
            ),
            const SizedBox(height: Spacing.md),
            Text(
              sub.isExpired ? 'EXPIRED' : 'DAYS REMAINING',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Spacing.xs),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  Formatting.integer(days),
                  style: Type.display(
                    34,
                    color: tone ?? scheme.onSurface,
                  ).copyWith(fontFeatures: Type.figures),
                ),
                const SizedBox(width: Spacing.sm),
                Text(
                  sub.isExpired
                      ? '${days == 1 ? 'day' : 'days'} ago'
                      : days == 1
                      ? 'day'
                      : 'days',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            if (sub.planPrice != null) ...[
              const SizedBox(height: Spacing.md),
              Row(
                children: [
                  Money(sub.planPrice),
                  if (sub.billingCycle != null) ...[
                    const SizedBox(width: Spacing.sm),
                    Flexible(
                      child: CrmMetaLine(
                        sub.billingCycle!.replaceAll('_', ' '),
                      ),
                    ),
                  ],
                ],
              ),
            ],
            if ((sub.isTrial && sub.trialEndsAt != null) ||
                sub.endsAt != null) ...[
              const Divider(height: Spacing.lg),
              if (sub.isTrial && sub.trialEndsAt != null)
                CrmDetailRow('Trial ends', Formatting.date(sub.trialEndsAt)),
              if (sub.endsAt != null)
                CrmDetailRow('Renews', Formatting.date(sub.endsAt)),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Automation
// ---------------------------------------------------------------------------

/// What the scheduled jobs did, and whether any of them failed.
class AutomationScreen extends StatefulWidget {
  const AutomationScreen({super.key});

  @override
  State<AutomationScreen> createState() => _AutomationScreenState();
}

class _AutomationScreenState extends State<AutomationScreen> {
  static const _tabLabels = [
    'Summary',
    'Cron Logs',
    'Messages',
    'Upcoming',
  ];

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: _tabLabels.length,
      child: Scaffold(
        appBar: const ShellTopBar(
          eyebrow: 'Automation',
          title: 'Automation',
          bottom: InkTabBar(isScrollable: true, tabs: _tabLabels),
        ),
        body: const TabBarView(
          children: [
            _SummaryTab(),
            _CronLogsTab(),
            _CommunicationLogsTab(),
            _UpcomingRemindersTab(),
          ],
        ),
      ),
    );
  }
}

/// A day's digest — what the scheduled jobs did, and how many messages went
/// out — with a date picker, since `/automation/summary` defaults to today
/// but the query already accepted any day.
class _SummaryTab extends ConsumerStatefulWidget {
  const _SummaryTab();

  @override
  ConsumerState<_SummaryTab> createState() => _SummaryTabState();
}

class _SummaryTabState extends ConsumerState<_SummaryTab> {
  DateTime? _date;

  String? get _dateKey => _date == null ? null : _ymd(_date!);

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      initialDate: _date ?? now,
    );
    if (picked != null) setState(() => _date = picked);
  }

  @override
  Widget build(BuildContext context) {
    final summary = ref.watch(automationSummaryProvider(_dateKey));
    final status = context.statusColors;

    return CrmAsyncView(
      value: summary,
      errorTitle: 'Could not load automation',
      onRetry: () => ref.invalidate(automationSummaryProvider(_dateKey)),
      builder: (data) => RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(automationSummaryProvider(_dateKey));
          await ref.read(automationSummaryProvider(_dateKey).future);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            Spacing.md,
            Spacing.md,
            Spacing.md,
            Spacing.xl,
          ),
          children: [
            _FilterPill(
              icon: Icons.date_range_outlined,
              label: _date == null ? 'Today' : Formatting.date(_date),
              selected: _date != null,
              onTap: _pickDate,
            ),
            const SizedBox(height: Spacing.lg),
            // The one number worth interrupting someone for.
            if (data.failedCommunications > 0) ...[
              ErrorBanner(
                message:
                    '${Formatting.integer(data.failedCommunications)} '
                    'message${data.failedCommunications == 1 ? '' : 's'} '
                    'failed to send',
              ),
              const SizedBox(height: Spacing.md),
            ],
            SectionHeader(
              'Billing',
              trailing: data.date.isEmpty
                  ? null
                  : CrmMetaLine(Formatting.date(data.date)),
            ),
            const SizedBox(height: Spacing.sm),
            StatRail(
              items: [
                StatRailItem(
                  label: 'Invoices',
                  value: Formatting.integer(data.invoicesCreated),
                ),
                StatRailItem(
                  label: 'Reminders',
                  value: Formatting.integer(data.remindersSent),
                ),
                StatRailItem(
                  label: 'Bills',
                  value: Formatting.integer(data.billsGenerated),
                ),
                StatRailItem(
                  label: 'Expired',
                  value: Formatting.integer(data.subscriptionsExpired),
                  emphasis: data.subscriptionsExpired > 0
                      ? status.attention
                      : null,
                ),
              ],
            ),
            const SizedBox(height: Spacing.lg),
            const SectionHeader('Messages'),
            const SizedBox(height: Spacing.sm),
            StatRail(
              items: [
                StatRailItem(
                  label: 'Emails',
                  value: Formatting.integer(data.emailsSent),
                ),
                StatRailItem(
                  label: 'SMS',
                  value: Formatting.integer(data.smsSent),
                ),
                StatRailItem(
                  label: 'Failed',
                  value: Formatting.integer(data.failedCommunications),
                  emphasis: data.failedCommunications > 0
                      ? status.overdue
                      : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Scheduled-job runs, with a date filter and real pagination — the old
/// screen capped this client-side at 30 with no way to see more.
class _CronLogsTab extends ConsumerStatefulWidget {
  const _CronLogsTab();

  @override
  ConsumerState<_CronLogsTab> createState() => _CronLogsTabState();
}

class _CronLogsTabState extends ConsumerState<_CronLogsTab> {
  final _listKey = GlobalKey<PagedListViewState>();
  DateTime? _date;

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      initialDate: _date ?? now,
    );
    if (picked == null) return;
    setState(() => _date = picked);
    _listKey.currentState?.reload();
  }

  void _clearDate() {
    setState(() => _date = null);
    _listKey.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Spacing.md,
            Spacing.sm,
            Spacing.md,
            Spacing.sm,
          ),
          child: Row(
            children: [
              Expanded(
                child: _FilterPill(
                  icon: Icons.date_range_outlined,
                  label: _date == null ? 'Every day' : Formatting.date(_date),
                  selected: _date != null,
                  onTap: _pickDate,
                ),
              ),
              if (_date != null)
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  tooltip: 'Clear date',
                  visualDensity: VisualDensity.compact,
                  onPressed: _clearDate,
                ),
            ],
          ),
        ),
        Expanded(
          child: PagedListView<CronLogEntry>(
            key: _listKey,
            padding: const EdgeInsets.fromLTRB(
              Spacing.md,
              0,
              Spacing.md,
              Spacing.xl,
            ),
            fetch: (page) => ref
                .read(adminServiceProvider)
                .cronLogs(date: _date == null ? null : _ymd(_date!), page: page),
            itemBuilder: (context, entry) => Card(child: _JobRow(entry: entry)),
            emptyIcon: Icons.event_busy_outlined,
            emptyTitle: 'No runs recorded',
            emptyMessage: 'Nothing ran on this day.',
          ),
        ),
      ],
    );
  }
}

/// Every message the tenant's automations (and staff broadcasts) sent —
/// search, channel/status filters, and a detail sheet per row.
class _CommunicationLogsTab extends ConsumerStatefulWidget {
  const _CommunicationLogsTab();

  @override
  ConsumerState<_CommunicationLogsTab> createState() =>
      _CommunicationLogsTabState();
}

class _CommunicationLogsTabState
    extends ConsumerState<_CommunicationLogsTab> {
  final _listKey = GlobalKey<PagedListViewState>();
  final _search = TextEditingController();
  Timer? _debounce;
  String? _channel;
  String? _status;

  static const _channels = <(String?, String)>[
    (null, 'All channels'),
    ('email', 'Email'),
    ('sms', 'SMS'),
    ('whatsapp', 'WhatsApp'),
  ];
  static const _statuses = <(String?, String)>[
    (null, 'All'),
    ('sent', 'Sent'),
    ('failed', 'Failed'),
    ('pending', 'Pending'),
  ];

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
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Spacing.md,
            Spacing.sm,
            Spacing.md,
            Spacing.sm,
          ),
          child: InkSearchField(
            controller: _search,
            hint: 'Search recipient or client',
            onChanged: _onSearchChanged,
          ),
        ),
        SizedBox(
          height: 40,
          child: FilterStrip(
            options: _channels,
            selected: _channel,
            onSelect: (v) {
              setState(() => _channel = v);
              _listKey.currentState?.reload();
            },
          ),
        ),
        const SizedBox(height: Spacing.xs),
        SizedBox(
          height: 40,
          child: FilterStrip(
            options: _statuses,
            selected: _status,
            onSelect: (v) {
              setState(() => _status = v);
              _listKey.currentState?.reload();
            },
          ),
        ),
        const SizedBox(height: Spacing.sm),
        Expanded(
          child: PagedListView<CommunicationLogEntry>(
            key: _listKey,
            padding: const EdgeInsets.fromLTRB(
              Spacing.md,
              0,
              Spacing.md,
              Spacing.xl,
            ),
            fetch: (page) => ref
                .read(adminServiceProvider)
                .communicationLogs(
                  search: _search.text.trim().isEmpty
                      ? null
                      : _search.text.trim(),
                  channel: _channel,
                  status: _status,
                  page: page,
                ),
            itemBuilder: (context, entry) =>
                Card(child: _CommsLogRow(entry: entry, onTap: _showDetail)),
            emptyIcon: Icons.mark_email_read_outlined,
            emptyTitle: 'Nothing sent yet',
            emptyMessage: 'Messages your automations and staff send appear here.',
          ),
        ),
      ],
    );
  }

  void _showDetail(CommunicationLogEntry entry) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
      builder: (sheetContext) => CrmSheet(
        eyebrow: entry.channel.toUpperCase(),
        title: entry.clientName ?? entry.recipient,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(Spacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CrmDetailRow('To', entry.recipient),
                  CrmDetailRow('Type', entry.type.replaceAll('_', ' ')),
                  CrmDetailRow('Status', entry.status),
                  if (entry.subject != null)
                    CrmDetailRow('Subject', entry.subject!),
                  if (entry.createdAt != null)
                    CrmDetailRow('Sent', Formatting.dateTime(entry.createdAt)),
                ],
              ),
            ),
          ),
          if (entry.message != null && entry.message!.isNotEmpty) ...[
            const SizedBox(height: Spacing.md),
            const SectionHeader('Message'),
            const SizedBox(height: Spacing.sm),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(Spacing.md),
                child: Text(htmlToPlainText(entry.message!)),
              ),
            ),
          ],
          if (entry.failed && entry.error != null) ...[
            const SizedBox(height: Spacing.md),
            ErrorBanner(message: entry.error!),
          ],
        ],
      ),
    );
  }
}

class _CommsLogRow extends StatelessWidget {
  const _CommsLogRow({required this.entry, required this.onTap});

  final CommunicationLogEntry entry;
  final ValueChanged<CommunicationLogEntry> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      dense: true,
      title: Text(
        entry.clientName ?? entry.recipient,
        style: theme.textTheme.titleSmall,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: CrmStatusLine(
          status: entry.status,
          meta: [
            entry.channel,
            entry.type.replaceAll('_', ' '),
            if (entry.createdAt != null) Formatting.dateTime(entry.createdAt),
          ].join(' · '),
        ),
      ),
      trailing: const Icon(Icons.chevron_right, size: 18),
      onTap: () => onTap(entry),
    );
  }
}

/// What the reminder crons will send over the next N days — a forecast, not
/// a log: nothing here has happened yet.
class _UpcomingRemindersTab extends ConsumerStatefulWidget {
  const _UpcomingRemindersTab();

  @override
  ConsumerState<_UpcomingRemindersTab> createState() =>
      _UpcomingRemindersTabState();
}

class _UpcomingRemindersTabState
    extends ConsumerState<_UpcomingRemindersTab> {
  int _days = 14;
  bool _exporting = false;

  @override
  Widget build(BuildContext context) {
    final events = ref.watch(upcomingRemindersProvider(_days));
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Spacing.md,
            Spacing.sm,
            Spacing.md,
            Spacing.sm,
          ),
          child: Row(
            children: [
              Expanded(
                child: SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 7, label: Text('7d')),
                    ButtonSegment(value: 14, label: Text('14d')),
                    ButtonSegment(value: 30, label: Text('30d')),
                    ButtonSegment(value: 60, label: Text('60d')),
                  ],
                  selected: {_days},
                  onSelectionChanged: (s) => setState(() => _days = s.first),
                ),
              ),
              const SizedBox(width: Spacing.sm),
              PopupMenuButton<String>(
                enabled: !_exporting,
                icon: Icon(
                  _exporting ? Icons.hourglass_top : Icons.ios_share_rounded,
                ),
                tooltip: 'Export',
                onSelected: _export,
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'pdf', child: Text('Export PDF')),
                  PopupMenuItem(value: 'csv', child: Text('Export CSV')),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: CrmAsyncView(
            value: events,
            errorTitle: 'Could not load the forecast',
            onRetry: () => ref.invalidate(upcomingRemindersProvider(_days)),
            builder: (rows) => rows.isEmpty
                ? const StateMessage(
                    icon: Icons.notifications_none_outlined,
                    title: 'Nothing coming up',
                    message: 'No reminders are due in this window.',
                  )
                : RefreshIndicator(
                    onRefresh: () async {
                      ref.invalidate(upcomingRemindersProvider(_days));
                      await ref.read(upcomingRemindersProvider(_days).future);
                    },
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(
                        Spacing.md,
                        0,
                        Spacing.md,
                        Spacing.xl,
                      ),
                      children: [
                        for (final entry in _groupByDate(rows).entries) ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: Spacing.sm,
                            ),
                            child: Text(
                              entry.key.toUpperCase(),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          CrmCardList(
                            children: [
                              for (final event in entry.value)
                                _ReminderRow(event: event),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  /// Ordered by first appearance — the API already sorts events by date, so
  /// this just folds consecutive same-date rows under one header.
  Map<String, List<ReminderForecastEvent>> _groupByDate(
    List<ReminderForecastEvent> rows,
  ) {
    final grouped = <String, List<ReminderForecastEvent>>{};
    for (final row in rows) {
      final key = row.date == null ? '—' : Formatting.date(row.date);
      (grouped[key] ??= []).add(row);
    }
    return grouped;
  }

  Future<void> _export(String format) async {
    setState(() => _exporting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await ref
          .read(adminServiceProvider)
          .exportUpcomingReminders(days: _days, format: format);
      final dir = await getTemporaryDirectory();
      final filename = 'upcoming-reminders-${_days}d.$format';
      final file = File('${dir.path}/$filename');
      await file.writeAsBytes(bytes, flush: true);
      await Share.shareXFiles([
        XFile(
          file.path,
          mimeType: format == 'pdf' ? 'application/pdf' : 'text/csv',
        ),
      ], subject: filename);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }
}

class _ReminderRow extends StatelessWidget {
  const _ReminderRow({required this.event});

  final ReminderForecastEvent event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      dense: true,
      title: Text(
        event.clientName,
        style: theme.textTheme.titleSmall,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: CrmMetaLine(
          [
            event.label,
            if (event.channels.isNotEmpty) event.channels.join('/'),
          ].join(' · '),
        ),
      ),
    );
  }
}

String _ymd(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// A tappable date-filter chip — the same visual the Reports screens use,
/// copied locally since that one is private to its own file.
class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;

    return Material(
      color: selected
          ? scheme.primary.withValues(alpha: 0.10)
          : theme.cardTheme.color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.sm),
        side: BorderSide(
          color: selected
              ? scheme.primary.withValues(alpha: 0.45)
              : scheme.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.sm + 2,
            vertical: Spacing.sm + 2,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: Spacing.sm - 2),
              Flexible(
                child: Text(
                  label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One scheduled run: the job it was, a chip for how it ended, and the
/// duration as the row's trailing figure so the column reads down.
class _JobRow extends StatelessWidget {
  const _JobRow({required this.entry});

  final CronLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return ListTile(
      dense: true,
      title: Text(
        entry.job,
        style: theme.textTheme.titleSmall,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CrmStatusLine(
              status: entry.failed ? 'failed' : 'completed',
              meta: entry.ranAt == null ? '' : Formatting.dateTime(entry.ranAt),
            ),
            if (entry.message != null && entry.message!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  entry.message!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      ),
      trailing: entry.durationMs == null
          ? null
          : Text(
              '${Formatting.integer(entry.durationMs)}ms',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Team
// ---------------------------------------------------------------------------

class TeamScreen extends ConsumerStatefulWidget {
  const TeamScreen({super.key});

  @override
  ConsumerState<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends ConsumerState<TeamScreen> {
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
    final me = ref.watch(currentUserProvider);

    // POST /users and PUT /users/{user} both sit behind settings.users.
    final canManage =
        ref
            .watch(sessionControllerProvider)
            .session
            ?.can(AdminPermissions.users) ??
        false;

    return Scaffold(
      appBar: ShellTopBar(
        eyebrow: 'Account',
        title: 'Team',
        trailing: !canManage
            ? null
            : InkActionButton(
                icon: Icons.person_add_alt_outlined,
                tooltip: 'Add a team member',
                onPressed: () => _openForm(null),
              ),
        bottom: InkSearchField(
          controller: _search,
          hint: 'Search name or email',
          onChanged: _onSearchChanged,
        ),
      ),
      body: PagedListView(
        key: _listKey,
        padding: const EdgeInsets.fromLTRB(
          Spacing.md,
          Spacing.md,
          Spacing.md,
          Spacing.xl,
        ),
        fetch: (page) => ref
            .read(adminServiceProvider)
            .users(
              search: _search.text.trim().isEmpty ? null : _search.text.trim(),
              page: page,
            ),
        itemBuilder: (context, user) {
          final isSelf = user.id == me?.id;
          return Card(
            child: ListTile(
              title: Text(
                user.name + (isSelf ? ' (you)' : ''),
                style: theme.textTheme.titleSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: CrmStatusLine(
                  status: user.isActive ? 'active' : 'deactivated',
                  meta: [
                    user.email ?? '',
                    user.roleName ?? 'no role',
                  ].where((s) => s.isNotEmpty).join(' · '),
                ),
              ),
              // The row's actions live in the sheet below rather than as
              // icons out here — there is no room for three on a phone row.
              trailing: Icon(
                Icons.chevron_right,
                size: 18,
                color: scheme.outline,
              ),
              onTap: () => _openActions(user, isSelf: isSelf),
            ),
          );
        },
        emptyIcon: Icons.groups_outlined,
        emptyTitle: 'No staff accounts',
        emptyMessage: 'Nothing matches this search.',
      ),
    );
  }

  /// The row's action sheet: who this is, then what can be done to them.
  Future<void> _openActions(StaffUser user, {required bool isSelf}) async {
    final canManage =
        ref
            .read(sessionControllerProvider)
            .session
            ?.can(AdminPermissions.users) ??
        false;
    // Separate permission from `canManage`: `employees.read`/`.update` gate
    // the HR record (`EmployeeProfileController`), not the sign-in account.
    final canViewProfile =
        ref
            .read(sessionControllerProvider)
            .session
            ?.can(AdminPermissions.employeesRead) ??
        false;

    final action = await showCrmSheet<_TeamAction>(
      context: context,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return CrmSheet(
          eyebrow: 'Team',
          title: user.name,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(Spacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CrmDetailRow(
                      'Status',
                      user.isActive ? 'Active' : 'Deactivated',
                    ),
                    CrmDetailRow('Role', user.roleName ?? 'No role'),
                    if (user.email != null) CrmDetailRow('Email', user.email!),
                    if (user.phone != null) CrmDetailRow('Phone', user.phone!),
                    if (user.lastLoginAt != null)
                      CrmDetailRow(
                        'Last sign-in',
                        Formatting.dateTime(user.lastLoginAt),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: Spacing.md),
            if (canViewProfile) ...[
              CrmCardList(
                children: [
                  ListTile(
                    leading: const Icon(Icons.badge_outlined),
                    title: Text(
                      'HR profile',
                      style: theme.textTheme.titleSmall,
                    ),
                    subtitle: Text(
                      'Employee number, hire date, statutory numbers, '
                      'pay-out details',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    onTap: () =>
                        Navigator.of(sheetContext).pop(_TeamAction.hrProfile),
                  ),
                ],
              ),
              const SizedBox(height: Spacing.md),
            ],
            if (!canManage)
              Text(
                'You can view the team, but not change it.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              )
            else
              CrmCardList(
                children: [
                  ListTile(
                    leading: const Icon(Icons.edit_outlined),
                    title: Text(
                      'Edit details',
                      style: theme.textTheme.titleSmall,
                    ),
                    onTap: () =>
                        Navigator.of(sheetContext).pop(_TeamAction.edit),
                  ),
                  // The API refuses self-deactivation, so it is not offered.
                  if (!isSelf)
                    ListTile(
                      leading: Icon(
                        user.isActive
                            ? Icons.block_outlined
                            : Icons.check_circle_outline,
                      ),
                      title: Text(
                        user.isActive ? 'Deactivate' : 'Reactivate',
                        style: theme.textTheme.titleSmall,
                      ),
                      subtitle: Text(
                        user.isActive
                            ? 'Blocks sign-in; keeps their history'
                            : 'Lets them sign in again',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      onTap: () =>
                          Navigator.of(sheetContext).pop(_TeamAction.toggle),
                    ),
                  // Same 422s as the API: inactive or self isn't offered.
                  if (!isSelf && user.isActive)
                    ListTile(
                      leading: const Icon(Icons.login_outlined),
                      title: Text(
                        'Login as ${user.name}',
                        style: theme.textTheme.titleSmall,
                      ),
                      subtitle: Text(
                        'Sign in as this person to see what they see',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      onTap: () =>
                          Navigator.of(sheetContext).pop(_TeamAction.loginAs),
                    ),
                ],
              ),
          ],
        );
      },
    );

    if (!mounted) return;
    switch (action) {
      case _TeamAction.edit:
        await _openForm(user);
      case _TeamAction.toggle:
        await _toggle(user);
      case _TeamAction.hrProfile:
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                EmployeeProfileScreen(userId: user.id, userName: user.name),
          ),
        );
      case _TeamAction.loginAs:
        await _loginAs(user);
      case null:
        break;
    }
  }

  Future<void> _loginAs(StaffUser user) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Sign in as ${user.name}?'),
        content: const Text(
          'This swaps your session for their account. To return, open the '
          'account sheet (tap your avatar) and use "Back to …" — it stays '
          'there until you do.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Sign in'),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      final body = await ref.read(adminServiceProvider).impersonateUser(user.id);
      // No `user_type` in the response — this endpoint only ever mints a
      // token for a tenant-side `User`, never a `ClientUser`.
      final session = AuthSession.fromJson({...body, 'user_type': 'tenant'});
      await ref.read(sessionControllerProvider).impersonate(session);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// Add (null) or edit a staff account. Both need `settings.users`.
  Future<void> _openForm(StaffUser? user) async {
    final saved = await showCrmSheet<bool>(
      context: context,
      builder: (_) => _UserFormSheet(user: user),
    );
    if (saved == true) _listKey.currentState?.reload();
  }

  Future<void> _toggle(StaffUser user) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(adminServiceProvider).toggleUserActive(user.id);
      _listKey.currentState?.reload();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            user.isActive
                ? '${user.name} deactivated.'
                : '${user.name} reactivated.',
          ),
        ),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

enum _TeamAction { edit, toggle, hrProfile, loginAs }

/// Add or edit a staff account.
///
/// `UserController::update` re-validates the whole record — name, email and
/// role are all required there — so the form carries every field on an edit
/// too, and only the password is genuinely optional.
class _UserFormSheet extends ConsumerStatefulWidget {
  const _UserFormSheet({required this.user});

  final StaffUser? user;

  @override
  ConsumerState<_UserFormSheet> createState() => _UserFormSheetState();
}

class _UserFormSheetState extends ConsumerState<_UserFormSheet> {
  late final TextEditingController _name;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  final _password = TextEditingController();

  String? _roleId;
  String? _roleName;
  String? _error;
  bool _busy = false;

  bool get _isNew => widget.user == null;

  @override
  void initState() {
    super.initState();
    final user = widget.user;
    _name = TextEditingController(text: user?.name ?? '');
    _email = TextEditingController(text: user?.email ?? '');
    _phone = TextEditingController(text: user?.phone ?? '');
    _roleId = user?.roleId;
    _roleName = user?.roleName;
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return CrmSheet(
      eyebrow: 'Team',
      title: _isNew ? 'Add a team member' : widget.user!.name,
      children: [
        if (_error != null) ...[
          ErrorBanner(message: _error!),
          const SizedBox(height: Spacing.md),
        ],
        CrmField(
          label: 'Name',
          child: TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(hintText: 'Full name'),
          ),
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Email',
          child: TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: const InputDecoration(
              hintText: 'What they sign in with',
            ),
          ),
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Phone',
          child: TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(hintText: 'Optional'),
          ),
        ),
        const SizedBox(height: Spacing.md),
        CrmPickerField(
          label: 'Role',
          icon: Icons.shield_outlined,
          value: _roleName ?? 'Choose a role',
          placeholder: _roleId == null,
          onTap: _busy ? null : _pickRole,
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: _isNew ? 'Password' : 'New password',
          child: TextField(
            controller: _password,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              hintText: _isNew
                  ? 'At least 8 characters'
                  : 'Leave blank to keep the current one',
            ),
          ),
        ),
        const SizedBox(height: Spacing.lg),
        PrimaryButton(
          label: _isNew ? 'Add member' : 'Save changes',
          busy: _busy,
          onPressed: _busy ? null : _submit,
        ),
        if (_isNew) ...[
          const SizedBox(height: Spacing.sm),
          Text(
            'They sign in with this email and password. Tell them to change '
            'the password once they are in.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  Future<void> _pickRole() async {
    final roles = await ref.read(rolesProvider.future);
    if (!mounted) return;

    final chosen = await showCrmSheet<StaffRole>(
      context: context,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return CrmSheet(
          eyebrow: 'Team',
          title: 'Choose a role',
          children: [
            CrmCardList(
              children: [
                for (final role in roles)
                  ListTile(
                    title: Text(
                      role.displayName,
                      style: theme.textTheme.titleSmall,
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: CrmMetaLine(
                        '${role.permissionNames.length} '
                        'permission${role.permissionNames.length == 1 ? '' : 's'}',
                      ),
                    ),
                    trailing: role.id == _roleId
                        ? Icon(
                            Icons.check,
                            size: 18,
                            color: Theme.of(sheetContext).colorScheme.primary,
                          )
                        : null,
                    onTap: () => Navigator.of(sheetContext).pop(role),
                  ),
              ],
            ),
          ],
        );
      },
    );
    if (chosen == null || !mounted) return;
    setState(() {
      _roleId = chosen.id;
      _roleName = chosen.displayName;
    });
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    final email = _email.text.trim();
    final phone = _phone.text.trim();
    final password = _password.text;
    final roleId = _roleId;

    // Mirrors UserController's rules, so an obvious slip costs no round trip.
    String? complaint;
    if (name.isEmpty) {
      complaint = 'A name is required.';
    } else if (email.isEmpty) {
      complaint = 'An email is required — it is what they sign in with.';
    } else if (roleId == null) {
      complaint = 'Choose a role.';
    } else if ((_isNew || password.isNotEmpty) && password.length < 8) {
      complaint = 'The password must be at least 8 characters.';
    }
    if (complaint != null) {
      setState(() => _error = complaint);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final service = ref.read(adminServiceProvider);
      if (_isNew) {
        await service.createUser(
          name: name,
          email: email,
          password: password,
          roleId: roleId!,
          phone: phone.isEmpty ? null : phone,
        );
      } else {
        await service.updateUser(
          widget.user!.id,
          name: name,
          email: email,
          // An emptied phone must clear the column, so '' goes up rather
          // than being dropped as "unchanged".
          phone: phone,
          roleId: roleId,
          password: password.isEmpty ? null : password,
        );
      }
      navigator.pop(true);
      messenger.showSnackBar(
        SnackBar(
          content: Text(_isNew ? '$name added to the team.' : '$name updated.'),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }
}

// ---------------------------------------------------------------------------
// Roles
// ---------------------------------------------------------------------------

/// Roles and what each one grants.
///
/// The web renders a wide permission matrix; on a phone that becomes a role
/// list drilling into a searchable grouped checklist, which is the same
/// information in a shape a thumb can actually use.
class RolesScreen extends ConsumerWidget {
  const RolesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roles = ref.watch(rolesProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // POST/PUT/DELETE /roles all sit behind settings.users — same string the
    // route middleware and RoleController enforce.
    final canManage =
        ref
            .watch(sessionControllerProvider)
            .session
            ?.can(AdminPermissions.roles) ??
        false;

    Future<void> open(StaffRole? role) async {
      final changed = await showRoleEditor(context, role: role);
      if (changed == true) ref.invalidate(rolesProvider);
    }

    return Scaffold(
      appBar: ShellTopBar(
        eyebrow: 'Account',
        title: 'Roles',
        trailing: !canManage
            ? null
            : InkActionButton(
                icon: Icons.add,
                tooltip: 'Create a role',
                onPressed: () => open(null),
              ),
      ),
      body: CrmAsyncView(
        value: roles,
        errorTitle: 'Could not load roles',
        onRetry: () => ref.invalidate(rolesProvider),
        builder: (items) => items.isEmpty
            ? StateMessage(
                icon: Icons.shield_outlined,
                title: 'No roles yet',
                message: canManage
                    ? 'Create one to decide what a team member can reach.'
                    : 'Roles are created by an administrator.',
                actionLabel: canManage ? 'Create a role' : null,
                onAction: canManage ? () => open(null) : null,
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(
                  Spacing.md,
                  Spacing.md,
                  Spacing.md,
                  Spacing.xl,
                ),
                children: [
                  CrmCardList(
                    children: [
                      for (final role in items)
                        ListTile(
                          title: Text(
                            role.displayName,
                            style: theme.textTheme.titleSmall,
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: CrmMetaLine(
                              [
                                '${role.usersCount} '
                                    'user${role.usersCount == 1 ? '' : 's'}',
                                if (role.isSystem) 'system role',
                              ].join(' · '),
                            ),
                          ),
                          // The permission count is the figure that separates
                          // one role from the next, so it holds the right
                          // edge like an amount would.
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                Formatting.integer(role.permissionNames.length),
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: scheme.onSurface,
                                ),
                              ),
                              const SizedBox(width: Spacing.xs),
                              Icon(
                                Icons.chevron_right,
                                size: 18,
                                color: scheme.outline,
                              ),
                            ],
                          ),
                          onTap: canManage
                              ? () => open(role)
                              : () => showCrmSheet<void>(
                                  context: context,
                                  builder: (_) =>
                                      _RolePermissionsSheet(role: role),
                                ),
                        ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }
}

/// What a role grants, read-only — for someone who can see the Roles screen
/// but does not hold `settings.users`.
class _RolePermissionsSheet extends ConsumerWidget {
  const _RolePermissionsSheet({required this.role});

  final StaffRole role;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final granted = role.permissionNames.toSet();

    // Group by the permission name's prefix so the list is scannable.
    final grouped = <String, List<String>>{};
    for (final name in role.permissionNames) {
      final group = name.contains('.') ? name.split('.').first : 'general';
      grouped.putIfAbsent(group, () => []).add(name);
    }
    final groups = grouped.keys.toList()..sort();

    return CrmSheet(
      eyebrow: 'Role',
      title: role.displayName,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: Spacing.lg),
          child: Text(
            '${granted.length} permission${granted.length == 1 ? '' : 's'}'
            '${role.isSystem ? ' · system role' : ''}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        for (final group in groups) ...[
          Text(
            group.replaceAll('_', ' ').toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: Spacing.sm),
          Wrap(
            spacing: Spacing.xs,
            runSpacing: Spacing.xs,
            children: [
              for (final name in grouped[group]!)
                Chip(
                  label: Text(name.split('.').last.replaceAll('_', ' ')),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
            ],
          ),
          const SizedBox(height: Spacing.md),
        ],
        const SizedBox(height: Spacing.sm),
        Text(
          'Changing a role needs the “Manage users & roles” permission.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Settings
// ---------------------------------------------------------------------------

/// Everything the web's Settings page covers: the company profile, the
/// signed-in user's own account, bank accounts, the systems catalog, and the
/// reminder / template / payment-method / late-fee policy. Laid out as tabs,
/// each gated on its own read permission, since a phone can't show the web's
/// grid of cards all at once.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider).session;
    bool can(String permission) => session?.can(permission) ?? false;

    final canBankRead = can(AdminPermissions.bankAccountsRead);
    final canSystemsRead = can(StaffSelfPermissions.systemsRead);
    final canPropertiesRead = can(StaffSelfPermissions.systemPropertiesRead);
    final canReminders = can(AdminPermissions.settingsReminders);
    final canTemplates = can(AdminPermissions.settingsTemplates);
    final canPaymentMethods = can(AdminPermissions.settingsPaymentMethods);

    final tabs = <(String, Widget)>[
      ('General', const _GeneralSettingsTab()),
      ('Profile', const _ProfileTab()),
      if (canBankRead) ('Bank accounts', const _BankAccountsTab()),
      if (canSystemsRead) ('Systems', const _SystemsTab()),
      if (canPropertiesRead) ('Properties', const _SystemPropertiesTab()),
      if (canReminders) ('Reminders', const _RemindersTab()),
      if (canTemplates) ('Templates', const _TemplatesTab()),
      if (canPaymentMethods) ('Payment methods', const _PaymentMethodsTab()),
      if (canReminders) ('Late fee', const _LateFeeTab()),
    ];

    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: ShellTopBar(
          eyebrow: 'Account',
          title: 'Settings',
          bottom: InkTabBar(
            isScrollable: tabs.length > 3,
            tabs: [for (final (label, _) in tabs) label],
          ),
        ),
        body: TabBarView(children: [for (final (_, body) in tabs) body]),
      ),
    );
  }
}

/// A confirmation dialog for a destructive action, shared by every delete
/// button in this screen.
Future<bool> _confirmDelete(
  BuildContext context, {
  required String title,
  required String message,
}) async {
  final sure = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(dialogContext).colorScheme.error,
          ),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return sure == true;
}

enum _ListAction { edit, delete }

// ---------------------------------------------------------------------------
// General — appearance + company profile
// ---------------------------------------------------------------------------

class _GeneralSettingsTab extends ConsumerWidget {
  const _GeneralSettingsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final company = ref.watch(companySettingsProvider);

    // PUT /settings/company needs settings.company.
    final canEdit =
        ref.watch(sessionControllerProvider).session?.can('settings.company') ??
        false;

    return CrmAsyncView(
      value: company,
      errorTitle: 'Could not load settings',
      onRetry: () => ref.invalidate(companySettingsProvider),
      builder: (settings) => RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(companySettingsProvider);
          await ref.read(companySettingsProvider.future);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            Spacing.md,
            Spacing.md,
            Spacing.md,
            Spacing.xl,
          ),
          children: [
            // Device-level preference — the same control as the account
            // sheet and the sign-in toggle, so the choice is reachable
            // wherever someone looks for it.
            const SectionHeader('Appearance'),
            const SizedBox(height: Spacing.sm),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(Spacing.md),
                child: AppearanceControl(),
              ),
            ),
            const SizedBox(height: Spacing.lg),
            SectionHeader(
              'Company',
              trailing: !canEdit
                  ? null
                  : TextButton(
                      onPressed: () => _editCompany(context, ref, settings),
                      child: const Text('Edit'),
                    ),
            ),
            const SizedBox(height: Spacing.sm),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(Spacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CrmDetailRow('Name', settings.name),
                    if (settings.email != null)
                      CrmDetailRow('Email', settings.email!),
                    if (settings.phone != null)
                      CrmDetailRow('Phone', settings.phone!),
                    if (settings.address != null)
                      CrmDetailRow('Address', settings.address!),
                    if (settings.taxId != null)
                      CrmDetailRow('TIN', settings.taxId!),
                    if (settings.currency != null)
                      CrmDetailRow('Currency', settings.currency!),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editCompany(
    BuildContext context,
    WidgetRef ref,
    CompanySettings current,
  ) async {
    final name = TextEditingController(text: current.name);
    final email = TextEditingController(text: current.email ?? '');
    final phone = TextEditingController(text: current.phone ?? '');
    final address = TextEditingController(text: current.address ?? '');
    final taxId = TextEditingController(text: current.taxId ?? '');
    final messenger = ScaffoldMessenger.of(context);

    final saved = await showCrmSheet<bool>(
      context: context,
      builder: (sheetContext) => CrmSheet(
        eyebrow: 'Settings',
        title: 'Company details',
        children: [
          CrmField(
            label: 'Name',
            child: TextField(
              controller: name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                hintText: 'The name that prints on invoices',
              ),
            ),
          ),
          const SizedBox(height: Spacing.md),
          CrmField(
            label: 'Email',
            child: TextField(
              controller: email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                hintText: 'billing@company.co.tz',
              ),
            ),
          ),
          const SizedBox(height: Spacing.md),
          CrmField(
            label: 'Phone',
            child: TextField(
              controller: phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(hintText: 'Reachable number'),
            ),
          ),
          const SizedBox(height: Spacing.md),
          CrmField(
            label: 'Address',
            child: TextField(
              controller: address,
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Street, city'),
            ),
          ),
          const SizedBox(height: Spacing.md),
          CrmField(
            label: 'TIN',
            child: TextField(
              controller: taxId,
              decoration: const InputDecoration(hintText: 'Tax number'),
            ),
          ),
          const SizedBox(height: Spacing.lg),
          PrimaryButton(
            label: 'Save company',
            onPressed: () => Navigator.of(sheetContext).pop(true),
          ),
        ],
      ),
    );
    if (saved != true) return;

    if (email.text.trim().isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('A company email is required.')),
      );
      return;
    }

    try {
      await ref
          .read(adminServiceProvider)
          .updateCompany(
            name: name.text.trim(),
            email: email.text.trim(),
            // Required by the API; not editable here — it is the billing
            // currency and changing it is a web/super-admin decision.
            currency: current.currency ?? Formatting.tenantCurrency,
            phone: phone.text.trim().isEmpty ? null : phone.text.trim(),
            address: address.text.trim().isEmpty ? null : address.text.trim(),
            taxId: taxId.text.trim().isEmpty ? null : taxId.text.trim(),
          );
      ref.invalidate(companySettingsProvider);
      messenger.showSnackBar(const SnackBar(content: Text('Company updated.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

// ---------------------------------------------------------------------------
// Profile — the signed-in account's own name/email/phone and password
// ---------------------------------------------------------------------------

/// The signed-in staff member's own account. `PUT /settings/profile` has no
/// permission gate — this is self-service for whoever is signed in.
///
/// There is no other place in this app where a staff account edits its own
/// name/email/phone (the only existing "profile" screen,
/// `PortalProfileScreen`, edits a *client*-portal account through a
/// different service entirely), so the full form lives here rather than
/// splitting it across two places.
class _ProfileTab extends ConsumerStatefulWidget {
  const _ProfileTab();

  @override
  ConsumerState<_ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends ConsumerState<_ProfileTab> {
  late final TextEditingController _name;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  final _currentPassword = TextEditingController();
  final _newPassword = TextEditingController();
  bool _changingPassword = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final user = ref.read(currentUserProvider);
    _name = TextEditingController(text: user?.name ?? '');
    _email = TextEditingController(text: user?.email ?? '');
    _phone = TextEditingController(text: user?.phone ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _currentPassword.dispose();
    _newPassword.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final email = _email.text.trim();
    final phone = _phone.text.trim();
    final newPassword = _newPassword.text;
    final currentPassword = _currentPassword.text;

    String? complaint;
    if (name.isEmpty) {
      complaint = 'A name is required.';
    } else if (email.isEmpty) {
      complaint = 'An email is required — it is what you sign in with.';
    } else if (_changingPassword && newPassword.length < 8) {
      complaint = 'The new password must be at least 8 characters.';
    } else if (_changingPassword && currentPassword.isEmpty) {
      complaint = 'Enter your current password to set a new one.';
    }
    if (complaint != null) {
      setState(() => _error = complaint);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(adminServiceProvider)
          .updateProfile(
            name: name,
            email: email,
            phone: phone,
            currentPassword: _changingPassword ? currentPassword : null,
            password: _changingPassword ? newPassword : null,
          );
      if (!mounted) return;
      _currentPassword.clear();
      _newPassword.clear();
      setState(() {
        _saving = false;
        _changingPassword = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profile updated.')));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return ListView(
      padding: const EdgeInsets.all(Spacing.md),
      children: [
        const SectionHeader('Your details'),
        const SizedBox(height: Spacing.sm),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error != null) ...[
                  ErrorBanner(message: _error!),
                  const SizedBox(height: Spacing.md),
                ],
                CrmField(
                  label: 'Name',
                  child: TextField(
                    controller: _name,
                    enabled: !_saving,
                    textCapitalization: TextCapitalization.words,
                  ),
                ),
                const SizedBox(height: Spacing.md),
                CrmField(
                  label: 'Email',
                  child: TextField(
                    controller: _email,
                    enabled: !_saving,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      hintText: 'What you sign in with',
                    ),
                  ),
                ),
                const SizedBox(height: Spacing.md),
                CrmField(
                  label: 'Phone',
                  child: TextField(
                    controller: _phone,
                    enabled: !_saving,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(hintText: 'Optional'),
                  ),
                ),
                const SizedBox(height: Spacing.md),
                if (!_changingPassword)
                  OutlinedButton(
                    onPressed: _saving
                        ? null
                        : () => setState(() => _changingPassword = true),
                    child: const Text('Change password'),
                  )
                else ...[
                  CrmField(
                    label: 'Current password',
                    child: TextField(
                      controller: _currentPassword,
                      enabled: !_saving,
                      obscureText: true,
                      autocorrect: false,
                      enableSuggestions: false,
                    ),
                  ),
                  const SizedBox(height: Spacing.md),
                  CrmField(
                    label: 'New password',
                    child: TextField(
                      controller: _newPassword,
                      enabled: !_saving,
                      obscureText: true,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: const InputDecoration(
                        hintText: 'At least 8 characters',
                      ),
                    ),
                  ),
                  const SizedBox(height: Spacing.sm),
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => setState(() {
                            _changingPassword = false;
                            _currentPassword.clear();
                            _newPassword.clear();
                          }),
                    child: const Text('Cancel password change'),
                  ),
                ],
                const SizedBox(height: Spacing.lg),
                PrimaryButton(
                  label: _saving ? 'Saving…' : 'Save changes',
                  busy: _saving,
                  onPressed: _saving ? null : _save,
                ),
                const SizedBox(height: Spacing.sm),
                Text(
                  'A changed name or role badge elsewhere in the app may '
                  'need a fresh sign-in to catch up.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Bank accounts — full CRUD
// ---------------------------------------------------------------------------

class _BankAccountsTab extends ConsumerWidget {
  const _BankAccountsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final banks = ref.watch(bankAccountsProvider);
    final session = ref.watch(sessionControllerProvider).session;
    final canCreate = session?.can(AdminPermissions.bankAccountsCreate) ?? false;
    final canUpdate = session?.can(AdminPermissions.bankAccountsUpdate) ?? false;
    final canDelete = session?.can(AdminPermissions.bankAccountsDelete) ?? false;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CrmAsyncView(
        value: banks,
        errorTitle: 'Could not load bank accounts',
        onRetry: () => ref.invalidate(bankAccountsProvider),
        builder: (accounts) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(bankAccountsProvider);
            await ref.read(bankAccountsProvider.future);
          },
          child: accounts.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    SizedBox(
                      height: 420,
                      child: StateMessage(
                        icon: Icons.account_balance_outlined,
                        title: 'No bank accounts',
                        message: canCreate
                            ? 'Add one to record bank-linked payments.'
                            : 'None configured yet.',
                        actionLabel: canCreate ? 'Add bank account' : null,
                        onAction: canCreate
                            ? () => _openForm(context, ref, null)
                            : null,
                      ),
                    ),
                  ],
                )
              : ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(
                    Spacing.md,
                    Spacing.md,
                    Spacing.md,
                    Spacing.xxl + Spacing.lg,
                  ),
                  children: [
                    CrmCardList(
                      children: [
                        for (final account in accounts)
                          ListTile(
                            title: Text(
                              account.bankName,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: CrmMetaLine(
                                [
                                  if ((account.accountNumber ?? '').isNotEmpty)
                                    account.accountNumber!,
                                  if (account.openingBalance != null)
                                    'Opening '
                                        '${Formatting.currency(account.openingBalance)}',
                                ].join(' · '),
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (!account.isActive) ...[
                                  const StatusChip('draft', dense: true),
                                  const SizedBox(width: Spacing.xs),
                                ],
                                if (canUpdate || canDelete)
                                  Icon(
                                    Icons.chevron_right,
                                    size: 18,
                                    color: scheme.outline,
                                  ),
                              ],
                            ),
                            onTap: (canUpdate || canDelete)
                                ? () => _openActions(
                                    context,
                                    ref,
                                    account,
                                    canUpdate: canUpdate,
                                    canDelete: canDelete,
                                  )
                                : null,
                          ),
                      ],
                    ),
                  ],
                ),
        ),
      ),
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              heroTag: 'bank-account-fab',
              onPressed: () => _openForm(context, ref, null),
              icon: const Icon(Icons.add),
              label: const Text('Add account'),
            )
          : null,
    );
  }

  Future<void> _openActions(
    BuildContext context,
    WidgetRef ref,
    BankAccount account, {
    required bool canUpdate,
    required bool canDelete,
  }) async {
    final action = await showCrmSheet<_ListAction>(
      context: context,
      builder: (sheetContext) {
        final scheme = Theme.of(sheetContext).colorScheme;
        return CrmSheet(
          eyebrow: 'Bank account',
          title: account.bankName,
          children: [
            CrmCardList(
              children: [
                if (canUpdate)
                  ListTile(
                    leading: const Icon(Icons.edit_outlined),
                    title: const Text('Edit'),
                    onTap: () =>
                        Navigator.of(sheetContext).pop(_ListAction.edit),
                  ),
                if (canDelete)
                  ListTile(
                    leading: Icon(Icons.delete_outline, color: scheme.error),
                    title: Text(
                      'Delete',
                      style: TextStyle(color: scheme.error),
                    ),
                    onTap: () =>
                        Navigator.of(sheetContext).pop(_ListAction.delete),
                  ),
              ],
            ),
          ],
        );
      },
    );
    if (!context.mounted) return;
    switch (action) {
      case _ListAction.edit:
        await _openForm(context, ref, account);
      case _ListAction.delete:
        await _delete(context, ref, account);
      case null:
        break;
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    BankAccount account,
  ) async {
    final sure = await _confirmDelete(
      context,
      title: 'Delete ${account.bankName}?',
      message: 'This cannot be undone.',
    );
    if (!sure || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(adminServiceProvider).deleteBankAccount(account.id);
      ref.invalidate(bankAccountsProvider);
      ref.invalidate(recordBankAccountsProvider);
      messenger.showSnackBar(
        const SnackBar(content: Text('Bank account deleted.')),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _openForm(
    BuildContext context,
    WidgetRef ref,
    BankAccount? account,
  ) async {
    final saved = await showCrmSheet<bool>(
      context: context,
      builder: (_) => _BankAccountFormSheet(account: account),
    );
    if (saved == true) {
      ref.invalidate(bankAccountsProvider);
      ref.invalidate(recordBankAccountsProvider);
    }
  }
}

/// Add or edit a bank account. `bank_accounts` has no `account_name`/`branch`
/// columns, so — unlike the model's leftover fields for old call sites — the
/// form only ever collects name, number, opening balance and active state.
class _BankAccountFormSheet extends ConsumerStatefulWidget {
  const _BankAccountFormSheet({this.account});

  final BankAccount? account;

  @override
  ConsumerState<_BankAccountFormSheet> createState() =>
      _BankAccountFormSheetState();
}

class _BankAccountFormSheetState extends ConsumerState<_BankAccountFormSheet> {
  late final TextEditingController _bankName;
  late final TextEditingController _accountNumber;
  late final TextEditingController _openingBalance;
  late bool _isActive;
  bool _busy = false;
  String? _error;

  bool get _editing => widget.account != null;

  @override
  void initState() {
    super.initState();
    final a = widget.account;
    _bankName = TextEditingController(text: a?.bankName ?? '');
    _accountNumber = TextEditingController(text: a?.accountNumber ?? '');
    _openingBalance = TextEditingController(
      text: a?.openingBalance == null ? '' : Formatting.amount(a!.openingBalance),
    );
    _isActive = a?.isActive ?? true;
  }

  @override
  void dispose() {
    _bankName.dispose();
    _accountNumber.dispose();
    _openingBalance.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final bankName = _bankName.text.trim();
    final accountNumber = _accountNumber.text.trim();
    final balanceText = _openingBalance.text.trim();

    String? complaint;
    double? openingBalance;
    if (bankName.isEmpty) {
      complaint = 'A bank name is required.';
    } else if (accountNumber.isEmpty) {
      complaint = 'An account number is required.';
    } else if (balanceText.isNotEmpty) {
      openingBalance = double.tryParse(balanceText.replaceAll(',', ''));
      if (openingBalance == null) {
        complaint = 'Enter a valid opening balance.';
      }
    }
    if (complaint != null) {
      setState(() => _error = complaint);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final service = ref.read(adminServiceProvider);
      if (_editing) {
        await service.updateBankAccount(
          widget.account!.id,
          bankName: bankName,
          accountNumber: accountNumber,
          openingBalance: openingBalance,
          isActive: _isActive,
        );
      } else {
        await service.createBankAccount(
          bankName: bankName,
          accountNumber: accountNumber,
          openingBalance: openingBalance,
          isActive: _isActive,
        );
      }
      navigator.pop(true);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            _editing ? 'Bank account updated.' : 'Bank account added.',
          ),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return CrmSheet(
      eyebrow: 'Bank account',
      title: _editing ? 'Edit bank account' : 'Add bank account',
      children: [
        if (_error != null) ...[
          ErrorBanner(message: _error!),
          const SizedBox(height: Spacing.md),
        ],
        CrmField(
          label: 'Bank name',
          child: TextField(
            controller: _bankName,
            enabled: !_busy,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(hintText: 'e.g. CRDB Bank'),
          ),
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Account number',
          child: TextField(controller: _accountNumber, enabled: !_busy),
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Opening balance',
          child: TextField(
            controller: _openingBalance,
            enabled: !_busy,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(hintText: 'Optional'),
          ),
        ),
        const SizedBox(height: Spacing.sm),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Active'),
          value: _isActive,
          onChanged: _busy ? null : (v) => setState(() => _isActive = v),
        ),
        const SizedBox(height: Spacing.lg),
        PrimaryButton(
          label: _editing ? 'Save changes' : 'Add account',
          busy: _busy,
          onPressed: _busy ? null : _submit,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Systems & system properties — flat name+active-toggle catalogs
// ---------------------------------------------------------------------------

/// A flat name+active-toggle catalog. Systems and system properties share
/// this exact shape — the only difference is which endpoints and permissions
/// back them — so one widget serves both, parameterised by the provider and
/// the three CRUD calls.
class _SystemOptionsTab extends ConsumerWidget {
  const _SystemOptionsTab({
    required this.noun,
    required this.heroTag,
    required this.provider,
    required this.canCreate,
    required this.canUpdate,
    required this.canDelete,
    required this.create,
    required this.update,
    required this.delete,
  });

  /// Lower-case singular, e.g. `'system'` / `'property'`, for messages.
  final String noun;
  final String heroTag;
  final AutoDisposeFutureProvider<List<SystemOption>> provider;
  final bool canCreate;
  final bool canUpdate;
  final bool canDelete;
  final Future<SystemOption> Function(String name) create;
  final Future<SystemOption> Function(
    String id, {
    required String name,
    bool isActive,
  })
  update;
  final Future<void> Function(String id) delete;

  String get _titleCaseNoun => noun[0].toUpperCase() + noun.substring(1);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(provider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CrmAsyncView(
        value: items,
        errorTitle: 'Could not load ${noun}s',
        onRetry: () => ref.invalidate(provider),
        builder: (options) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(provider);
            await ref.read(provider.future);
          },
          child: options.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    SizedBox(
                      height: 420,
                      child: StateMessage(
                        icon: Icons.dns_outlined,
                        title: 'No ${noun}s yet',
                        message: canCreate
                            ? 'Add one to log records against it.'
                            : 'None set up yet.',
                        actionLabel: canCreate ? 'Add $noun' : null,
                        onAction: canCreate
                            ? () => _openForm(context, ref, null)
                            : null,
                      ),
                    ),
                  ],
                )
              : ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(
                    Spacing.md,
                    Spacing.md,
                    Spacing.md,
                    Spacing.xxl + Spacing.lg,
                  ),
                  children: [
                    CrmCardList(
                      children: [
                        for (final option in options)
                          ListTile(
                            title: Text(
                              option.name,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (!option.isActive) ...[
                                  const StatusChip('draft', dense: true),
                                  const SizedBox(width: Spacing.xs),
                                ],
                                if (canUpdate || canDelete)
                                  Icon(
                                    Icons.chevron_right,
                                    size: 18,
                                    color: scheme.outline,
                                  ),
                              ],
                            ),
                            onTap: (canUpdate || canDelete)
                                ? () => _openActions(context, ref, option)
                                : null,
                          ),
                      ],
                    ),
                  ],
                ),
        ),
      ),
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              heroTag: heroTag,
              onPressed: () => _openForm(context, ref, null),
              icon: const Icon(Icons.add),
              label: Text('Add $noun'),
            )
          : null,
    );
  }

  Future<void> _openActions(
    BuildContext context,
    WidgetRef ref,
    SystemOption option,
  ) async {
    final action = await showCrmSheet<_ListAction>(
      context: context,
      builder: (sheetContext) {
        final scheme = Theme.of(sheetContext).colorScheme;
        return CrmSheet(
          eyebrow: _titleCaseNoun,
          title: option.name,
          children: [
            CrmCardList(
              children: [
                if (canUpdate)
                  ListTile(
                    leading: const Icon(Icons.edit_outlined),
                    title: const Text('Edit'),
                    onTap: () =>
                        Navigator.of(sheetContext).pop(_ListAction.edit),
                  ),
                if (canDelete)
                  ListTile(
                    leading: Icon(Icons.delete_outline, color: scheme.error),
                    title: Text(
                      'Delete',
                      style: TextStyle(color: scheme.error),
                    ),
                    onTap: () =>
                        Navigator.of(sheetContext).pop(_ListAction.delete),
                  ),
              ],
            ),
          ],
        );
      },
    );
    if (!context.mounted) return;
    switch (action) {
      case _ListAction.edit:
        await _openForm(context, ref, option);
      case _ListAction.delete:
        await _delete(context, ref, option);
      case null:
        break;
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    SystemOption option,
  ) async {
    final sure = await _confirmDelete(
      context,
      title: 'Delete ${option.name}?',
      message: 'This cannot be undone.',
    );
    if (!sure || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await delete(option.id);
      ref.invalidate(provider);
      messenger.showSnackBar(SnackBar(content: Text('${option.name} deleted.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _openForm(
    BuildContext context,
    WidgetRef ref,
    SystemOption? option,
  ) async {
    final saved = await showCrmSheet<bool>(
      context: context,
      builder: (_) => _SystemOptionFormSheet(
        noun: noun,
        option: option,
        create: create,
        update: update,
      ),
    );
    if (saved == true) ref.invalidate(provider);
  }
}

class _SystemsTab extends ConsumerWidget {
  const _SystemsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider).session;
    final service = ref.watch(staffSelfServiceProvider);
    return _SystemOptionsTab(
      noun: 'system',
      heroTag: 'system-fab',
      provider: systemsProvider,
      canCreate: session?.can(StaffSelfPermissions.systemsCreate) ?? false,
      canUpdate: session?.can(StaffSelfPermissions.systemsUpdate) ?? false,
      canDelete: session?.can(StaffSelfPermissions.systemsDelete) ?? false,
      create: service.createSystem,
      update: service.updateSystem,
      delete: service.deleteSystem,
    );
  }
}

class _SystemPropertiesTab extends ConsumerWidget {
  const _SystemPropertiesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider).session;
    final service = ref.watch(staffSelfServiceProvider);
    return _SystemOptionsTab(
      noun: 'property',
      heroTag: 'system-property-fab',
      provider: systemPropertiesProvider,
      canCreate:
          session?.can(StaffSelfPermissions.systemPropertiesCreate) ?? false,
      canUpdate:
          session?.can(StaffSelfPermissions.systemPropertiesUpdate) ?? false,
      canDelete:
          session?.can(StaffSelfPermissions.systemPropertiesDelete) ?? false,
      create: service.createSystemProperty,
      update: service.updateSystemProperty,
      delete: service.deleteSystemProperty,
    );
  }
}

/// Add or edit a system/system-property row. Creation only ever sends a
/// name — the active toggle exists solely to retire one later.
class _SystemOptionFormSheet extends StatefulWidget {
  const _SystemOptionFormSheet({
    required this.noun,
    required this.option,
    required this.create,
    required this.update,
  });

  final String noun;
  final SystemOption? option;
  final Future<SystemOption> Function(String name) create;
  final Future<SystemOption> Function(
    String id, {
    required String name,
    bool isActive,
  })
  update;

  @override
  State<_SystemOptionFormSheet> createState() => _SystemOptionFormSheetState();
}

class _SystemOptionFormSheetState extends State<_SystemOptionFormSheet> {
  late final TextEditingController _name;
  late bool _isActive;
  bool _busy = false;
  String? _error;

  bool get _editing => widget.option != null;
  String get _titleCaseNoun =>
      widget.noun[0].toUpperCase() + widget.noun.substring(1);

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.option?.name ?? '');
    _isActive = widget.option?.isActive ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'A name is required.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      if (_editing) {
        await widget.update(widget.option!.id, name: name, isActive: _isActive);
      } else {
        await widget.create(name);
      }
      navigator.pop(true);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            _editing ? '$_titleCaseNoun updated.' : '$_titleCaseNoun added.',
          ),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return CrmSheet(
      eyebrow: _titleCaseNoun,
      title: _editing ? 'Edit ${widget.noun}' : 'Add ${widget.noun}',
      children: [
        if (_error != null) ...[
          ErrorBanner(message: _error!),
          const SizedBox(height: Spacing.md),
        ],
        CrmField(
          label: 'Name',
          child: TextField(
            controller: _name,
            enabled: !_busy,
            textCapitalization: TextCapitalization.words,
          ),
        ),
        if (_editing) ...[
          const SizedBox(height: Spacing.sm),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Active'),
            value: _isActive,
            onChanged: _busy ? null : (v) => setState(() => _isActive = v),
          ),
        ],
        const SizedBox(height: Spacing.lg),
        PrimaryButton(
          label: _editing ? 'Save changes' : 'Add',
          busy: _busy,
          onPressed: _busy ? null : _submit,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Reminders — which channels reminders may use at all
// ---------------------------------------------------------------------------

class _RemindersTab extends ConsumerStatefulWidget {
  const _RemindersTab();

  @override
  ConsumerState<_RemindersTab> createState() => _RemindersTabState();
}

class _RemindersTabState extends ConsumerState<_RemindersTab> {
  /// A local, editable copy. `PUT /settings/reminders` requires every field
  /// on each save, so all six travel together until "Save changes".
  ReminderSettings? _local;
  bool _saving = false;
  String? _error;

  void _seed(ReminderSettings settings) {
    _local ??= settings;
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      final s = _local!;
      final saved = await ref
          .read(adminServiceProvider)
          .updateReminderSettings(
            emailEnabled: s.emailEnabled,
            smsEnabled: s.smsEnabled,
            reminderSmsEnabled: s.reminderSmsEnabled,
            reminderEmailEnabled: s.reminderEmailEnabled,
            whatsappEnabled: s.whatsappEnabled,
            reminderWhatsappEnabled: s.reminderWhatsappEnabled,
          );
      if (mounted) {
        setState(() {
          _local = saved;
          _saving = false;
        });
        messenger.showSnackBar(
          const SnackBar(content: Text('Reminder settings saved.')),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(reminderSettingsProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return CrmAsyncView(
      value: settings,
      errorTitle: 'Could not load reminder settings',
      onRetry: () => ref.invalidate(reminderSettingsProvider),
      builder: (data) {
        _seed(data);
        final s = _local!;

        return RefreshIndicator(
          onRefresh: () async {
            _local = null;
            ref.invalidate(reminderSettingsProvider);
            await ref.read(reminderSettingsProvider.future);
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(Spacing.md),
            children: [
              if (_error != null) ...[
                ErrorBanner(message: _error!),
                const SizedBox(height: Spacing.md),
              ],
              const SectionHeader('System-wide notifications'),
              const SizedBox(height: Spacing.xs),
              Text(
                'Master switches — off, and nothing on that channel goes out '
                'at all (invoices, reminders, receipts).',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: Spacing.sm),
              CrmCardList(
                children: [
                  SwitchListTile(
                    title: const Text('Email'),
                    value: s.emailEnabled,
                    onChanged: (v) => setState(
                      () => _local = ReminderSettings(
                        emailEnabled: v,
                        smsEnabled: s.smsEnabled,
                        reminderSmsEnabled: s.reminderSmsEnabled,
                        reminderEmailEnabled: v ? s.reminderEmailEnabled : false,
                        whatsappEnabled: s.whatsappEnabled,
                        reminderWhatsappEnabled: s.reminderWhatsappEnabled,
                      ),
                    ),
                  ),
                  SwitchListTile(
                    title: const Text('SMS'),
                    value: s.smsEnabled,
                    onChanged: (v) => setState(
                      () => _local = ReminderSettings(
                        emailEnabled: s.emailEnabled,
                        smsEnabled: v,
                        reminderSmsEnabled: v ? s.reminderSmsEnabled : false,
                        reminderEmailEnabled: s.reminderEmailEnabled,
                        whatsappEnabled: s.whatsappEnabled,
                        reminderWhatsappEnabled: s.reminderWhatsappEnabled,
                      ),
                    ),
                  ),
                  SwitchListTile(
                    title: const Text('WhatsApp'),
                    value: s.whatsappEnabled,
                    onChanged: (v) => setState(
                      () => _local = ReminderSettings(
                        emailEnabled: s.emailEnabled,
                        smsEnabled: s.smsEnabled,
                        reminderSmsEnabled: s.reminderSmsEnabled,
                        reminderEmailEnabled: s.reminderEmailEnabled,
                        whatsappEnabled: v,
                        reminderWhatsappEnabled: v
                            ? s.reminderWhatsappEnabled
                            : false,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Spacing.lg),
              const SectionHeader('Automatic reminders'),
              const SizedBox(height: Spacing.xs),
              Text(
                'Lets the reminder cron use a channel for upcoming and '
                'overdue bills — needs the matching switch above turned on.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: Spacing.sm),
              CrmCardList(
                children: [
                  SwitchListTile(
                    title: const Text('Email reminders'),
                    value: s.reminderEmailEnabled,
                    onChanged: !s.emailEnabled
                        ? null
                        : (v) => setState(
                            () => _local = ReminderSettings(
                              emailEnabled: s.emailEnabled,
                              smsEnabled: s.smsEnabled,
                              reminderSmsEnabled: s.reminderSmsEnabled,
                              reminderEmailEnabled: v,
                              whatsappEnabled: s.whatsappEnabled,
                              reminderWhatsappEnabled: s.reminderWhatsappEnabled,
                            ),
                          ),
                  ),
                  SwitchListTile(
                    title: const Text('SMS reminders'),
                    value: s.reminderSmsEnabled,
                    onChanged: !s.smsEnabled
                        ? null
                        : (v) => setState(
                            () => _local = ReminderSettings(
                              emailEnabled: s.emailEnabled,
                              smsEnabled: s.smsEnabled,
                              reminderSmsEnabled: v,
                              reminderEmailEnabled: s.reminderEmailEnabled,
                              whatsappEnabled: s.whatsappEnabled,
                              reminderWhatsappEnabled: s.reminderWhatsappEnabled,
                            ),
                          ),
                  ),
                  SwitchListTile(
                    title: const Text('WhatsApp reminders'),
                    value: s.reminderWhatsappEnabled,
                    onChanged: !s.whatsappEnabled
                        ? null
                        : (v) => setState(
                            () => _local = ReminderSettings(
                              emailEnabled: s.emailEnabled,
                              smsEnabled: s.smsEnabled,
                              reminderSmsEnabled: s.reminderSmsEnabled,
                              reminderEmailEnabled: s.reminderEmailEnabled,
                              whatsappEnabled: s.whatsappEnabled,
                              reminderWhatsappEnabled: v,
                            ),
                          ),
                  ),
                ],
              ),
              const SizedBox(height: Spacing.lg),
              PrimaryButton(
                label: _saving ? 'Saving…' : 'Save changes',
                busy: _saving,
                onPressed: _saving ? null : _save,
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Templates — the message bodies reminders/invoices send
// ---------------------------------------------------------------------------

class _TemplatesTab extends ConsumerStatefulWidget {
  const _TemplatesTab();

  @override
  ConsumerState<_TemplatesTab> createState() => _TemplatesTabState();
}

class _TemplatesTabState extends ConsumerState<_TemplatesTab> {
  final _footer = TextEditingController();
  final _invoiceSubject = TextEditingController();
  final _invoiceBody = TextEditingController();
  final _reminderSubject = TextEditingController();
  final _reminderBody = TextEditingController();
  final _overdueSubject = TextEditingController();
  final _overdueBody = TextEditingController();
  final _reminderSms = TextEditingController();
  final _overdueSms = TextEditingController();

  bool _seeded = false;
  bool _saving = false;
  String? _error;

  static const _smsCap = 160;
  static const _footerCap = 500;

  void _seed(MessageTemplates t) {
    if (_seeded) return;
    _seeded = true;
    _footer.text = t.emailFooterText ?? '';
    _invoiceSubject.text = t.invoiceEmailSubject ?? '';
    _invoiceBody.text = t.invoiceEmailBody ?? '';
    _reminderSubject.text = t.reminderEmailSubject ?? '';
    _reminderBody.text = t.reminderEmailBody ?? '';
    _overdueSubject.text = t.overdueEmailSubject ?? '';
    _overdueBody.text = t.overdueEmailBody ?? '';
    _reminderSms.text = t.reminderSmsBody ?? '';
    _overdueSms.text = t.overdueSmsBody ?? '';
  }

  @override
  void dispose() {
    _footer.dispose();
    _invoiceSubject.dispose();
    _invoiceBody.dispose();
    _reminderSubject.dispose();
    _reminderBody.dispose();
    _overdueSubject.dispose();
    _overdueBody.dispose();
    _reminderSms.dispose();
    _overdueSms.dispose();
    super.dispose();
  }

  String? _blankToNull(String value) => value.trim().isEmpty ? null : value;

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      final saved = await ref
          .read(adminServiceProvider)
          .updateTemplates(
            MessageTemplates(
              reminderEmailSubject: _blankToNull(_reminderSubject.text),
              reminderEmailBody: _blankToNull(_reminderBody.text),
              overdueEmailSubject: _blankToNull(_overdueSubject.text),
              overdueEmailBody: _blankToNull(_overdueBody.text),
              reminderSmsBody: _blankToNull(_reminderSms.text),
              overdueSmsBody: _blankToNull(_overdueSms.text),
              invoiceEmailSubject: _blankToNull(_invoiceSubject.text),
              invoiceEmailBody: _blankToNull(_invoiceBody.text),
              emailFooterText: _blankToNull(_footer.text),
            ),
          );
      if (!mounted) return;
      setState(() {
        _seeded = false;
        _saving = false;
      });
      _seed(saved);
      messenger.showSnackBar(const SnackBar(content: Text('Templates saved.')));
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final templates = ref.watch(messageTemplatesProvider);

    return CrmAsyncView(
      value: templates,
      errorTitle: 'Could not load templates',
      onRetry: () => ref.invalidate(messageTemplatesProvider),
      builder: (data) {
        _seed(data);
        return ListView(
          padding: const EdgeInsets.all(Spacing.md),
          children: [
            if (_error != null) ...[
              ErrorBanner(message: _error!),
              const SizedBox(height: Spacing.md),
            ],
            const SectionHeader('Email branding'),
            const SizedBox(height: Spacing.sm),
            CrmField(
              label: 'Email footer text',
              child: TextField(
                controller: _footer,
                maxLines: 3,
                maxLength: _footerCap,
                decoration: const InputDecoration(
                  hintText: 'Leave blank for the default copyright line',
                ),
              ),
            ),
            const SizedBox(height: Spacing.lg),
            const SectionHeader('Invoice / quote email'),
            const SizedBox(height: Spacing.sm),
            CrmField(
              label: 'Subject',
              child: TextField(controller: _invoiceSubject),
            ),
            const SizedBox(height: Spacing.md),
            CrmField(
              label: 'Body',
              child: TextField(controller: _invoiceBody, maxLines: 5),
            ),
            const SizedBox(height: Spacing.lg),
            const SectionHeader('Bill reminder email'),
            const SizedBox(height: Spacing.sm),
            CrmField(
              label: 'Due reminder — subject',
              child: TextField(controller: _reminderSubject),
            ),
            const SizedBox(height: Spacing.md),
            CrmField(
              label: 'Due reminder — body',
              child: TextField(controller: _reminderBody, maxLines: 4),
            ),
            const SizedBox(height: Spacing.md),
            CrmField(
              label: 'Overdue — subject',
              child: TextField(controller: _overdueSubject),
            ),
            const SizedBox(height: Spacing.md),
            CrmField(
              label: 'Overdue — body',
              child: TextField(controller: _overdueBody, maxLines: 4),
            ),
            const SizedBox(height: Spacing.lg),
            const SectionHeader('SMS templates'),
            const SizedBox(height: Spacing.sm),
            CrmField(
              label: 'Due reminder SMS',
              child: TextField(
                controller: _reminderSms,
                maxLines: 3,
                maxLength: _smsCap,
              ),
            ),
            const SizedBox(height: Spacing.md),
            CrmField(
              label: 'Overdue SMS',
              child: TextField(
                controller: _overdueSms,
                maxLines: 3,
                maxLength: _smsCap,
              ),
            ),
            const SizedBox(height: Spacing.lg),
            PrimaryButton(
              label: _saving ? 'Saving…' : 'Save changes',
              busy: _saving,
              onPressed: _saving ? null : _save,
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Payment methods — the repeatable card editor
// ---------------------------------------------------------------------------

/// One free-form key/value row under a payment method — "Paybill" → "123456".
class _EditableDetail {
  _EditableDetail({String key = '', String value = ''})
    : keyController = TextEditingController(text: key),
      valueController = TextEditingController(text: value);

  final TextEditingController keyController;
  final TextEditingController valueController;

  void dispose() {
    keyController.dispose();
    valueController.dispose();
  }
}

/// One payment method being edited locally — nothing here reaches the server
/// until the whole list is saved, matching `PUT /settings/payment-methods`
/// replacing the list on file wholesale.
class _EditableMethod {
  _EditableMethod({
    String label = '',
    String value = '',
    List<(String, String)> details = const [],
  }) : labelController = TextEditingController(text: label),
       valueController = TextEditingController(text: value),
       details = [
         for (final (k, v) in details) _EditableDetail(key: k, value: v),
       ];

  final TextEditingController labelController;
  final TextEditingController valueController;
  final List<_EditableDetail> details;

  PaymentMethodEntry toEntry() => PaymentMethodEntry(
    value: valueController.text.trim(),
    label: labelController.text.trim(),
    details: [
      for (final d in details)
        if (d.keyController.text.trim().isNotEmpty)
          (d.keyController.text.trim(), d.valueController.text.trim()),
    ],
  );

  void dispose() {
    labelController.dispose();
    valueController.dispose();
    for (final d in details) {
      d.dispose();
    }
  }
}

class _PaymentMethodsTab extends ConsumerStatefulWidget {
  const _PaymentMethodsTab();

  @override
  ConsumerState<_PaymentMethodsTab> createState() => _PaymentMethodsTabState();
}

class _PaymentMethodsTabState extends ConsumerState<_PaymentMethodsTab> {
  List<_EditableMethod>? _methods;
  bool _saving = false;
  String? _error;

  void _seed(PaymentMethodsSettings settings) {
    if (_methods != null) return;
    _methods = [
      for (final m in settings.methods)
        _EditableMethod(label: m.label, value: m.value, details: m.details),
    ];
  }

  @override
  void dispose() {
    for (final m in _methods ?? const <_EditableMethod>[]) {
      m.dispose();
    }
    super.dispose();
  }

  void _addMethod() => setState(() => _methods!.add(_EditableMethod()));

  void _removeMethod(int index) => setState(() {
    _methods!.removeAt(index).dispose();
  });

  void _addDetail(int methodIndex) =>
      setState(() => _methods![methodIndex].details.add(_EditableDetail()));

  void _removeDetail(int methodIndex, int detailIndex) => setState(() {
    _methods![methodIndex].details.removeAt(detailIndex).dispose();
  });

  Future<void> _save() async {
    final methods = _methods!;
    if (methods.isEmpty) {
      setState(() => _error = 'Add at least one payment method.');
      return;
    }
    for (final m in methods) {
      if (m.labelController.text.trim().isEmpty ||
          m.valueController.text.trim().isEmpty) {
        setState(() => _error = 'Every method needs a name and a key.');
        return;
      }
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(adminServiceProvider)
          .updatePaymentMethods([for (final m in methods) m.toEntry()]);
      if (mounted) {
        setState(() => _saving = false);
        messenger.showSnackBar(
          const SnackBar(content: Text('Payment methods saved.')),
        );
      }
      ref.invalidate(paymentMethodsSettingsProvider);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(paymentMethodsSettingsProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return CrmAsyncView(
      value: settings,
      errorTitle: 'Could not load payment methods',
      onRetry: () => ref.invalidate(paymentMethodsSettingsProvider),
      builder: (data) {
        _seed(data);
        final methods = _methods!;

        return ListView(
          padding: const EdgeInsets.all(Spacing.md),
          children: [
            Text(
              'Details (an account number, a paybill) appear on invoices '
              'exactly as entered here.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Spacing.md),
            if (_error != null) ...[
              ErrorBanner(message: _error!),
              const SizedBox(height: Spacing.md),
            ],
            if (methods.isEmpty)
              const Card(
                child: StateMessage(
                  icon: Icons.payments_outlined,
                  title: 'No payment methods',
                  message: 'Add at least one so clients know how to pay you.',
                ),
              )
            else
              for (final (i, method) in methods.indexed) ...[
                Card(
                  child: ExpansionTile(
                    title: Text(
                      method.labelController.text.isEmpty
                          ? 'New method'
                          : method.labelController.text,
                      style: theme.textTheme.titleSmall,
                    ),
                    subtitle: Text(
                      '${method.details.length} '
                      'detail${method.details.length == 1 ? '' : 's'}',
                    ),
                    childrenPadding: const EdgeInsets.fromLTRB(
                      Spacing.md,
                      0,
                      Spacing.md,
                      Spacing.md,
                    ),
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: CrmField(
                              label: 'Display name',
                              child: TextField(
                                controller: method.labelController,
                                decoration: const InputDecoration(
                                  hintText: 'e.g. M-Pesa',
                                ),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                          ),
                          const SizedBox(width: Spacing.sm),
                          Expanded(
                            child: CrmField(
                              label: 'Key',
                              child: TextField(
                                controller: method.valueController,
                                decoration: const InputDecoration(
                                  hintText: 'e.g. mpesa',
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: Spacing.sm),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'PAYMENT DETAILS',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          TextButton.icon(
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('Add detail'),
                            onPressed: () => _addDetail(i),
                          ),
                        ],
                      ),
                      for (final (di, detail) in method.details.indexed)
                        Padding(
                          padding: const EdgeInsets.only(bottom: Spacing.sm),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: detail.keyController,
                                  decoration: const InputDecoration(
                                    hintText: 'Field (e.g. Account number)',
                                  ),
                                ),
                              ),
                              const SizedBox(width: Spacing.sm),
                              Expanded(
                                child: TextField(
                                  controller: detail.valueController,
                                  decoration: const InputDecoration(
                                    hintText: 'Value',
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: Icon(
                                  Icons.delete_outline,
                                  size: 18,
                                  color: scheme.error,
                                ),
                                onPressed: () => _removeDetail(i, di),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: Spacing.sm),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          icon: Icon(
                            Icons.delete_outline,
                            size: 16,
                            color: methods.length > 1 ? scheme.error : null,
                          ),
                          label: Text(
                            'Remove method',
                            style: TextStyle(
                              color: methods.length > 1 ? scheme.error : null,
                            ),
                          ),
                          onPressed: methods.length > 1
                              ? () => _removeMethod(i)
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Spacing.sm),
              ],
            OutlinedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Add payment method'),
              onPressed: _addMethod,
            ),
            const SizedBox(height: Spacing.lg),
            PrimaryButton(
              label: _saving ? 'Saving…' : 'Save changes',
              busy: _saving,
              onPressed: _saving ? null : _save,
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Late fee — enable/percent/days, plus the revert danger zone
// ---------------------------------------------------------------------------

class _LateFeeTab extends ConsumerStatefulWidget {
  const _LateFeeTab();

  @override
  ConsumerState<_LateFeeTab> createState() => _LateFeeTabState();
}

class _LateFeeTabState extends ConsumerState<_LateFeeTab> {
  bool? _enabled;
  final _percent = TextEditingController();
  final _days = TextEditingController();
  bool _saving = false;
  String? _error;

  int? _affectedCount;
  bool _loadingCount = false;
  bool _reverting = false;

  void _seed(LateFeeSettings settings) {
    if (_enabled != null) return;
    _enabled = settings.enabled;
    _percent.text = Formatting.amount(settings.percent);
    _days.text = settings.days.toString();
    _loadAffectedCount();
  }

  Future<void> _loadAffectedCount() async {
    setState(() => _loadingCount = true);
    try {
      final count = await ref.read(adminServiceProvider).lateFeeAffectedCount();
      if (mounted) setState(() => _affectedCount = count);
    } on ApiException catch (_) {
      // The revert card just stays hidden without a count; the settings
      // form above still works.
    } finally {
      if (mounted) setState(() => _loadingCount = false);
    }
  }

  @override
  void dispose() {
    _percent.dispose();
    _days.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final percent = double.tryParse(_percent.text.trim().replaceAll(',', ''));
    final days = int.tryParse(_days.text.trim());
    String? complaint;
    if (percent == null || percent <= 0 || percent > 100) {
      complaint = 'Enter a percentage between 0 and 100.';
    } else if (days == null || days < 1) {
      complaint = 'Enter at least 1 day.';
    }
    if (complaint != null) {
      setState(() => _error = complaint);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      final saved = await ref
          .read(adminServiceProvider)
          .updateLateFeeSettings(
            enabled: _enabled!,
            percent: percent!,
            days: days!,
          );
      if (mounted) {
        setState(() {
          _enabled = saved.enabled;
          _percent.text = Formatting.amount(saved.percent);
          _days.text = saved.days.toString();
          _saving = false;
        });
        messenger.showSnackBar(
          const SnackBar(content: Text('Late fee settings saved.')),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.message;
        });
      }
    }
  }

  Future<void> _confirmRevert() async {
    final count = _affectedCount ?? 0;
    var updateTotals = true;

    final sure = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Remove late fees from invoices?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This removes the late fee line item from $count unpaid '
                'invoice${count == 1 ? '' : 's'} (sent, overdue, or partial) '
                'and resets their overdue escalation stage. Paid and '
                'cancelled invoices are not affected.\n\n'
                'This cannot be undone — late fees are re-applied by the '
                'next nightly run if they are still enabled.',
              ),
              const SizedBox(height: Spacing.md),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Update invoice totals'),
                subtitle: const Text(
                  'Off leaves the charged total unchanged and only removes '
                  'the line item.',
                ),
                value: updateTotals,
                onChanged: (v) => setDialogState(() => updateTotals = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogContext).colorScheme.error,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Remove late fees'),
            ),
          ],
        ),
      ),
    );
    if (sure != true || !mounted) return;

    setState(() => _reverting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final message = await ref
          .read(adminServiceProvider)
          .revertLateFee(updateTotals: updateTotals);
      messenger.showSnackBar(
        SnackBar(content: Text(message ?? 'Late fees removed.')),
      );
      await _loadAffectedCount();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _reverting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(lateFeeSettingsProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return CrmAsyncView(
      value: settings,
      errorTitle: 'Could not load late fee settings',
      onRetry: () => ref.invalidate(lateFeeSettingsProvider),
      builder: (data) {
        _seed(data);
        final enabled = _enabled!;

        return ListView(
          padding: const EdgeInsets.all(Spacing.md),
          children: [
            const SectionHeader('Late fee automation'),
            const SizedBox(height: Spacing.xs),
            Text(
              'When enabled, a late fee line item is added automatically to '
              'overdue invoices by the nightly automation.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Spacing.sm),
            if (_error != null) ...[
              ErrorBanner(message: _error!),
              const SizedBox(height: Spacing.md),
            ],
            Card(
              child: Padding(
                padding: const EdgeInsets.all(Spacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Enable late fees'),
                      value: enabled,
                      onChanged: (v) => setState(() => _enabled = v),
                    ),
                    const SizedBox(height: Spacing.sm),
                    CrmField(
                      label: 'Late fee percentage',
                      child: TextField(
                        controller: _percent,
                        enabled: enabled,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(suffixText: '%'),
                      ),
                    ),
                    const SizedBox(height: Spacing.md),
                    CrmField(
                      label: 'Apply after (days overdue)',
                      child: TextField(
                        controller: _days,
                        enabled: enabled,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(suffixText: 'days'),
                      ),
                    ),
                    const SizedBox(height: Spacing.lg),
                    PrimaryButton(
                      label: _saving ? 'Saving…' : 'Save changes',
                      busy: _saving,
                      onPressed: _saving ? null : _save,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: Spacing.lg),
            const SectionHeader('Danger zone'),
            const SizedBox(height: Spacing.sm),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(Spacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Remove late fees from invoices',
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: Spacing.xs),
                    Text(
                      'Strips the late fee line from unpaid invoices. Paid '
                      'and cancelled invoices are skipped.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: Spacing.md),
                    if (_loadingCount)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: Spacing.sm),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    else ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${_affectedCount ?? 0} invoice'
                            '${(_affectedCount ?? 0) == 1 ? '' : 's'} affected',
                            style: theme.textTheme.bodyMedium,
                          ),
                          OutlinedButton.icon(
                            icon: Icon(
                              Icons.delete_outline,
                              size: 18,
                              color: scheme.error,
                            ),
                            label: Text(
                              'Remove',
                              style: TextStyle(color: scheme.error),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(
                                color: scheme.error.withValues(alpha: 0.4),
                              ),
                            ),
                            onPressed:
                                (_affectedCount ?? 0) == 0 || _reverting
                                ? null
                                : _confirmRevert,
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Private building blocks (candidates for mobilling_ui)
// ---------------------------------------------------------------------------
