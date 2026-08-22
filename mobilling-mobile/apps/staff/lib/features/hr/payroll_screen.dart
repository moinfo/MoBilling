import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';
import '../common/pickers.dart';
import '../common/share_pdf.dart';
import '../crm/crm_ui.dart' show CrmAsyncView, CrmDetailRow;
import 'hr_providers.dart';

/// Payroll on a phone: the monthly runs, who earns what, loans and
/// advances, and every employee's own payslips.
///
/// Deliberately web-only: the allowance / deduction / statutory-rate
/// catalogs and their per-employee assignment matrices, and PAYE bracket
/// editing. Those are grids, and a grid is not a phone screen. Everything
/// that is a list or a form is here.
class PayrollScreen extends ConsumerWidget {
  const PayrollScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(sessionControllerProvider).session;
    final canManage = auth?.can(HrPermissions.payrollManage) ?? false;
    final canView =
        canManage || (auth?.can(HrPermissions.payrollView) ?? false);

    final tabs = <(String, Widget)>[
      if (canView) ('Runs', _RunsTab(canManage: canManage)),
      if (canManage) ('Salaries', const _SalariesTab()),
      if (canManage) ('Loans', const _LoansTab()),
      ('My payslips', const _MyPayslipsTab()),
    ];

    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Payroll'),
          bottom: TabBar(
            isScrollable: tabs.length > 3,
            tabs: [for (final (label, _) in tabs) Tab(text: label)],
          ),
        ),
        body: TabBarView(children: [for (final (_, body) in tabs) body]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Runs
// ---------------------------------------------------------------------------

class _RunsTab extends ConsumerWidget {
  const _RunsTab({required this.canManage});

  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runs = ref.watch(payrollRunsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.play_arrow_outlined),
              label: const Text('Generate'),
              onPressed: () => _generate(context, ref),
            )
          : null,
      body: CrmAsyncView(
        value: runs,
        errorTitle: 'Could not load payroll runs',
        onRetry: () => ref.invalidate(payrollRunsProvider),
        builder: (list) => RefreshIndicator(
          onRefresh: () => ref.refresh(payrollRunsProvider.future),
          child: list.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: const [
                    SizedBox(
                      height: 320,
                      child: StateMessage(
                        icon: Icons.account_balance_outlined,
                        title: 'No payroll runs yet',
                        message:
                            'Generate a month to create a payslip for every employee with a salary on file.',
                      ),
                    ),
                  ],
                )
              : ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(
                      Spacing.md, Spacing.md, Spacing.md, 96),
                  itemCount: list.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: Spacing.sm),
                  itemBuilder: (context, index) {
                    final run = list[index];
                    return Card(
                      child: ListTile(
                        leading: Icon(
                          run.isFinalized
                              ? Icons.lock_outline
                              : Icons.edit_note_outlined,
                          color: run.isFinalized
                              ? context.statusColors.settled
                              : context.statusColors.pending,
                        ),
                        title: Text(_monthLabel(run.monthKey),
                            style: theme.textTheme.titleSmall),
                        subtitle: Text(
                          '${run.payslipsCount} payslip${run.payslipsCount == 1 ? '' : 's'}'
                          '${run.finalizedAt != null ? ' · finalized ${Formatting.date(run.finalizedAt)}' : run.generatedAt != null ? ' · generated ${Formatting.date(run.generatedAt)}' : ''}',
                          style: theme.textTheme.bodySmall,
                        ),
                        trailing: StatusChip(
                            run.isFinalized ? 'finalized' : 'draft',
                            dense: true),
                        onTap: () => context.push('/payroll/runs/${run.id}'),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }

  Future<void> _generate(BuildContext context, WidgetRef ref) async {
    final monthKey = await _pickMonth(context, title: 'Generate payroll for');
    if (monthKey == null || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      final message =
          await ref.read(hrServiceProvider).generatePayrollRun(monthKey);
      ref.invalidate(payrollRunsProvider);
      messenger.showSnackBar(
          SnackBar(content: Text(message ?? 'Payroll generated.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

/// One payroll run: totals, the payslips, and the draft → finalized step.
class PayrollRunScreen extends ConsumerWidget {
  const PayrollRunScreen({super.key, required this.runId});

  final String runId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final run = ref.watch(payrollRunProvider(runId));
    final canManage = ref.watch(sessionControllerProvider).session?.can(
            HrPermissions.payrollManage) ??
        false;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(run.valueOrNull == null
            ? 'Payroll run'
            : _monthLabel(run.value!.monthKey)),
        actions: [
          if (canManage && (run.valueOrNull?.isDraft ?? false))
            PopupMenuButton<String>(
              onSelected: (action) => _act(context, ref, run.value!, action),
              itemBuilder: (context) => const [
                PopupMenuItem(
                    value: 'regenerate', child: Text('Regenerate payslips')),
                PopupMenuItem(
                    value: 'delete', child: Text('Delete draft run')),
              ],
            ),
        ],
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
              Row(
                children: [
                  StatusChip(data.isFinalized ? 'finalized' : 'draft'),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: Text(
                      data.isFinalized
                          ? 'Finalized by ${data.finalizedBy?.name ?? '—'} · ${Formatting.date(data.finalizedAt)}'
                          : 'Generated by ${data.generatedBy?.name ?? '—'} · ${Formatting.date(data.generatedAt)}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Spacing.md),
              Row(
                children: [
                  Expanded(
                    child: StatTile.money(
                      label: 'Net pay',
                      amount: data.netPayTotal,
                      icon: Icons.payments_outlined,
                    ),
                  ),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: StatTile.money(
                      label: 'Employer cost',
                      amount: data.employerCostTotal,
                      icon: Icons.business_outlined,
                    ),
                  ),
                ],
              ),
              if (canManage && data.isDraft) ...[
                const SizedBox(height: Spacing.md),
                FilledButton.icon(
                  icon: const Icon(Icons.lock_outline, size: 18),
                  label: const Text('Finalize run'),
                  onPressed: data.payslips.isEmpty
                      ? null
                      : () => _act(context, ref, data, 'finalize'),
                ),
                const SizedBox(height: Spacing.xs),
                Text(
                  'Finalizing locks the payslips and collects loan '
                  'instalments and salary advances. It cannot be undone.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: Spacing.lg),
              Text('Payslips (${data.payslips.length})',
                  style: theme.textTheme.titleSmall),
              const SizedBox(height: Spacing.sm),
              if (data.payslips.isEmpty)
                Text(
                  'No payslips — no active employee has a salary on file.',
                  style: theme.textTheme.bodySmall,
                )
              else
                Card(
                  child: Column(
                    children: [
                      for (final (i, slip) in data.payslips.indexed) ...[
                        if (i > 0) const Divider(height: 1),
                        ListTile(
                          dense: true,
                          title: Text(slip.userName),
                          subtitle: Text(
                              'Gross ${Formatting.currency(slip.grossPay)}',
                              style: theme.textTheme.bodySmall),
                          trailing: Money(slip.netPay),
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
                    ],
                  ),
                ),
              const SizedBox(height: Spacing.xl),
            ],
          ),
        ),
      ),
    );
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
          'Finalize'
        ),
      'delete' => (
          'Delete this draft run?',
          'All ${run.payslips.length} payslips in it are discarded. You can generate the month again later.',
          'Delete'
        ),
      _ => (
          'Regenerate payslips?',
          'Existing draft payslips are replaced using the current salaries, allowances and deductions.',
          'Regenerate'
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
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(verb)),
        ],
      ),
    );
    if (!(confirmed ?? false) || !context.mounted) return;

    try {
      switch (action) {
        case 'finalize':
          await service.finalizePayrollRun(run.id);
          messenger.showSnackBar(
              const SnackBar(content: Text('Payroll finalized.')));
        case 'delete':
          await service.deletePayrollRun(run.id);
          messenger
              .showSnackBar(const SnackBar(content: Text('Draft deleted.')));
          if (context.mounted) context.pop();
        default:
          final message = await service.generatePayrollRun(run.monthKey);
          messenger.showSnackBar(
              SnackBar(content: Text(message ?? 'Payslips regenerated.')));
      }
      ref.invalidate(payrollRunsProvider);
      ref.invalidate(payrollRunProvider(run.id));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

/// A payslip's full breakdown, with the PDF one tap away.
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
    shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
    builder: (context) {
      final theme = Theme.of(context);

      Widget section(String title, List<BreakdownLine> lines, double total) {
        if (lines.isEmpty && total == 0) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: Spacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.labelLarge),
              for (final line in lines)
                CrmDetailRow(line.name, Formatting.currency(line.amount)),
              if (lines.length != 1)
                CrmDetailRow('Total', Formatting.currency(total)),
            ],
          ),
        );
      }

      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (context, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.all(Spacing.md),
          children: [
            Text(slip.userName, style: theme.textTheme.titleMedium),
            Text(_monthLabel(monthKey), style: theme.textTheme.bodySmall),
            const SizedBox(height: Spacing.md),
            Center(child: Money(slip.netPay, scale: MoneyScale.display)),
            Center(
              child: Text('Net pay',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ),
            const SizedBox(height: Spacing.sm),
            CrmDetailRow('Basic salary', Formatting.currency(slip.basicSalary)),
            section('Allowances', slip.allowancesBreakdown,
                slip.allowancesTotal),
            CrmDetailRow('Gross pay', Formatting.currency(slip.grossPay)),
            section('Statutory (employee)', slip.statutoryEmployeeBreakdown,
                slip.statutoryEmployeeTotal),
            const SizedBox(height: Spacing.md),
            Text('Tax', style: theme.textTheme.labelLarge),
            CrmDetailRow(
                'Taxable income', Formatting.currency(slip.taxableIncome)),
            CrmDetailRow('PAYE', Formatting.currency(slip.payeAmount)),
            section('Other deductions', slip.deductionsBreakdown,
                slip.otherDeductionsTotal),
            section('Statutory (employer)', slip.statutoryEmployerBreakdown,
                slip.statutoryEmployerTotal),
            const SizedBox(height: Spacing.sm),
            CrmDetailRow(
                'Employer cost', Formatting.currency(slip.employerCostTotal)),
            const SizedBox(height: Spacing.lg),
            // The PDF endpoints 422 until the run is finalized.
            FilledButton.icon(
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
              label: Text(finalized
                  ? 'Share payslip PDF'
                  : 'PDF available once finalized'),
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

// ---------------------------------------------------------------------------
// Salaries
// ---------------------------------------------------------------------------

class _SalariesTab extends ConsumerWidget {
  const _SalariesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final salaries = ref.watch(salariesProvider);
    final theme = Theme.of(context);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Set salary'),
        onPressed: () => _add(context, ref),
      ),
      body: CrmAsyncView(
        value: salaries,
        errorTitle: 'Could not load salaries',
        onRetry: () => ref.invalidate(salariesProvider),
        builder: (list) => RefreshIndicator(
          onRefresh: () => ref.refresh(salariesProvider.future),
          child: list.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: const [
                    SizedBox(
                      height: 320,
                      child: StateMessage(
                        icon: Icons.account_balance_wallet_outlined,
                        title: 'No salaries on file',
                        message:
                            'Employees without a salary are skipped when payroll is generated.',
                      ),
                    ),
                  ],
                )
              : ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(
                      Spacing.md, Spacing.md, Spacing.md, 96),
                  itemCount: list.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: Spacing.sm),
                  itemBuilder: (context, index) {
                    final s = list[index];
                    return Card(
                      child: ListTile(
                        title: Text(s.userName),
                        subtitle: Text(
                          'From ${Formatting.date(s.effectiveFrom)}'
                          '${s.notes == null ? '' : ' · ${s.notes}'}',
                          style: theme.textTheme.bodySmall,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Money(s.basicSalary),
                        onLongPress: () => _delete(context, ref, s),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
      builder: (_) => const _MoneyFormSheet(kind: _MoneyFormKind.salary),
    );
    if (saved ?? false) ref.invalidate(salariesProvider);
  }

  Future<void> _delete(
      BuildContext context, WidgetRef ref, StaffSalary s) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove this salary entry?'),
        content: Text(
            '${s.userName} · ${Formatting.currency(s.basicSalary)} from ${Formatting.date(s.effectiveFrom)}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Remove')),
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

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('New'),
        onPressed: () async {
          final kind = await showModalBottomSheet<_MoneyFormKind>(
            context: context,
            shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
            builder: (context) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(Icons.request_quote_outlined),
                    title: const Text('Loan'),
                    subtitle:
                        const Text('Repaid in monthly instalments via payroll'),
                    onTap: () => Navigator.pop(context, _MoneyFormKind.loan),
                  ),
                  ListTile(
                    leading: const Icon(Icons.fast_forward_outlined),
                    title: const Text('Salary advance'),
                    subtitle: const Text('Recovered in full from one month'),
                    onTap: () =>
                        Navigator.pop(context, _MoneyFormKind.advance),
                  ),
                ],
              ),
            ),
          );
          if (kind == null || !context.mounted) return;
          final saved = await showModalBottomSheet<bool>(
            context: context,
            isScrollControlled: true,
            shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
            builder: (_) => _MoneyFormSheet(kind: kind),
          );
          if (saved ?? false) {
            ref.invalidate(loansProvider);
            ref.invalidate(salaryAdvancesProvider);
          }
        },
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(loansProvider);
          ref.invalidate(salaryAdvancesProvider);
          await ref.read(loansProvider.future);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding:
              const EdgeInsets.fromLTRB(Spacing.md, Spacing.md, Spacing.md, 96),
          children: [
            Text('Loans', style: theme.textTheme.titleSmall),
            const SizedBox(height: Spacing.sm),
            loans.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text(
                  e is ApiException ? e.message : 'Could not load loans',
                  style: TextStyle(color: theme.colorScheme.error)),
              data: (list) => list.isEmpty
                  ? Text('No loans.', style: theme.textTheme.bodySmall)
                  : Card(
                      child: Column(
                        children: [
                          for (final (i, loan) in list.indexed) ...[
                            if (i > 0) const Divider(height: 1),
                            ListTile(
                              dense: true,
                              title: Text(loan.userName),
                              subtitle: Text(
                                '${Formatting.currency(loan.monthlyInstallment)}/month · issued ${Formatting.date(loan.issuedDate)}',
                                style: theme.textTheme.bodySmall,
                              ),
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Money(loan.balance,
                                      color: loan.isActive
                                          ? status.attention
                                          : null),
                                  StatusChip(loan.status, dense: true),
                                ],
                              ),
                              onTap: () => _showLoan(context, ref, loan),
                            ),
                          ],
                        ],
                      ),
                    ),
            ),
            const SizedBox(height: Spacing.lg),
            Text('Salary advances', style: theme.textTheme.titleSmall),
            const SizedBox(height: Spacing.sm),
            advances.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text(
                  e is ApiException ? e.message : 'Could not load advances',
                  style: TextStyle(color: theme.colorScheme.error)),
              data: (list) => list.isEmpty
                  ? Text('No advances.', style: theme.textTheme.bodySmall)
                  : Card(
                      child: Column(
                        children: [
                          for (final (i, adv) in list.indexed) ...[
                            if (i > 0) const Divider(height: 1),
                            ListTile(
                              dense: true,
                              title: Text(adv.userName),
                              subtitle: Text(
                                'Recover in ${_monthLabel(adv.recoveryMonthKey)} · issued ${Formatting.date(adv.issuedDate)}',
                                style: theme.textTheme.bodySmall,
                              ),
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Money(adv.amount),
                                  StatusChip(adv.status, dense: true),
                                ],
                              ),
                              onLongPress: adv.isPending
                                  ? () => _cancelAdvance(context, ref, adv)
                                  : null,
                            ),
                          ],
                        ],
                      ),
                    ),
            ),
            const SizedBox(height: Spacing.xl),
          ],
        ),
      ),
    );
  }

  Future<void> _showLoan(BuildContext context, WidgetRef ref, Loan loan) async {
    final messenger = ScaffoldMessenger.of(context);
    final cancel = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final theme = Theme.of(context);
          final payments = ref.watch(loanPaymentsProvider(loan.id));
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.6,
            builder: (context, scroll) => ListView(
              controller: scroll,
              padding: const EdgeInsets.all(Spacing.md),
              children: [
                Row(
                  children: [
                    Expanded(
                        child: Text(loan.userName,
                            style: theme.textTheme.titleMedium)),
                    StatusChip(loan.status, dense: true),
                  ],
                ),
                const SizedBox(height: Spacing.sm),
                CrmDetailRow('Principal', Formatting.currency(loan.principal)),
                CrmDetailRow('Balance', Formatting.currency(loan.balance)),
                CrmDetailRow('Instalment',
                    '${Formatting.currency(loan.monthlyInstallment)}/month'),
                CrmDetailRow('Issued', Formatting.date(loan.issuedDate)),
                if (loan.notes != null) CrmDetailRow('Notes', loan.notes!),
                const SizedBox(height: Spacing.md),
                Text('Repayments', style: theme.textTheme.labelLarge),
                const SizedBox(height: Spacing.xs),
                payments.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (e, _) => Text(
                      e is ApiException ? e.message : 'Could not load',
                      style: TextStyle(color: theme.colorScheme.error)),
                  data: (rows) => rows.isEmpty
                      ? Text('None yet.', style: theme.textTheme.bodySmall)
                      : Column(
                          children: [
                            for (final p in rows)
                              ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: Text(p.runMonthKey == null
                                    ? 'Manual'
                                    : 'Payroll ${_monthLabel(p.runMonthKey!)}'),
                                subtitle: Text(
                                    'Balance after ${Formatting.currency(p.balanceAfter)}',
                                    style: theme.textTheme.bodySmall),
                                trailing: Money(p.amount),
                              ),
                          ],
                        ),
                ),
                if (loan.isActive) ...[
                  const SizedBox(height: Spacing.md),
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

    final confirmed = await _confirm(context,
        title: 'Cancel this loan?',
        body:
            'No further instalments will be collected. The repayment history is kept.');
    if (!confirmed) return;
    try {
      await ref.read(hrServiceProvider).cancelLoan(loan.id);
      ref.invalidate(loansProvider);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _cancelAdvance(
      BuildContext context, WidgetRef ref, SalaryAdvance adv) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await _confirm(context,
        title: 'Cancel this advance?',
        body:
            '${adv.userName} · ${Formatting.currency(adv.amount)} will not be recovered from payroll.');
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

  Future<void> _save() async {
    final amount = double.tryParse(_amount.text.replaceAll(',', '').trim());
    if (_user == null || amount == null || amount <= 0) {
      setState(() => _error = 'Choose an employee and enter an amount.');
      return;
    }
    final installment =
        double.tryParse(_installment.text.replaceAll(',', '').trim());
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
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: Spacing.md,
        right: Spacing.md,
        top: Spacing.md,
        bottom: MediaQuery.of(context).viewInsets.bottom + Spacing.md,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_title, style: theme.textTheme.titleMedium),
          const SizedBox(height: Spacing.md),
          if (_error != null) ...[
            ErrorBanner(message: _error!),
            const SizedBox(height: Spacing.sm),
          ],
          OutlinedButton.icon(
            icon: const Icon(Icons.person_outline, size: 18),
            label: Text(_user?.name ?? 'Choose employee'),
            onPressed: () async {
              final picked = await StaffUserPickerSheet.show(context);
              if (picked != null) setState(() => _user = picked);
            },
          ),
          const SizedBox(height: Spacing.sm),
          TextField(
            controller: _amount,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: switch (widget.kind) {
                _MoneyFormKind.salary => 'Basic salary (monthly)',
                _MoneyFormKind.loan => 'Principal',
                _MoneyFormKind.advance => 'Amount',
              },
              prefixText: '${Formatting.tenantCurrency} ',
            ),
          ),
          if (widget.kind == _MoneyFormKind.loan) ...[
            const SizedBox(height: Spacing.sm),
            TextField(
              controller: _installment,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Monthly instalment',
                prefixText: '${Formatting.tenantCurrency} ',
              ),
            ),
          ],
          const SizedBox(height: Spacing.sm),
          OutlinedButton.icon(
            icon: const Icon(Icons.calendar_today_outlined, size: 16),
            label: Text(
                '${widget.kind == _MoneyFormKind.salary ? 'Effective from' : 'Issued'}: ${Formatting.date(_date)}'),
            onPressed: () async {
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
            const SizedBox(height: Spacing.sm),
            OutlinedButton.icon(
              icon: const Icon(Icons.event_repeat_outlined, size: 16),
              label: Text(_recoveryMonth == null
                  ? 'Recover from payroll month…'
                  : 'Recover in ${_monthLabel(_recoveryMonth!)}'),
              onPressed: () async {
                final key =
                    await _pickMonth(context, title: 'Recover from');
                if (key != null) setState(() => _recoveryMonth = key);
              },
            ),
          ],
          const SizedBox(height: Spacing.sm),
          TextField(
            controller: _notes,
            decoration: const InputDecoration(labelText: 'Notes (optional)'),
          ),
          const SizedBox(height: Spacing.md),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Saving…' : 'Save'),
          ),
        ],
      ),
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
        child: list.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(
                    height: 320,
                    child: StateMessage(
                      icon: Icons.receipt_long_outlined,
                      title: 'No payslips yet',
                      message: 'Payslips appear here once payroll is generated.',
                    ),
                  ),
                ],
              )
            : ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(Spacing.md),
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(height: Spacing.sm),
                itemBuilder: (context, index) {
                  final slip = list[index];
                  final month = slip.runMonthKey ?? '—';
                  return Card(
                    child: ListTile(
                      title: Text(_monthLabel(month),
                          style: theme.textTheme.titleSmall),
                      subtitle: Text(
                          'Gross ${Formatting.currency(slip.grossPay)}',
                          style: theme.textTheme.bodySmall),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Money(slip.netPay),
                          StatusChip(slip.runStatus ?? 'draft', dense: true),
                        ],
                      ),
                      onTap: () => showPayslipSheet(
                        context,
                        slip,
                        monthKey: month,
                        finalized: slip.runStatus == 'finalized',
                        fetchPdf: () =>
                            ref.read(hrServiceProvider).myPayslipPdf(slip.id),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
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
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(
                context, HrService.monthKey(DateTime(year, month))),
            child: const Text('Continue'),
          ),
        ],
      ),
    ),
  );
}

Future<bool> _confirm(BuildContext context,
    {required String title, required String body}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Back')),
        FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm')),
      ],
    ),
  );
  return result ?? false;
}
