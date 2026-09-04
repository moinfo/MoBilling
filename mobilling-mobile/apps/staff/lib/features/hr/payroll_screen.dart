import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';
import 'package:share_plus/share_plus.dart';

import '../../providers.dart';
import '../common/pickers.dart';
import '../common/share_pdf.dart';
import '../crm/crm_ui.dart'
    show
        CrmAsyncView,
        CrmCardList,
        CrmField,
        CrmMetaLine,
        CrmPickerField,
        CrmSheet,
        CrmStatusLine,
        showCrmSheet;
import 'hr_providers.dart';
import 'payroll_catalog_screens.dart';
import 'payroll_settings_screen.dart';

/// Payroll on a phone: the monthly runs, who earns what, the allowance,
/// deduction and statutory-rate catalogs and who is assigned to each, PAYE
/// bracket and exemption settings, loans and advances, and every employee's
/// own payslips.
class PayrollScreen extends ConsumerWidget {
  const PayrollScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(sessionControllerProvider).session;
    final canManage = auth?.can(HrPermissions.payrollManage) ?? false;
    final canView =
        canManage || (auth?.can(HrPermissions.payrollView) ?? false);

    final tabs = <(String, Widget)>[
      if (canView) ('Runs', const _RunsTab()),
      if (canManage) ('Salaries', const _SalariesTab()),
      if (canView)
        (
          'Allowances',
          PayComponentCatalogTab(
            kind: PayComponentKind.allowance,
            canManage: canManage,
          ),
        ),
      if (canView)
        (
          'Deductions',
          PayComponentCatalogTab(
            kind: PayComponentKind.deduction,
            canManage: canManage,
          ),
        ),
      if (canView)
        ('Statutory rates', StatutoryRateCatalogTab(canManage: canManage)),
      if (canView) ('Settings', PayrollSettingsTab(canManage: canManage)),
      if (canManage) ('Loans', const _LoansTab()),
      ('My payslips', const _MyPayslipsTab()),
    ];

    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: ShellTopBar(
          eyebrow: 'HR',
          title: 'Payroll',
          // Payroll has four things you can add and they belong to different
          // tabs. One "+" that names all four keeps the masthead honest
          // whichever tab is being read, instead of a button that changes
          // meaning as you swipe.
          trailing: canManage
              ? InkActionButton(
                  icon: Icons.add_rounded,
                  tooltip: 'Add to payroll',
                  onPressed: () => _addRecord(context, ref),
                )
              : null,
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

// ---------------------------------------------------------------------------
// The masthead's one create action
// ---------------------------------------------------------------------------

/// The four records payroll can gain, each with the sentence that says what
/// it does — the same words the tabs' empty states use.
Future<void> _addRecord(BuildContext context, WidgetRef ref) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
    builder: (context) {
      final theme = Theme.of(context);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Spacing.lg,
            0,
            Spacing.lg,
            Spacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'PAYROLL',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: Spacing.xs),
              Text(
                'Add to payroll',
                style: Type.display(22, color: theme.colorScheme.onSurface),
              ),
              const SizedBox(height: Spacing.md),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.play_arrow_outlined),
                title: const Text('Generate a month'),
                subtitle: const Text(
                  'A draft payslip for every employee with a salary on file.',
                ),
                onTap: () => Navigator.pop(context, 'generate'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.account_balance_wallet_outlined),
                title: const Text('Set a basic salary'),
                subtitle: const Text(
                  'Employees without one are skipped when payroll runs.',
                ),
                onTap: () => Navigator.pop(context, 'salary'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.request_quote_outlined),
                title: const Text('New loan'),
                subtitle: const Text(
                  'Repaid in monthly instalments via payroll.',
                ),
                onTap: () => Navigator.pop(context, 'loan'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.fast_forward_outlined),
                title: const Text('New salary advance'),
                subtitle: const Text('Recovered in full from one month.'),
                onTap: () => Navigator.pop(context, 'advance'),
              ),
            ],
          ),
        ),
      );
    },
  );
  // A dismissed sheet returns null; only a named choice goes on.
  if (choice == null || !context.mounted) return;
  if (choice == 'generate') {
    await _generate(context, ref);
    return;
  }

  final kind = switch (choice) {
    'salary' => _MoneyFormKind.salary,
    'loan' => _MoneyFormKind.loan,
    _ => _MoneyFormKind.advance,
  };
  final saved = await showCrmSheet<bool>(
    context: context,
    builder: (_) => _MoneyFormSheet(kind: kind),
  );
  if (!(saved ?? false)) return;
  if (kind == _MoneyFormKind.salary) {
    ref.invalidate(salariesProvider);
  } else {
    ref.invalidate(loansProvider);
    ref.invalidate(salaryAdvancesProvider);
  }
}

Future<void> _generate(BuildContext context, WidgetRef ref) async {
  final monthKey = await _pickMonth(context, title: 'Generate payroll for');
  if (monthKey == null || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  try {
    final message = await ref
        .read(hrServiceProvider)
        .generatePayrollRun(monthKey);
    ref.invalidate(payrollRunsProvider);
    messenger.showSnackBar(
      SnackBar(content: Text(message ?? 'Payroll generated.')),
    );
  } on ApiException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  }
}

// ---------------------------------------------------------------------------
// Runs
// ---------------------------------------------------------------------------

/// Every payroll month as one card of rows: the month as the title, the
/// draft/finalized chip beside the payslip count, and the way in on the right.
class _RunsTab extends ConsumerWidget {
  const _RunsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runs = ref.watch(payrollRunsProvider);
    final theme = Theme.of(context);
    final status = context.statusColors;

    return CrmAsyncView(
      value: runs,
      errorTitle: 'Could not load payroll runs',
      onRetry: () => ref.invalidate(payrollRunsProvider),
      builder: (list) => RefreshIndicator(
        onRefresh: () => ref.refresh(payrollRunsProvider.future),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(Spacing.md),
          children: [
            if (list.isEmpty)
              const SizedBox(
                height: 320,
                child: StateMessage(
                  icon: Icons.account_balance_outlined,
                  title: 'No payroll runs yet',
                  message:
                      'Generate a month to create a payslip for every employee '
                      'with a salary on file.',
                ),
              )
            else
              Reveal(
                child: CrmCardList(
                  children: [
                    for (final run in list)
                      ListTile(
                        leading: Icon(
                          run.isFinalized
                              ? Icons.lock_outline
                              : Icons.edit_note_outlined,
                          color: run.isFinalized
                              ? status.settled
                              : status.pending,
                        ),
                        title: Text(
                          _monthLabel(run.monthKey),
                          style: theme.textTheme.titleSmall,
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: CrmStatusLine(
                            status: run.isFinalized ? 'finalized' : 'draft',
                            meta: _runMeta(run),
                          ),
                        ),
                        trailing: Icon(
                          Icons.chevron_right,
                          color: theme.colorScheme.outline,
                        ),
                        onTap: () => context.push('/payroll/runs/${run.id}'),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: Spacing.xl),
          ],
        ),
      ),
    );
  }
}

/// `12 payslips · finalized 31 Aug 2026` — the run's own history, as the
/// mono metadata line every list here carries.
String _runMeta(PayrollRun run) => [
  '${run.payslipsCount} payslip${run.payslipsCount == 1 ? '' : 's'}',
  if (run.finalizedAt != null)
    'finalized ${Formatting.date(run.finalizedAt)}'
  else if (run.generatedAt != null)
    'generated ${Formatting.date(run.generatedAt)}',
].join(' · ');

/// One payroll run: totals, the payslips, and the draft → finalized step.
class PayrollRunScreen extends ConsumerWidget {
  const PayrollRunScreen({super.key, required this.runId});

  final String runId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final run = ref.watch(payrollRunProvider(runId));
    final canManage =
        ref
            .watch(sessionControllerProvider)
            .session
            ?.can(HrPermissions.payrollManage) ??
        false;
    final theme = Theme.of(context);
    final loaded = run.valueOrNull;

    return Scaffold(
      appBar: ShellTopBar(
        eyebrow: 'Payroll',
        title: loaded == null ? 'Payroll run' : _monthLabel(loaded.monthKey),
        trailing: canManage && (loaded?.isDraft ?? false)
            ? InkActionButton(
                icon: Icons.more_horiz_rounded,
                tooltip: 'Run actions',
                onPressed: () => _showActions(context, ref, loaded!),
              )
            : null,
      ),
      body: CrmAsyncView(
        value: run,
        errorTitle: 'Could not load this run',
        onRetry: () => ref.invalidate(payrollRunProvider(runId)),
        builder: (data) => RefreshIndicator(
          onRefresh: () => ref.refresh(payrollRunProvider(runId).future),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(Spacing.md),
            children: [
              // The one figure this screen is about: what the month costs in
              // pay. Employer cost and the head count explain it beneath a
              // rule, as figures rather than as a sentence.
              Reveal(child: _RunTotalsCard(run: data)),
              if (canManage && data.isDraft) ...[
                const SizedBox(height: Spacing.md),
                Reveal(
                  delay: const Duration(milliseconds: 80),
                  child: PrimaryButton(
                    label: 'Finalize run',
                    icon: Icons.lock_outline,
                    onPressed: data.payslips.isEmpty
                        ? null
                        : () => _act(context, ref, data, 'finalize'),
                  ),
                ),
                const SizedBox(height: Spacing.sm),
                Text(
                  'Finalizing locks the payslips and collects loan '
                  'instalments and salary advances. It cannot be undone.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: Spacing.lg),
              SectionHeader(
                'Payslips',
                trailing: Text(
                  Formatting.integer(data.payslips.length),
                  style: theme.textTheme.labelSmall,
                ),
              ),
              const SizedBox(height: Spacing.sm),
              if (data.payslips.isEmpty)
                const Card(
                  child: StateMessage(
                    icon: Icons.receipt_long_outlined,
                    title: 'No payslips',
                    message:
                        'No active employee has a salary on file, so there was '
                        'nothing to pay.',
                  ),
                )
              else
                CrmCardList(
                  children: [
                    for (final slip in data.payslips)
                      ListTile(
                        dense: true,
                        title: Text(
                          slip.userName,
                          style: theme.textTheme.titleSmall,
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: CrmMetaLine(
                            'Gross ${Formatting.currency(slip.grossPay)}',
                          ),
                        ),
                        trailing: Money(slip.netPay, showCode: false),
                        onTap: () => showPayslipSheet(
                          context,
                          slip,
                          monthKey: data.monthKey,
                          finalized: data.isFinalized,
                          fetchPdf: () =>
                              ref.read(hrServiceProvider).payslipPdf(slip.id),
                        ),
                      ),
                  ],
                ),
              if (data.payslips.isNotEmpty) ...[
                const SizedBox(height: Spacing.lg),
                const SectionHeader('Employer obligations'),
                const SizedBox(height: Spacing.sm),
                _EmployerObligationsCard(payslips: data.payslips),
                const SizedBox(height: Spacing.lg),
                SectionHeader(
                  'Net salary payment list',
                  trailing: IconButton(
                    icon: const Icon(Icons.ios_share_rounded, size: 18),
                    tooltip: 'Share as text',
                    onPressed: () => _shareNetSalaryList(data),
                  ),
                ),
                const SizedBox(height: Spacing.sm),
                CrmCardList(
                  children: [
                    for (final slip in data.payslips)
                      ListTile(
                        dense: true,
                        title: Text(
                          slip.userName,
                          style: theme.textTheme.titleSmall,
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: CrmMetaLine(
                            slip.hasBankDetails
                                ? '${slip.bankName} · ${slip.bankAccountNumber}'
                                : 'No bank details on file',
                          ),
                        ),
                        trailing: Money(slip.netPay, showCode: false),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: Spacing.xl),
            ],
          ),
        ),
      ),
    );
  }

  /// Plain-text rows a bank's bulk-payment tool can be fed — name, bank,
  /// account, amount — one employee per line.
  void _shareNetSalaryList(PayrollRun run) {
    final lines = [
      'Net salary payment list — ${_monthLabel(run.monthKey)}',
      '',
      for (final slip in run.payslips)
        '${slip.userName}\t'
            '${slip.bankName ?? 'No bank on file'}\t'
            '${slip.bankAccountNumber ?? '—'}\t'
            '${Formatting.currency(slip.netPay)}',
    ];
    Share.share(lines.join('\n'));
  }

  /// The draft-only actions, as a sheet rather than an overflow menu — the
  /// masthead is ink, and a popup menu on it reads as a foreign control.
  Future<void> _showActions(
    BuildContext context,
    WidgetRef ref,
    PayrollRun run,
  ) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
      builder: (context) {
        final theme = Theme.of(context);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.lg,
              0,
              Spacing.lg,
              Spacing.lg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _monthLabel(run.monthKey).toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: Spacing.xs),
                Text(
                  'Run actions',
                  style: Type.display(22, color: theme.colorScheme.onSurface),
                ),
                const SizedBox(height: Spacing.md),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.refresh_rounded),
                  title: const Text('Regenerate payslips'),
                  subtitle: const Text(
                    'Rebuilt from the current salaries, allowances and '
                    'deductions.',
                  ),
                  onTap: () => Navigator.pop(context, 'regenerate'),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.delete_outline,
                    color: theme.colorScheme.error,
                  ),
                  title: const Text('Delete draft run'),
                  subtitle: const Text('The month can be generated again.'),
                  onTap: () => Navigator.pop(context, 'delete'),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (action == null || !context.mounted) return;
    await _act(context, ref, run, action);
  }

  Future<void> _act(
    BuildContext context,
    WidgetRef ref,
    PayrollRun run,
    String action,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final service = ref.read(hrServiceProvider);

    final (title, body, verb) = switch (action) {
      'finalize' => (
        'Finalize ${_monthLabel(run.monthKey)}?',
        'Payslips become payroll history and loan/advance recoveries are collected. This cannot be undone.',
        'Finalize',
      ),
      'delete' => (
        'Delete this draft run?',
        'All ${run.payslips.length} payslips in it are discarded. You can generate the month again later.',
        'Delete',
      ),
      _ => (
        'Regenerate payslips?',
        'Existing draft payslips are replaced using the current salaries, allowances and deductions.',
        'Regenerate',
      ),
    };

    final confirmed = await showDialog<bool>(
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
            child: Text(verb),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false) || !context.mounted) return;

    try {
      switch (action) {
        case 'finalize':
          await service.finalizePayrollRun(run.id);
          messenger.showSnackBar(
            const SnackBar(content: Text('Payroll finalized.')),
          );
        case 'delete':
          await service.deletePayrollRun(run.id);
          messenger.showSnackBar(
            const SnackBar(content: Text('Draft deleted.')),
          );
          if (context.mounted) context.pop();
        default:
          final message = await service.generatePayrollRun(run.monthKey);
          messenger.showSnackBar(
            SnackBar(content: Text(message ?? 'Payslips regenerated.')),
          );
      }
      ref.invalidate(payrollRunsProvider);
      ref.invalidate(payrollRunProvider(run.id));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

/// The run's hero: net pay at display scale, with the state of the run and
/// who put it there set as the eyebrow above it.
class _RunTotalsCard extends StatelessWidget {
  const _RunTotalsCard({required this.run});

  final PayrollRun run;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final eyebrow = theme.textTheme.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text('NET PAY', style: eyebrow)),
                StatusChip(run.isFinalized ? 'finalized' : 'draft'),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Money(run.netPayTotal, scale: MoneyScale.display),
            ),
            const Divider(height: Spacing.lg + Spacing.sm),
            Row(
              children: [
                Expanded(
                  child: _Figure(
                    label: 'Employer cost',
                    amount: run.employerCostTotal,
                  ),
                ),
                const SizedBox(width: Spacing.md),
                Expanded(
                  child: _Count(
                    label: 'Payslips',
                    value: Formatting.integer(run.payslipsCount),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              (run.isFinalized
                      ? 'Finalized by ${run.finalizedBy?.name ?? '—'} · ${Formatting.date(run.finalizedAt)}'
                      : 'Generated by ${run.generatedBy?.name ?? '—'} · ${Formatting.date(run.generatedAt)}')
                  .toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: eyebrow,
            ),
          ],
        ),
      ),
    );
  }
}

/// What the tenant owes on top of net pay: each statutory rate's employer
/// share, grouped by name across every payslip in the run, plus the PAYE
/// total due to the tax authority.
class _EmployerObligationsCard extends StatelessWidget {
  const _EmployerObligationsCard({required this.payslips});

  final List<Payslip> payslips;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final byName = <String, double>{};
    for (final slip in payslips) {
      for (final line in slip.statutoryEmployerBreakdown) {
        byName[line.name] = (byName[line.name] ?? 0) + line.amount;
      }
    }
    final payeTotal = payslips.fold<double>(0, (sum, s) => sum + s.payeAmount);
    final employerTotal = payslips.fold<double>(
      0,
      (sum, s) => sum + s.statutoryEmployerTotal,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final entry in byName.entries) ...[
              _ObligationRow(label: '${entry.key} (employer)', amount: entry.value),
              const SizedBox(height: Spacing.sm),
            ],
            _ObligationRow(label: 'PAYE to remit', amount: payeTotal),
            const Divider(height: Spacing.lg + Spacing.sm),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'TOTAL EMPLOYER OBLIGATIONS',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Money(employerTotal + payeTotal, showCode: false),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ObligationRow extends StatelessWidget {
  const _ObligationRow({required this.label, required this.amount});

  final String label;
  final double amount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
        Money(amount, showCode: false, scale: MoneyScale.dense),
      ],
    );
  }
}

/// A labelled row-scale figure inside a card.
class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.amount});

  final String label;
  final Object? amount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: Spacing.xs),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Money(amount, showCode: false),
        ),
      ],
    );
  }
}

/// A [_Figure] whose value is a count — matched to the money readout by
/// construction so the two sit at the same weight side by side.
class _Count extends StatelessWidget {
  const _Count({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: Spacing.xs),
        Text(
          value,
          style: TextStyle(
            fontFamily: Type.family,
            fontSize: MoneyScale.row.size,
            fontWeight: FontWeight.w700,
            letterSpacing: MoneyScale.row.size * -0.02,
            height: 1,
            color: theme.colorScheme.onSurface,
            fontFeatures: Type.figures,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// The payslip
// ---------------------------------------------------------------------------

/// A payslip's full breakdown, with the PDF one tap away.
///
/// Net pay is the hero; everything below it is the arithmetic that produced
/// it, grouped under the same section rules the rest of the app uses so a
/// long column of figures still has a shape.
Future<void> showPayslipSheet(
  BuildContext context,
  Payslip slip, {
  required String monthKey,
  required bool finalized,
  required Future<Uint8List> Function() fetchPdf,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
    builder: (context) {
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;

      /// One group of breakdown lines on its own card, under its own rule.
      /// Hidden entirely when the section is empty and worth nothing, as
      /// before — a payslip should not list what it did not charge.
      List<Widget> section(
        String title,
        List<BreakdownLine> lines,
        double total,
      ) {
        if (lines.isEmpty && total == 0) return const [];
        return [
          const SizedBox(height: Spacing.lg),
          SectionHeader(title),
          const SizedBox(height: Spacing.sm),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.md,
                vertical: Spacing.sm,
              ),
              child: Column(
                children: [
                  for (final line in lines) _SlipLine(line.name, line.amount),
                  // A single line is already its own total.
                  if (lines.length != 1)
                    _SlipLine('Total', total, strong: true),
                ],
              ),
            ),
          ),
        ];
      }

      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (context, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(
            Spacing.lg,
            0,
            Spacing.lg,
            Spacing.lg,
          ),
          children: [
            Text(
              _monthLabel(monthKey).toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Spacing.xs),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    slip.userName,
                    style: Type.display(22, color: scheme.onSurface),
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                StatusChip(finalized ? 'finalized' : 'draft'),
              ],
            ),
            const SizedBox(height: Spacing.md),
            // The figure the whole sheet exists to state.
            Card(
              child: Padding(
                padding: const EdgeInsets.all(Spacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'NET PAY',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: Spacing.sm),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Money(slip.netPay, scale: MoneyScale.display),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: Spacing.lg),
            const SectionHeader('Earnings'),
            const SizedBox(height: Spacing.sm),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.md,
                  vertical: Spacing.sm,
                ),
                child: Column(
                  children: [
                    _SlipLine('Basic salary', slip.basicSalary),
                    if (slip.allowancesBreakdown.isNotEmpty ||
                        slip.allowancesTotal != 0) ...[
                      for (final line in slip.allowancesBreakdown)
                        _SlipLine(line.name, line.amount),
                      if (slip.allowancesBreakdown.length != 1)
                        _SlipLine('Allowances', slip.allowancesTotal),
                    ],
                    _SlipLine('Gross pay', slip.grossPay, strong: true),
                  ],
                ),
              ),
            ),
            ...section(
              'Statutory (employee)',
              slip.statutoryEmployeeBreakdown,
              slip.statutoryEmployeeTotal,
            ),
            const SizedBox(height: Spacing.lg),
            const SectionHeader('Tax'),
            const SizedBox(height: Spacing.sm),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.md,
                  vertical: Spacing.sm,
                ),
                child: Column(
                  children: [
                    _SlipLine('Taxable income', slip.taxableIncome),
                    _SlipLine('PAYE', slip.payeAmount, strong: true),
                  ],
                ),
              ),
            ),
            ...section(
              'Other deductions',
              slip.deductionsBreakdown,
              slip.otherDeductionsTotal,
            ),
            ...section(
              'Statutory (employer)',
              slip.statutoryEmployerBreakdown,
              slip.statutoryEmployerTotal,
            ),
            const SizedBox(height: Spacing.lg),
            const SectionHeader('Employer'),
            const SizedBox(height: Spacing.sm),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.md,
                  vertical: Spacing.sm,
                ),
                child: _SlipLine(
                  'Employer cost',
                  slip.employerCostTotal,
                  strong: true,
                ),
              ),
            ),
            const SizedBox(height: Spacing.lg),
            // The PDF endpoints 422 until the run is finalized.
            PrimaryButton(
              icon: Icons.picture_as_pdf_outlined,
              label: finalized
                  ? 'Share payslip PDF'
                  : 'PDF available once finalized',
              onPressed: !finalized
                  ? null
                  : () => sharePdf(
                      context,
                      fetch: fetchPdf,
                      filename:
                          'payslip-${slip.userName.replaceAll(' ', '-')}-$monthKey.pdf',
                    ),
            ),
            const SizedBox(height: Spacing.lg),
          ],
        ),
      );
    },
  );
}

/// One line of a payslip: the mono eyebrow names the item, the figure sits on
/// the right so a column of them reads as arithmetic. [strong] is for a
/// subtotal — the same size, in full-strength ink.
class _SlipLine extends StatelessWidget {
  const _SlipLine(this.label, this.amount, {this.strong = false});

  final String label;
  final Object? amount;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.xs + 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Text(
              label.toUpperCase(),
              maxLines: 2,
              style: theme.textTheme.labelSmall?.copyWith(
                color: strong ? scheme.onSurface : scheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: Spacing.sm),
          Money(
            amount,
            scale: strong ? MoneyScale.row : MoneyScale.dense,
            showCode: false,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Salaries
// ---------------------------------------------------------------------------

class _SalariesTab extends ConsumerWidget {
  const _SalariesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final salaries = ref.watch(salariesProvider);
    final theme = Theme.of(context);

    return CrmAsyncView(
      value: salaries,
      errorTitle: 'Could not load salaries',
      onRetry: () => ref.invalidate(salariesProvider),
      builder: (list) => RefreshIndicator(
        onRefresh: () => ref.refresh(salariesProvider.future),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(Spacing.md),
          children: [
            if (list.isEmpty)
              const SizedBox(
                height: 320,
                child: StateMessage(
                  icon: Icons.account_balance_wallet_outlined,
                  title: 'No salaries on file',
                  message:
                      'Employees without a salary are skipped when payroll is '
                      'generated.',
                ),
              )
            else ...[
              Reveal(
                child: CrmCardList(
                  children: [
                    for (final s in list)
                      ListTile(
                        dense: true,
                        title: Text(
                          s.userName,
                          style: theme.textTheme.titleSmall,
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: CrmMetaLine(
                            [
                              'From ${Formatting.date(s.effectiveFrom)}',
                              if (s.notes != null) s.notes!,
                            ].join(' · '),
                          ),
                        ),
                        trailing: Money(s.basicSalary, showCode: false),
                        onLongPress: () => _delete(context, ref, s),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: Spacing.sm),
              Text(
                'Press and hold an entry to remove it.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: Spacing.xl),
          ],
        ),
      ),
    );
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    StaffSalary s,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove this salary entry?'),
        content: Text(
          '${s.userName} · ${Formatting.currency(s.basicSalary)} from ${Formatting.date(s.effectiveFrom)}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false) || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(hrServiceProvider).deleteSalary(s.id);
      ref.invalidate(salariesProvider);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

// ---------------------------------------------------------------------------
// Loans & advances
// ---------------------------------------------------------------------------

class _LoansTab extends ConsumerWidget {
  const _LoansTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loans = ref.watch(loansProvider);
    final advances = ref.watch(salaryAdvancesProvider);
    final theme = Theme.of(context);
    final status = context.statusColors;

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(loansProvider);
        ref.invalidate(salaryAdvancesProvider);
        await ref.read(loansProvider.future);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(Spacing.md),
        children: [
          const SectionHeader('Loans'),
          const SizedBox(height: Spacing.sm),
          loans.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => ErrorBanner(
              message: e is ApiException ? e.message : 'Could not load loans',
              onRetry: () => ref.invalidate(loansProvider),
            ),
            data: (list) => list.isEmpty
                ? const Card(
                    child: StateMessage(
                      icon: Icons.request_quote_outlined,
                      title: 'No loans',
                      message: 'Loans are repaid in instalments via payroll.',
                    ),
                  )
                : Reveal(
                    child: CrmCardList(
                      children: [
                        for (final loan in list)
                          ListTile(
                            dense: true,
                            title: Text(
                              loan.userName,
                              style: theme.textTheme.titleSmall,
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: CrmStatusLine(
                                status: loan.status,
                                meta:
                                    '${Formatting.currency(loan.monthlyInstallment)}/month · '
                                    'issued ${Formatting.date(loan.issuedDate)}',
                              ),
                            ),
                            trailing: Money(
                              loan.balance,
                              showCode: false,
                              color: loan.isActive ? status.attention : null,
                            ),
                            onTap: () => _showLoan(context, ref, loan),
                          ),
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: Spacing.lg),
          const SectionHeader('Salary advances'),
          const SizedBox(height: Spacing.sm),
          advances.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => ErrorBanner(
              message: e is ApiException
                  ? e.message
                  : 'Could not load advances',
              onRetry: () => ref.invalidate(salaryAdvancesProvider),
            ),
            data: (list) => list.isEmpty
                ? const Card(
                    child: StateMessage(
                      icon: Icons.fast_forward_outlined,
                      title: 'No advances',
                      message:
                          'An advance is recovered in full from one month.',
                    ),
                  )
                : CrmCardList(
                    children: [
                      for (final adv in list)
                        ListTile(
                          dense: true,
                          title: Text(
                            adv.userName,
                            style: theme.textTheme.titleSmall,
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: CrmStatusLine(
                              status: adv.status,
                              meta:
                                  'Recover in ${_monthLabel(adv.recoveryMonthKey)} · '
                                  'issued ${Formatting.date(adv.issuedDate)}',
                            ),
                          ),
                          trailing: Money(adv.amount, showCode: false),
                          onLongPress: adv.isPending
                              ? () => _cancelAdvance(context, ref, adv)
                              : null,
                        ),
                    ],
                  ),
          ),
          // Cancelling is destructive and rare, so it hides behind a long
          // press rather than sitting on every row — which needs saying.
          if (advances.valueOrNull?.any((a) => a.isPending) ?? false) ...[
            const SizedBox(height: Spacing.sm),
            Text(
              'Press and hold a pending advance to cancel it.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: Spacing.xl),
        ],
      ),
    );
  }

  Future<void> _showLoan(BuildContext context, WidgetRef ref, Loan loan) async {
    final messenger = ScaffoldMessenger.of(context);
    final cancel = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final theme = Theme.of(context);
          final scheme = theme.colorScheme;
          final payments = ref.watch(loanPaymentsProvider(loan.id));

          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.6,
            maxChildSize: 0.95,
            builder: (context, scroll) => ListView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(
                Spacing.lg,
                0,
                Spacing.lg,
                Spacing.lg,
              ),
              children: [
                Text(
                  'LOAN',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: Spacing.xs),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        loan.userName,
                        style: Type.display(22, color: scheme.onSurface),
                      ),
                    ),
                    const SizedBox(width: Spacing.sm),
                    StatusChip(loan.status),
                  ],
                ),
                const SizedBox(height: Spacing.md),
                // What is still owed is the figure that decides anything here.
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(Spacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'BALANCE',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: Spacing.sm),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Money(
                            loan.balance,
                            scale: MoneyScale.display,
                            color: loan.isActive
                                ? context.statusColors.attention
                                : null,
                          ),
                        ),
                        const Divider(height: Spacing.lg + Spacing.sm),
                        Row(
                          children: [
                            Expanded(
                              child: _Figure(
                                label: 'Principal',
                                amount: loan.principal,
                              ),
                            ),
                            const SizedBox(width: Spacing.md),
                            Expanded(
                              child: _Figure(
                                label: 'Instalment / month',
                                amount: loan.monthlyInstallment,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: Spacing.sm),
                        Text(
                          [
                            'Issued ${Formatting.date(loan.issuedDate)}',
                            if (loan.notes != null) loan.notes!,
                          ].join(' · ').toUpperCase(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: Spacing.lg),
                const SectionHeader('Repayments'),
                const SizedBox(height: Spacing.sm),
                payments.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (e, _) => ErrorBanner(
                    message: e is ApiException
                        ? e.message
                        : 'Could not load repayments',
                    onRetry: () =>
                        ref.invalidate(loanPaymentsProvider(loan.id)),
                  ),
                  data: (rows) => rows.isEmpty
                      ? const Card(
                          child: StateMessage(
                            icon: Icons.history_outlined,
                            title: 'Nothing collected yet',
                            message:
                                'Instalments appear here as payroll months are '
                                'finalized.',
                          ),
                        )
                      : CrmCardList(
                          children: [
                            for (final p in rows)
                              ListTile(
                                dense: true,
                                title: Text(
                                  p.runMonthKey == null
                                      ? 'Manual'
                                      : 'Payroll ${_monthLabel(p.runMonthKey!)}',
                                  style: theme.textTheme.titleSmall,
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: CrmMetaLine(
                                    'Balance after ${Formatting.currency(p.balanceAfter)}',
                                  ),
                                ),
                                trailing: Money(p.amount, showCode: false),
                              ),
                          ],
                        ),
                ),
                if (loan.isActive && loan.balance == loan.principal) ...[
                  const SizedBox(height: Spacing.lg),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.cancel_outlined, size: 18),
                    label: const Text('Cancel loan'),
                    onPressed: () => Navigator.pop(context, true),
                  ),
                ],
                const SizedBox(height: Spacing.lg),
              ],
            ),
          );
        },
      ),
    );
    if (!(cancel ?? false) || !context.mounted) return;

    final confirmed = await _confirm(
      context,
      title: 'Cancel this loan?',
      body:
          'No further instalments will be collected. The repayment history is kept.',
    );
    if (!confirmed) return;
    try {
      await ref.read(hrServiceProvider).cancelLoan(loan.id);
      ref.invalidate(loansProvider);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _cancelAdvance(
    BuildContext context,
    WidgetRef ref,
    SalaryAdvance adv,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await _confirm(
      context,
      title: 'Cancel this advance?',
      body:
          '${adv.userName} · ${Formatting.currency(adv.amount)} will not be recovered from payroll.',
    );
    if (!confirmed || !context.mounted) return;
    try {
      await ref.read(hrServiceProvider).cancelSalaryAdvance(adv.id);
      ref.invalidate(salaryAdvancesProvider);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

enum _MoneyFormKind { salary, loan, advance }

/// One form for the three "employee + amount + date" records.
class _MoneyFormSheet extends ConsumerStatefulWidget {
  const _MoneyFormSheet({required this.kind});

  final _MoneyFormKind kind;

  @override
  ConsumerState<_MoneyFormSheet> createState() => _MoneyFormSheetState();
}

class _MoneyFormSheetState extends ConsumerState<_MoneyFormSheet> {
  final _amount = TextEditingController();
  final _installment = TextEditingController();
  final _notes = TextEditingController();
  StaffUser? _user;
  DateTime _date = DateTime.now();
  String? _recoveryMonth;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _installment.dispose();
    _notes.dispose();
    super.dispose();
  }

  String get _title => switch (widget.kind) {
    _MoneyFormKind.salary => 'Set basic salary',
    _MoneyFormKind.loan => 'New loan',
    _MoneyFormKind.advance => 'New salary advance',
  };

  String get _amountLabel => switch (widget.kind) {
    _MoneyFormKind.salary => 'Basic salary (monthly)',
    _MoneyFormKind.loan => 'Principal',
    _MoneyFormKind.advance => 'Amount',
  };

  Future<void> _save() async {
    final amount = double.tryParse(_amount.text.replaceAll(',', '').trim());
    if (_user == null || amount == null || amount <= 0) {
      setState(() => _error = 'Choose an employee and enter an amount.');
      return;
    }
    final installment = double.tryParse(
      _installment.text.replaceAll(',', '').trim(),
    );
    if (widget.kind == _MoneyFormKind.loan &&
        (installment == null || installment <= 0)) {
      setState(() => _error = 'Enter the monthly instalment.');
      return;
    }
    if (widget.kind == _MoneyFormKind.advance && _recoveryMonth == null) {
      setState(() => _error = 'Choose the month that recovers it.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    final service = ref.read(hrServiceProvider);
    final notes = _notes.text.trim().isEmpty ? null : _notes.text.trim();
    try {
      switch (widget.kind) {
        case _MoneyFormKind.salary:
          await service.createSalary(
            userId: _user!.id,
            basicSalary: amount,
            effectiveFrom: _date,
            notes: notes,
          );
        case _MoneyFormKind.loan:
          await service.createLoan(
            userId: _user!.id,
            principal: amount,
            monthlyInstallment: installment!,
            issuedDate: _date,
            notes: notes,
          );
        case _MoneyFormKind.advance:
          await service.createSalaryAdvance(
            userId: _user!.id,
            amount: amount,
            issuedDate: _date,
            recoveryMonthKey: _recoveryMonth!,
            notes: notes,
          );
      }
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel = widget.kind == _MoneyFormKind.salary
        ? 'Effective from'
        : 'Issued';

    return CrmSheet(
      eyebrow: 'Payroll',
      title: _title,
      children: [
        if (_error != null) ...[
          ErrorBanner(message: _error!),
          const SizedBox(height: Spacing.md),
        ],
        CrmPickerField(
          label: 'Employee',
          value: _user?.name ?? 'Choose an employee',
          placeholder: _user == null,
          icon: Icons.person_outline,
          onTap: _saving
              ? null
              : () async {
                  final picked = await StaffUserPickerSheet.show(context);
                  if (picked != null) setState(() => _user = picked);
                },
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: _amountLabel,
          child: TextField(
            controller: _amount,
            enabled: !_saving,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              hintText: '0.00',
              prefixText: '${Formatting.tenantCurrency} ',
            ),
          ),
        ),
        if (widget.kind == _MoneyFormKind.loan) ...[
          const SizedBox(height: Spacing.md),
          CrmField(
            label: 'Monthly instalment',
            child: TextField(
              controller: _installment,
              enabled: !_saving,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                hintText: '0.00',
                prefixText: '${Formatting.tenantCurrency} ',
              ),
            ),
          ),
        ],
        const SizedBox(height: Spacing.md),
        CrmPickerField(
          label: dateLabel,
          value: Formatting.date(_date),
          onTap: _saving
              ? null
              : () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (picked != null) setState(() => _date = picked);
                },
        ),
        if (widget.kind == _MoneyFormKind.advance) ...[
          const SizedBox(height: Spacing.md),
          CrmPickerField(
            label: 'Recovered from',
            value: _recoveryMonth == null
                ? 'Choose a payroll month'
                : _monthLabel(_recoveryMonth!),
            placeholder: _recoveryMonth == null,
            icon: Icons.event_repeat_outlined,
            onTap: _saving
                ? null
                : () async {
                    final key = await _pickMonth(
                      context,
                      title: 'Recover from',
                    );
                    if (key != null) setState(() => _recoveryMonth = key);
                  },
          ),
        ],
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Notes (optional)',
          child: TextField(
            controller: _notes,
            enabled: !_saving,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'What this record is for',
            ),
          ),
        ),
        const SizedBox(height: Spacing.lg),
        PrimaryButton(
          label: _saving ? 'Saving…' : 'Save',
          busy: _saving,
          onPressed: _saving ? null : _save,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// My payslips
// ---------------------------------------------------------------------------

class _MyPayslipsTab extends ConsumerWidget {
  const _MyPayslipsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final payslips = ref.watch(myPayslipsProvider);
    final theme = Theme.of(context);

    return CrmAsyncView(
      value: payslips,
      errorTitle: 'Could not load your payslips',
      onRetry: () => ref.invalidate(myPayslipsProvider),
      builder: (list) => RefreshIndicator(
        onRefresh: () => ref.refresh(myPayslipsProvider.future),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(Spacing.md),
          children: [
            if (list.isEmpty)
              const SizedBox(
                height: 320,
                child: StateMessage(
                  icon: Icons.receipt_long_outlined,
                  title: 'No payslips yet',
                  message: 'Payslips appear here once payroll is generated.',
                ),
              )
            else
              Reveal(
                child: CrmCardList(
                  children: [
                    for (final slip in list)
                      ListTile(
                        title: Text(
                          _monthLabel(slip.runMonthKey ?? '—'),
                          style: theme.textTheme.titleSmall,
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: CrmStatusLine(
                            status: slip.runStatus ?? 'draft',
                            meta: 'Gross ${Formatting.currency(slip.grossPay)}',
                          ),
                        ),
                        trailing: Money(slip.netPay, showCode: false),
                        onTap: () => showPayslipSheet(
                          context,
                          slip,
                          monthKey: slip.runMonthKey ?? '—',
                          finalized: slip.runStatus == 'finalized',
                          fetchPdf: () =>
                              ref.read(hrServiceProvider).myPayslipPdf(slip.id),
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: Spacing.xl),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// `2026-08` → `Aug 2026`.
String _monthLabel(String monthKey) {
  final parts = monthKey.split('-');
  if (parts.length != 2) return monthKey;
  final month = int.tryParse(parts[1]);
  if (month == null || month < 1 || month > 12) return monthKey;
  return '${_months[month - 1]} ${parts[0]}';
}

/// Year + month picker returning a `YYYY-MM` key.
Future<String?> _pickMonth(BuildContext context, {required String title}) {
  final now = DateTime.now();
  var year = now.year;
  var month = now.month;
  return showDialog<String>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(title),
        content: Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: month,
                decoration: const InputDecoration(labelText: 'Month'),
                items: [
                  for (var m = 1; m <= 12; m++)
                    DropdownMenuItem(value: m, child: Text(_months[m - 1])),
                ],
                onChanged: (v) => setState(() => month = v!),
              ),
            ),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: year,
                decoration: const InputDecoration(labelText: 'Year'),
                items: [
                  for (var y = now.year - 2; y <= now.year + 1; y++)
                    DropdownMenuItem(value: y, child: Text('$y')),
                ],
                onChanged: (v) => setState(() => year = v!),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              HrService.monthKey(DateTime(year, month)),
            ),
            child: const Text('Continue'),
          ),
        ],
      ),
    ),
  );
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String body,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Back'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Confirm'),
        ),
      ],
    ),
  );
  return result ?? false;
}
