import { useState } from 'react';
import {
  Title, Text, Tabs, Paper, Table, Badge, Button, Group, Stack,
  Modal, TextInput, Select, NumberInput, ActionIcon, Switch, Center, Loader, Alert, SegmentedControl, Textarea,
} from '@mantine/core';
import { useForm } from '@mantine/form';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { notifications } from '@mantine/notifications';
import { modals } from '@mantine/modals';
import {
  IconPlayerPlay, IconLock, IconDownload, IconTrash, IconEdit, IconPlus, IconAlertTriangle,
} from '@tabler/icons-react';
import {
  getPayrollSettings, updatePayrollSettings, getStaffSalaries, createStaffSalary, deleteStaffSalary,
  getAllowances, createAllowance, updateAllowance, deleteAllowance, getAllowanceSubscriptions, subscribeAllowance,
  getDeductions, createDeduction, updateDeduction, deleteDeduction, getDeductionSubscriptions, subscribeDeduction,
  getStatutoryRates, createStatutoryRate, updateStatutoryRate, deleteStatutoryRate,
  getStatutoryRateSubscriptions, subscribeStatutoryRate,
  getPayeSubscriptions, subscribePaye,
  getAttendancePenaltySubscriptions, subscribeAttendancePenalty,
  getReportPenaltySubscriptions, subscribeReportPenalty,
  getPayrollRuns, getPayrollRun, generatePayrollRun, finalizePayrollRun, deletePayrollRun, downloadPayslipPdf,
  getMyPayslips, downloadMyPayslipPdf,
  getLoans, createLoan, getLoanPayments, cancelLoan,
  getSalaryAdvances, createSalaryAdvance, cancelSalaryAdvance,
  PayeBracket, Allowance, Deduction, StatutoryRate, PayrollRun, Loan, SalaryAdvance, Payslip,
} from '../api/payroll';
import { getUsers } from '../api/users';
import { formatCurrency } from '../utils/formatCurrency';
import { usePermissions } from '../hooks/usePermissions';

function downloadBlob(data: BlobPart, filename: string) {
  const url = window.URL.createObjectURL(new Blob([data]));
  const a = window.document.createElement('a');
  a.href = url;
  a.download = filename;
  a.click();
  window.URL.revokeObjectURL(url);
}

/** Decimal columns come back from Laravel as numeric strings — parseFloat before arithmetic (same fix as Bills.tsx's payment sum). */
function num(v: number | string | null | undefined): number {
  const n = typeof v === 'string' ? parseFloat(v) : v;
  return Number.isFinite(n as number) ? (n as number) : 0;
}

/** Every line that reduces net pay, itemized: PAYE + each statutory rate (NSSF, WCF, SDL, ...) + each other deduction (catalog, penalties, loan, advance). */
function deductionItems(p: Payslip): { name: string; amount: number }[] {
  const items: { name: string; amount: number }[] = [];
  if (num(p.paye_amount) > 0) items.push({ name: 'PAYE', amount: num(p.paye_amount) });
  for (const b of p.statutory_employee_breakdown ?? []) items.push({ name: b.name, amount: num(b.amount) });
  for (const b of p.deductions_breakdown ?? []) items.push({ name: b.name, amount: num(b.amount) });
  return items;
}

export default function Payroll() {
  const { can } = usePermissions();
  const canManage = can('payroll.manage');
  const canView = can('payroll.manage') || can('payroll.view');

  return (
    <Stack gap="lg">
      <Title order={2}>Payroll</Title>
      <Tabs defaultValue={canView ? 'runs' : 'mine'} keepMounted={false}>
        <Tabs.List>
          {canView && <Tabs.Tab value="runs">Runs</Tabs.Tab>}
          {canManage && <Tabs.Tab value="salaries">Salaries</Tabs.Tab>}
          {canManage && <Tabs.Tab value="allowances">Allowances</Tabs.Tab>}
          {canManage && <Tabs.Tab value="deductions">Deductions</Tabs.Tab>}
          {canManage && <Tabs.Tab value="statutory">Statutory Rates</Tabs.Tab>}
          {canManage && <Tabs.Tab value="loans">Loans & Advances</Tabs.Tab>}
          {canManage && <Tabs.Tab value="settings">Settings</Tabs.Tab>}
          <Tabs.Tab value="mine">My Payslips</Tabs.Tab>
        </Tabs.List>

        {canView && <Tabs.Panel value="runs" pt="md"><RunsTab canManage={canManage} /></Tabs.Panel>}
        {canManage && <Tabs.Panel value="salaries" pt="md"><SalariesTab /></Tabs.Panel>}
        {canManage && <Tabs.Panel value="allowances" pt="md"><CatalogTab kind="allowance" /></Tabs.Panel>}
        {canManage && <Tabs.Panel value="deductions" pt="md"><CatalogTab kind="deduction" /></Tabs.Panel>}
        {canManage && <Tabs.Panel value="statutory" pt="md"><StatutoryRatesTab /></Tabs.Panel>}
        {canManage && <Tabs.Panel value="loans" pt="md"><LoansAdvancesTab /></Tabs.Panel>}
        {canManage && <Tabs.Panel value="settings" pt="md"><SettingsTab /></Tabs.Panel>}
        <Tabs.Panel value="mine" pt="md"><MyPayslipsTab /></Tabs.Panel>
      </Tabs>
    </Stack>
  );
}

function RunsTab({ canManage }: { canManage: boolean }) {
  const queryClient = useQueryClient();
  const [monthKey, setMonthKey] = useState(new Date().toISOString().slice(0, 7));
  const [expandedRun, setExpandedRun] = useState<string | null>(null);

  const { data, isLoading } = useQuery({ queryKey: ['payroll-runs'], queryFn: getPayrollRuns });
  const runs = data?.data?.data ?? [];

  const { data: runDetail } = useQuery({
    queryKey: ['payroll-run', expandedRun],
    queryFn: () => getPayrollRun(expandedRun!),
    enabled: !!expandedRun,
  });

  const generateMut = useMutation({
    mutationFn: (mk: string) => generatePayrollRun(mk),
    onSuccess: (res) => {
      notifications.show({ title: 'Success', message: res.data.message, color: 'green' });
      queryClient.invalidateQueries({ queryKey: ['payroll-runs'] });
      setExpandedRun(res.data.data.id);
    },
    onError: (err: any) => notifications.show({
      title: 'Error', message: err.response?.data?.message || 'Failed to generate payroll', color: 'red',
    }),
  });

  const finalizeMut = useMutation({
    mutationFn: (id: string) => finalizePayrollRun(id),
    onSuccess: () => {
      notifications.show({ title: 'Success', message: 'Payroll finalized', color: 'green' });
      queryClient.invalidateQueries({ queryKey: ['payroll-runs'] });
      queryClient.invalidateQueries({ queryKey: ['payroll-run', expandedRun] });
    },
    onError: (err: any) => notifications.show({
      title: 'Error', message: err.response?.data?.message || 'Failed to finalize', color: 'red',
    }),
  });

  const confirmFinalize = (run: PayrollRun) => {
    modals.openConfirmModal({
      title: 'Finalize Payroll',
      children: <Text size="sm">
        Finalize payroll for {run.month_key}? Once finalized, payslips are locked and employees can view/download them —
        the run can no longer be regenerated.
      </Text>,
      labels: { confirm: 'Finalize', cancel: 'Cancel' },
      confirmProps: { color: 'green' },
      onConfirm: () => finalizeMut.mutate(run.id),
    });
  };

  const deleteMut = useMutation({
    mutationFn: (id: string) => deletePayrollRun(id),
    onSuccess: (_res, id) => {
      notifications.show({ title: 'Success', message: 'Payroll run deleted', color: 'green' });
      queryClient.invalidateQueries({ queryKey: ['payroll-runs'] });
      if (expandedRun === id) setExpandedRun(null);
    },
    onError: (err: any) => notifications.show({
      title: 'Error', message: err.response?.data?.message || 'Failed to delete', color: 'red',
    }),
  });

  const confirmDelete = (run: PayrollRun) => {
    modals.openConfirmModal({
      title: 'Delete Payroll Run',
      children: <Text size="sm">
        Delete the draft payroll run for {run.month_key}? This removes all {run.payslips_count ?? 0} payslip(s) generated for it. This cannot be undone.
      </Text>,
      labels: { confirm: 'Delete', cancel: 'Cancel' },
      confirmProps: { color: 'red' },
      onConfirm: () => deleteMut.mutate(run.id),
    });
  };

  const downloadPdf = async (payslipId: string, name: string, mk: string) => {
    try {
      const res = await downloadPayslipPdf(payslipId);
      downloadBlob(res.data, `payslip-${name.replace(/\s+/g, '-')}-${mk}.pdf`);
    } catch {
      notifications.show({ message: 'Failed to download payslip', color: 'red' });
    }
  };

  return (
    <Stack gap="md">
      {canManage && (
        <Group align="flex-end" gap="xs">
          <TextInput label="Month" type="month" value={monthKey} onChange={(e) => setMonthKey(e.currentTarget.value)} />
          <Button leftSection={<IconPlayerPlay size={16} />} loading={generateMut.isPending} onClick={() => generateMut.mutate(monthKey)}>
            Generate Payroll
          </Button>
        </Group>
      )}

      {isLoading ? <Center py="md"><Loader size="sm" /></Center> : runs.length === 0 ? (
        <Text c="dimmed" size="sm">No payroll runs yet.</Text>
      ) : (
        <Table striped highlightOnHover>
          <Table.Thead>
            <Table.Tr>
              <Table.Th>Month</Table.Th>
              <Table.Th>Status</Table.Th>
              <Table.Th>Payslips</Table.Th>
              <Table.Th>Actions</Table.Th>
            </Table.Tr>
          </Table.Thead>
          <Table.Tbody>
            {runs.map((r) => (
              <Table.Tr key={r.id} style={{ cursor: 'pointer' }} onClick={() => setExpandedRun(expandedRun === r.id ? null : r.id)}>
                <Table.Td fw={500}>{r.month_key}</Table.Td>
                <Table.Td><Badge size="sm" color={r.status === 'finalized' ? 'green' : 'yellow'}>{r.status}</Badge></Table.Td>
                <Table.Td>{r.payslips_count ?? '—'}</Table.Td>
                <Table.Td onClick={(e) => e.stopPropagation()}>
                  {canManage && r.status === 'draft' && (
                    <Group gap="xs">
                      <Button size="xs" variant="light" color="green" leftSection={<IconLock size={14} />} onClick={() => confirmFinalize(r)}>
                        Finalize
                      </Button>
                      <ActionIcon variant="subtle" size="sm" color="red" onClick={() => confirmDelete(r)}>
                        <IconTrash size={14} />
                      </ActionIcon>
                    </Group>
                  )}
                </Table.Td>
              </Table.Tr>
            ))}
          </Table.Tbody>
        </Table>
      )}

      {expandedRun && runDetail?.data?.data && (() => {
        const payslips = runDetail.data!.data.payslips ?? [];
        // One column per distinct deduction name across the whole run (PAYE, NSSF, Attendance Penalties, ...),
        // in order of first appearance, so every employee's row lines up under the same headers.
        const dedNames: string[] = [];
        const dedMaps = payslips.map((p) => {
          const map: Record<string, number> = {};
          for (const it of deductionItems(p)) {
            map[it.name] = (map[it.name] ?? 0) + it.amount;
            if (!dedNames.includes(it.name)) dedNames.push(it.name);
          }
          return map;
        });

        return (
          <Paper withBorder p="md" radius="md">
            <Title order={5} mb="sm">Payslips — {runDetail.data!.data.month_key}</Title>
            <Table.ScrollContainer minWidth={550 + dedNames.length * 140}>
              <Table striped highlightOnHover>
                <Table.Thead>
                  <Table.Tr>
                    <Table.Th>#</Table.Th>
                    <Table.Th>Employee</Table.Th>
                    <Table.Th>Gross</Table.Th>
                    {dedNames.map((name) => <Table.Th key={name}>{name}</Table.Th>)}
                    <Table.Th>Net Pay</Table.Th>
                    <Table.Th />
                  </Table.Tr>
                </Table.Thead>
                <Table.Tbody>
                  {payslips.map((p, i) => (
                    <Table.Tr key={p.id}>
                      <Table.Td>{i + 1}</Table.Td>
                      <Table.Td>{p.user?.name ?? '—'}</Table.Td>
                      <Table.Td>{formatCurrency(p.gross_pay)}</Table.Td>
                      {dedNames.map((name) => (
                        <Table.Td key={name}>{dedMaps[i][name] ? formatCurrency(dedMaps[i][name]) : '—'}</Table.Td>
                      ))}
                      <Table.Td fw={600}>{formatCurrency(p.net_pay)}</Table.Td>
                      <Table.Td>
                        <ActionIcon variant="subtle" size="sm" onClick={() => downloadPdf(p.id, p.user?.name ?? 'payslip', runDetail.data!.data.month_key)}>
                          <IconDownload size={14} />
                        </ActionIcon>
                      </Table.Td>
                    </Table.Tr>
                  ))}
                </Table.Tbody>
                <Table.Tfoot>
                  <Table.Tr>
                    <Table.Th />
                    <Table.Th>Total</Table.Th>
                    <Table.Th>{formatCurrency(payslips.reduce((sum, p) => sum + num(p.gross_pay), 0))}</Table.Th>
                    {dedNames.map((name) => (
                      <Table.Th key={name}>{formatCurrency(dedMaps.reduce((sum, m) => sum + (m[name] ?? 0), 0))}</Table.Th>
                    ))}
                    <Table.Th>{formatCurrency(payslips.reduce((sum, p) => sum + num(p.net_pay), 0))}</Table.Th>
                    <Table.Th />
                  </Table.Tr>
                </Table.Tfoot>
              </Table>
            </Table.ScrollContainer>
          </Paper>
        );
      })()}
    </Stack>
  );
}

function SalariesTab() {
  const queryClient = useQueryClient();
  const [modalOpen, setModalOpen] = useState(false);

  const { data: usersData } = useQuery({ queryKey: ['users-simple'], queryFn: () => getUsers({ per_page: 200 }) });
  const { data, isLoading } = useQuery({ queryKey: ['staff-salaries'], queryFn: () => getStaffSalaries() });

  const users = (usersData?.data?.data ?? []) as { id: string; name: string }[];
  const salaries = data?.data?.data ?? [];

  const form = useForm({
    initialValues: { user_id: '', basic_salary: 0, effective_from: new Date().toISOString().slice(0, 10), notes: '' },
    validate: {
      user_id: (v) => (v ? null : 'Required'),
      basic_salary: (v) => (v > 0 ? null : 'Must be greater than 0'),
    },
  });

  const createMut = useMutation({
    mutationFn: (values: typeof form.values) => createStaffSalary(values),
    onSuccess: () => {
      notifications.show({ title: 'Success', message: 'Salary recorded', color: 'green' });
      queryClient.invalidateQueries({ queryKey: ['staff-salaries'] });
      setModalOpen(false);
      form.reset();
    },
  });

  const deleteMut = useMutation({
    mutationFn: (id: string) => deleteStaffSalary(id),
    onSuccess: () => {
      notifications.show({ title: 'Success', message: 'Salary record removed', color: 'green' });
      queryClient.invalidateQueries({ queryKey: ['staff-salaries'] });
    },
  });

  return (
    <Stack gap="md">
      <Group justify="flex-end">
        <Button leftSection={<IconPlus size={14} />} size="xs" onClick={() => setModalOpen(true)}>Add Salary</Button>
      </Group>

      {isLoading ? <Center py="md"><Loader size="sm" /></Center> : salaries.length === 0 ? (
        <Text c="dimmed" size="sm">No salary records yet.</Text>
      ) : (
        <Table striped highlightOnHover>
          <Table.Thead>
            <Table.Tr>
              <Table.Th>#</Table.Th>
              <Table.Th>Employee</Table.Th>
              <Table.Th>Basic Salary</Table.Th>
              <Table.Th>Effective From</Table.Th>
              <Table.Th />
            </Table.Tr>
          </Table.Thead>
          <Table.Tbody>
            {salaries.map((s, i) => (
              <Table.Tr key={s.id}>
                <Table.Td>{i + 1}</Table.Td>
                <Table.Td>{s.user?.name ?? '—'}</Table.Td>
                <Table.Td>{formatCurrency(s.basic_salary)}</Table.Td>
                <Table.Td>{s.effective_from}</Table.Td>
                <Table.Td>
                  <ActionIcon variant="subtle" size="sm" color="red" onClick={() => deleteMut.mutate(s.id)}>
                    <IconTrash size={14} />
                  </ActionIcon>
                </Table.Td>
              </Table.Tr>
            ))}
          </Table.Tbody>
        </Table>
      )}

      <Modal opened={modalOpen} onClose={() => setModalOpen(false)} title="Add Salary Record">
        <form onSubmit={form.onSubmit((values) => createMut.mutate(values))}>
          <Stack gap="sm">
            <Select label="Employee" required searchable data={users.map((u) => ({ value: u.id, label: u.name }))} {...form.getInputProps('user_id')} />
            <NumberInput label="Basic Salary" required min={0} {...form.getInputProps('basic_salary')} />
            <TextInput label="Effective From" type="date" required {...form.getInputProps('effective_from')} />
            <Group justify="flex-end">
              <Button variant="default" onClick={() => setModalOpen(false)}>Cancel</Button>
              <Button type="submit" loading={createMut.isPending}>Save</Button>
            </Group>
          </Stack>
        </form>
      </Modal>
    </Stack>
  );
}

function LoansAdvancesTab() {
  const [view, setView] = useState<'loans' | 'advances'>('loans');
  return (
    <Stack gap="md">
      <SegmentedControl value={view} onChange={(v) => setView(v as 'loans' | 'advances')} data={[
        { value: 'loans', label: 'Loans' },
        { value: 'advances', label: 'Salary Advances' },
      ]} style={{ alignSelf: 'flex-start' }} />
      {view === 'loans' ? <LoansPanel /> : <AdvancesPanel />}
    </Stack>
  );
}

function LoansPanel() {
  const queryClient = useQueryClient();
  const [modalOpen, setModalOpen] = useState(false);
  const [paymentsFor, setPaymentsFor] = useState<Loan | null>(null);

  const { data: usersData } = useQuery({ queryKey: ['users-simple'], queryFn: () => getUsers({ per_page: 200 }) });
  const { data, isLoading } = useQuery({ queryKey: ['loans'], queryFn: () => getLoans() });

  const users = (usersData?.data?.data ?? []) as { id: string; name: string }[];
  const loans = data?.data?.data ?? [];

  const form = useForm({
    initialValues: { user_id: '', principal: 0, monthly_installment: 0, issued_date: new Date().toISOString().slice(0, 10), notes: '' },
    validate: {
      user_id: (v) => (v ? null : 'Required'),
      principal: (v) => (v > 0 ? null : 'Must be greater than 0'),
      monthly_installment: (v) => (v > 0 ? null : 'Must be greater than 0'),
    },
  });

  const createMut = useMutation({
    mutationFn: (values: typeof form.values) => createLoan(values),
    onSuccess: () => {
      notifications.show({ title: 'Success', message: 'Loan recorded', color: 'green' });
      queryClient.invalidateQueries({ queryKey: ['loans'] });
      setModalOpen(false);
      form.reset();
    },
    onError: (err: any) => notifications.show({
      title: 'Error', message: err.response?.data?.message || 'Failed to record loan', color: 'red',
    }),
  });

  const cancelMut = useMutation({
    mutationFn: (id: string) => cancelLoan(id),
    onSuccess: () => {
      notifications.show({ title: 'Success', message: 'Loan cancelled', color: 'green' });
      queryClient.invalidateQueries({ queryKey: ['loans'] });
    },
    onError: (err: any) => notifications.show({
      title: 'Error', message: err.response?.data?.message || 'Failed to cancel loan', color: 'red',
    }),
  });

  const confirmCancel = (loan: Loan) => {
    modals.openConfirmModal({
      title: 'Cancel Loan',
      children: <Text size="sm">Cancel this loan for {loan.user?.name}? Only possible while no repayment has been collected yet.</Text>,
      labels: { confirm: 'Cancel Loan', cancel: 'Back' },
      confirmProps: { color: 'red' },
      onConfirm: () => cancelMut.mutate(loan.id),
    });
  };

  const statusColors: Record<string, string> = { active: 'blue', paid_off: 'green', cancelled: 'gray' };

  return (
    <Stack gap="md">
      <Group justify="flex-end">
        <Button leftSection={<IconPlus size={14} />} size="xs" onClick={() => setModalOpen(true)}>Add Loan</Button>
      </Group>

      {isLoading ? <Center py="md"><Loader size="sm" /></Center> : loans.length === 0 ? (
        <Text c="dimmed" size="sm">No loans recorded yet.</Text>
      ) : (
        <Table.ScrollContainer minWidth={650}>
          <Table striped highlightOnHover>
            <Table.Thead>
              <Table.Tr>
                <Table.Th>#</Table.Th>
                <Table.Th>Employee</Table.Th>
                <Table.Th>Principal</Table.Th>
                <Table.Th>Balance</Table.Th>
                <Table.Th>Monthly Installment</Table.Th>
                <Table.Th>Status</Table.Th>
                <Table.Th />
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {loans.map((l, i) => (
                <Table.Tr key={l.id}>
                  <Table.Td>{i + 1}</Table.Td>
                  <Table.Td>{l.user?.name ?? '—'}</Table.Td>
                  <Table.Td>{formatCurrency(l.principal)}</Table.Td>
                  <Table.Td fw={600}>{formatCurrency(l.balance)}</Table.Td>
                  <Table.Td>{formatCurrency(l.monthly_installment)}</Table.Td>
                  <Table.Td><Badge size="sm" color={statusColors[l.status]}>{l.status.replace('_', ' ')}</Badge></Table.Td>
                  <Table.Td>
                    <Group gap="xs">
                      <Button size="xs" variant="light" onClick={() => setPaymentsFor(l)}>Payments</Button>
                      {l.status === 'active' && l.balance === l.principal && (
                        <ActionIcon variant="subtle" size="sm" color="red" onClick={() => confirmCancel(l)}>
                          <IconTrash size={14} />
                        </ActionIcon>
                      )}
                    </Group>
                  </Table.Td>
                </Table.Tr>
              ))}
            </Table.Tbody>
            <Table.Tfoot>
              <Table.Tr>
                <Table.Th />
                <Table.Th>Total</Table.Th>
                <Table.Th>{formatCurrency(loans.reduce((sum, l) => sum + num(l.principal), 0))}</Table.Th>
                <Table.Th>{formatCurrency(loans.reduce((sum, l) => sum + num(l.balance), 0))}</Table.Th>
                <Table.Th>{formatCurrency(loans.reduce((sum, l) => sum + num(l.monthly_installment), 0))}</Table.Th>
                <Table.Th />
                <Table.Th />
              </Table.Tr>
            </Table.Tfoot>
          </Table>
        </Table.ScrollContainer>
      )}

      <Modal opened={modalOpen} onClose={() => setModalOpen(false)} title="Add Loan">
        <form onSubmit={form.onSubmit((values) => createMut.mutate(values))}>
          <Stack gap="sm">
            <Select label="Employee" required searchable data={users.map((u) => ({ value: u.id, label: u.name }))} {...form.getInputProps('user_id')} />
            <NumberInput label="Principal" required min={0} {...form.getInputProps('principal')} />
            <NumberInput label="Monthly Installment" required min={0} {...form.getInputProps('monthly_installment')} />
            <TextInput label="Issued Date" type="date" required {...form.getInputProps('issued_date')} />
            <Textarea label="Notes" minRows={2} {...form.getInputProps('notes')} />
            <Group justify="flex-end">
              <Button variant="default" onClick={() => setModalOpen(false)}>Cancel</Button>
              <Button type="submit" loading={createMut.isPending}>Save</Button>
            </Group>
          </Stack>
        </form>
      </Modal>

      {paymentsFor && <LoanPaymentsModal loan={paymentsFor} onClose={() => setPaymentsFor(null)} />}
    </Stack>
  );
}

function LoanPaymentsModal({ loan, onClose }: { loan: Loan; onClose: () => void }) {
  const { data, isLoading } = useQuery({ queryKey: ['loan-payments', loan.id], queryFn: () => getLoanPayments(loan.id) });
  const payments = data?.data?.data ?? [];

  return (
    <Modal opened onClose={onClose} title={`Payments — ${loan.user?.name ?? ''}`} size="md">
      {isLoading ? <Center py="md"><Loader size="sm" /></Center> : payments.length === 0 ? (
        <Text c="dimmed" size="sm">No repayments collected yet.</Text>
      ) : (
        <Table>
          <Table.Thead>
            <Table.Tr>
              <Table.Th>#</Table.Th>
              <Table.Th>Month</Table.Th>
              <Table.Th>Amount</Table.Th>
              <Table.Th>Balance After</Table.Th>
            </Table.Tr>
          </Table.Thead>
          <Table.Tbody>
            {payments.map((p, i) => (
              <Table.Tr key={p.id}>
                <Table.Td>{i + 1}</Table.Td>
                <Table.Td>{p.payroll_run?.month_key ?? 'Manual'}</Table.Td>
                <Table.Td>{formatCurrency(p.amount)}</Table.Td>
                <Table.Td>{formatCurrency(p.balance_after)}</Table.Td>
              </Table.Tr>
            ))}
          </Table.Tbody>
          <Table.Tfoot>
            <Table.Tr>
              <Table.Th />
              <Table.Th>Total</Table.Th>
              <Table.Th>{formatCurrency(payments.reduce((sum, p) => sum + num(p.amount), 0))}</Table.Th>
              <Table.Th />
            </Table.Tr>
          </Table.Tfoot>
        </Table>
      )}
    </Modal>
  );
}

function AdvancesPanel() {
  const queryClient = useQueryClient();
  const [modalOpen, setModalOpen] = useState(false);

  const { data: usersData } = useQuery({ queryKey: ['users-simple'], queryFn: () => getUsers({ per_page: 200 }) });
  const { data, isLoading } = useQuery({ queryKey: ['salary-advances'], queryFn: () => getSalaryAdvances() });

  const users = (usersData?.data?.data ?? []) as { id: string; name: string }[];
  const advances = data?.data?.data ?? [];

  const form = useForm({
    initialValues: {
      user_id: '', amount: 0, issued_date: new Date().toISOString().slice(0, 10),
      recovery_month_key: new Date().toISOString().slice(0, 7), notes: '',
    },
    validate: {
      user_id: (v) => (v ? null : 'Required'),
      amount: (v) => (v > 0 ? null : 'Must be greater than 0'),
    },
  });

  const createMut = useMutation({
    mutationFn: (values: typeof form.values) => createSalaryAdvance(values),
    onSuccess: () => {
      notifications.show({ title: 'Success', message: 'Salary advance recorded', color: 'green' });
      queryClient.invalidateQueries({ queryKey: ['salary-advances'] });
      setModalOpen(false);
      form.reset();
    },
    onError: (err: any) => notifications.show({
      title: 'Error', message: err.response?.data?.message || 'Failed to record advance', color: 'red',
    }),
  });

  const cancelMut = useMutation({
    mutationFn: (id: string) => cancelSalaryAdvance(id),
    onSuccess: () => {
      notifications.show({ title: 'Success', message: 'Advance cancelled', color: 'green' });
      queryClient.invalidateQueries({ queryKey: ['salary-advances'] });
    },
    onError: (err: any) => notifications.show({
      title: 'Error', message: err.response?.data?.message || 'Failed to cancel advance', color: 'red',
    }),
  });

  const confirmCancel = (advance: SalaryAdvance) => {
    modals.openConfirmModal({
      title: 'Cancel Salary Advance',
      children: <Text size="sm">Cancel this advance for {advance.user?.name}?</Text>,
      labels: { confirm: 'Cancel Advance', cancel: 'Back' },
      confirmProps: { color: 'red' },
      onConfirm: () => cancelMut.mutate(advance.id),
    });
  };

  const statusColors: Record<string, string> = { pending: 'yellow', recovered: 'green', cancelled: 'gray' };

  return (
    <Stack gap="md">
      <Group justify="flex-end">
        <Button leftSection={<IconPlus size={14} />} size="xs" onClick={() => setModalOpen(true)}>Add Advance</Button>
      </Group>

      {isLoading ? <Center py="md"><Loader size="sm" /></Center> : advances.length === 0 ? (
        <Text c="dimmed" size="sm">No salary advances recorded yet.</Text>
      ) : (
        <Table striped highlightOnHover>
          <Table.Thead>
            <Table.Tr>
              <Table.Th>#</Table.Th>
              <Table.Th>Employee</Table.Th>
              <Table.Th>Amount</Table.Th>
              <Table.Th>Recovery Month</Table.Th>
              <Table.Th>Status</Table.Th>
              <Table.Th />
            </Table.Tr>
          </Table.Thead>
          <Table.Tbody>
            {advances.map((a, i) => (
              <Table.Tr key={a.id}>
                <Table.Td>{i + 1}</Table.Td>
                <Table.Td>{a.user?.name ?? '—'}</Table.Td>
                <Table.Td>{formatCurrency(a.amount)}</Table.Td>
                <Table.Td>{a.recovery_month_key}</Table.Td>
                <Table.Td><Badge size="sm" color={statusColors[a.status]}>{a.status}</Badge></Table.Td>
                <Table.Td>
                  {a.status === 'pending' && (
                    <ActionIcon variant="subtle" size="sm" color="red" onClick={() => confirmCancel(a)}>
                      <IconTrash size={14} />
                    </ActionIcon>
                  )}
                </Table.Td>
              </Table.Tr>
            ))}
          </Table.Tbody>
          <Table.Tfoot>
            <Table.Tr>
              <Table.Th />
              <Table.Th>Total</Table.Th>
              <Table.Th>{formatCurrency(advances.reduce((sum, a) => sum + num(a.amount), 0))}</Table.Th>
              <Table.Th />
              <Table.Th />
              <Table.Th />
            </Table.Tr>
          </Table.Tfoot>
        </Table>
      )}

      <Modal opened={modalOpen} onClose={() => setModalOpen(false)} title="Add Salary Advance">
        <form onSubmit={form.onSubmit((values) => createMut.mutate(values))}>
          <Stack gap="sm">
            <Select label="Employee" required searchable data={users.map((u) => ({ value: u.id, label: u.name }))} {...form.getInputProps('user_id')} />
            <NumberInput label="Amount" required min={0} {...form.getInputProps('amount')} />
            <TextInput label="Issued Date" type="date" required {...form.getInputProps('issued_date')} />
            <TextInput label="Recovery Month" type="month" required {...form.getInputProps('recovery_month_key')} />
            <Textarea label="Notes" minRows={2} {...form.getInputProps('notes')} />
            <Group justify="flex-end">
              <Button variant="default" onClick={() => setModalOpen(false)}>Cancel</Button>
              <Button type="submit" loading={createMut.isPending}>Save</Button>
            </Group>
          </Stack>
        </form>
      </Modal>
    </Stack>
  );
}

function CatalogTab({ kind }: { kind: 'allowance' | 'deduction' }) {
  const queryClient = useQueryClient();
  const isAllowance = kind === 'allowance';
  const [modalOpen, setModalOpen] = useState(false);
  const [editing, setEditing] = useState<Allowance | Deduction | null>(null);
  const [subscribingTo, setSubscribingTo] = useState<Allowance | Deduction | null>(null);

  const listQuery = useQuery({ queryKey: [`${kind}s`], queryFn: isAllowance ? getAllowances : getDeductions });
  const items = listQuery.data?.data?.data ?? [];

  const form = useForm({
    initialValues: { name: '', calculation_type: 'fixed' as 'fixed' | 'percent_of_basic', default_amount: 0, is_active: true },
    validate: { name: (v) => (v.length > 0 ? null : 'Required') },
  });

  const createMut = useMutation({
    mutationFn: (values: typeof form.values) => (isAllowance ? createAllowance(values) : createDeduction(values)),
    onSuccess: () => {
      notifications.show({ title: 'Success', message: `${isAllowance ? 'Allowance' : 'Deduction'} created`, color: 'green' });
      queryClient.invalidateQueries({ queryKey: [`${kind}s`] });
      closeModal();
    },
  });

  const updateMut = useMutation({
    mutationFn: (values: typeof form.values) => (isAllowance ? updateAllowance(editing!.id, values) : updateDeduction(editing!.id, values)),
    onSuccess: () => {
      notifications.show({ title: 'Success', message: 'Updated', color: 'green' });
      queryClient.invalidateQueries({ queryKey: [`${kind}s`] });
      closeModal();
    },
  });

  const deleteMut = useMutation({
    mutationFn: (id: string) => (isAllowance ? deleteAllowance(id) : deleteDeduction(id)),
    onSuccess: () => {
      notifications.show({ title: 'Success', message: 'Removed', color: 'green' });
      queryClient.invalidateQueries({ queryKey: [`${kind}s`] });
    },
  });

  const openCreate = () => { setEditing(null); form.reset(); setModalOpen(true); };
  const openEdit = (item: Allowance | Deduction) => {
    setEditing(item);
    form.setValues({ name: item.name, calculation_type: item.calculation_type, default_amount: item.default_amount, is_active: item.is_active });
    setModalOpen(true);
  };
  const closeModal = () => { setModalOpen(false); setEditing(null); form.reset(); };

  const confirmDelete = (item: Allowance | Deduction) => {
    modals.openConfirmModal({
      title: `Remove ${isAllowance ? 'Allowance' : 'Deduction'}`,
      children: <Text size="sm">Remove "{item.name}"?</Text>,
      labels: { confirm: 'Remove', cancel: 'Cancel' },
      confirmProps: { color: 'red' },
      onConfirm: () => deleteMut.mutate(item.id),
    });
  };

  return (
    <Stack gap="md">
      <Group justify="space-between">
        <Title order={4}>{isAllowance ? 'Allowances' : 'Deductions'}</Title>
        <Button leftSection={<IconPlus size={14} />} size="xs" onClick={openCreate}>Add {isAllowance ? 'Allowance' : 'Deduction'}</Button>
      </Group>

      {listQuery.isLoading ? <Center py="md"><Loader size="sm" /></Center> : items.length === 0 ? (
        <Text c="dimmed" size="sm">None configured yet.</Text>
      ) : (
        <Table striped highlightOnHover>
          <Table.Thead>
            <Table.Tr>
              <Table.Th>#</Table.Th>
              <Table.Th>Name</Table.Th>
              <Table.Th>Type</Table.Th>
              <Table.Th>Default Amount</Table.Th>
              <Table.Th>Actions</Table.Th>
            </Table.Tr>
          </Table.Thead>
          <Table.Tbody>
            {items.map((item, i) => (
              <Table.Tr key={item.id}>
                <Table.Td>{i + 1}</Table.Td>
                <Table.Td fw={500}>{item.name}</Table.Td>
                <Table.Td><Badge size="sm" variant="light">{item.calculation_type === 'fixed' ? 'Fixed' : '% of Basic'}</Badge></Table.Td>
                <Table.Td>{item.calculation_type === 'fixed' ? formatCurrency(item.default_amount) : `${item.default_amount}%`}</Table.Td>
                <Table.Td>
                  <Group gap="xs">
                    <Button size="xs" variant="light" onClick={() => setSubscribingTo(item)}>Assign</Button>
                    <ActionIcon variant="subtle" size="sm" onClick={() => openEdit(item)}><IconEdit size={14} /></ActionIcon>
                    <ActionIcon variant="subtle" size="sm" color="red" onClick={() => confirmDelete(item)}><IconTrash size={14} /></ActionIcon>
                  </Group>
                </Table.Td>
              </Table.Tr>
            ))}
          </Table.Tbody>
        </Table>
      )}

      <Modal opened={modalOpen} onClose={closeModal} title={editing ? `Edit ${isAllowance ? 'Allowance' : 'Deduction'}` : `Add ${isAllowance ? 'Allowance' : 'Deduction'}`}>
        <form onSubmit={form.onSubmit((values) => editing ? updateMut.mutate(values) : createMut.mutate(values))}>
          <Stack gap="sm">
            <TextInput label="Name" required {...form.getInputProps('name')} />
            <Select label="Calculation" data={[
              { value: 'fixed', label: 'Fixed Amount' },
              { value: 'percent_of_basic', label: '% of Basic Salary' },
            ]} {...form.getInputProps('calculation_type')} />
            <NumberInput label={form.values.calculation_type === 'fixed' ? 'Default Amount' : 'Default Percent'} min={0} required {...form.getInputProps('default_amount')} />
            {editing && <Switch label="Active" {...form.getInputProps('is_active', { type: 'checkbox' })} />}
            <Group justify="flex-end">
              <Button variant="default" onClick={closeModal}>Cancel</Button>
              <Button type="submit" loading={createMut.isPending || updateMut.isPending}>{editing ? 'Save' : 'Create'}</Button>
            </Group>
          </Stack>
        </form>
      </Modal>

      {subscribingTo && (
        <SubscriptionModal kind={kind} item={subscribingTo} onClose={() => setSubscribingTo(null)} />
      )}
    </Stack>
  );
}

function SubscriptionModal({ kind, item, onClose }: { kind: 'allowance' | 'deduction'; item: Allowance | Deduction; onClose: () => void }) {
  const isAllowance = kind === 'allowance';
  const { data, isLoading } = useQuery({
    queryKey: [`${kind}-subscriptions`, item.id],
    queryFn: () => (isAllowance ? getAllowanceSubscriptions(item.id) : getDeductionSubscriptions(item.id)),
  });

  const subscribeMut = useMutation({
    mutationFn: (vars: { user_id: string; is_active: boolean }) =>
      (isAllowance ? subscribeAllowance(item.id, vars) : subscribeDeduction(item.id, vars)),
  });

  const users = data?.data?.data?.users ?? [];
  const subscriptions = data?.data?.data?.subscriptions ?? {};

  return (
    <Modal opened onClose={onClose} title={`Assign "${item.name}"`} size="md">
      {isLoading ? <Center py="md"><Loader size="sm" /></Center> : (
        <Stack gap="xs">
          {users.map((u) => {
            const sub = subscriptions[u.id];
            return (
              <Group key={u.id} justify="space-between">
                <Text size="sm">{u.name}</Text>
                <Switch
                  checked={sub?.is_active ?? false}
                  onChange={(e) => subscribeMut.mutate({ user_id: u.id, is_active: e.currentTarget.checked })}
                />
              </Group>
            );
          })}
        </Stack>
      )}
    </Modal>
  );
}

function StatutoryRatesTab() {
  const queryClient = useQueryClient();
  const [modalOpen, setModalOpen] = useState(false);
  const [editing, setEditing] = useState<StatutoryRate | null>(null);
  const [subscribingTo, setSubscribingTo] = useState<StatutoryRate | null>(null);

  const listQuery = useQuery({ queryKey: ['statutory-rates'], queryFn: getStatutoryRates });
  const items = listQuery.data?.data?.data ?? [];

  const form = useForm({
    initialValues: { name: '', employee_percent: 0, employer_percent: 0, reduces_taxable_income: false, is_active: true },
    validate: { name: (v) => (v.length > 0 ? null : 'Required') },
  });

  const createMut = useMutation({
    mutationFn: (values: typeof form.values) => createStatutoryRate(values),
    onSuccess: () => {
      notifications.show({ title: 'Success', message: 'Statutory rate created', color: 'green' });
      queryClient.invalidateQueries({ queryKey: ['statutory-rates'] });
      closeModal();
    },
  });

  const updateMut = useMutation({
    mutationFn: (values: typeof form.values) => updateStatutoryRate(editing!.id, values),
    onSuccess: () => {
      notifications.show({ title: 'Success', message: 'Updated', color: 'green' });
      queryClient.invalidateQueries({ queryKey: ['statutory-rates'] });
      closeModal();
    },
  });

  const deleteMut = useMutation({
    mutationFn: (id: string) => deleteStatutoryRate(id),
    onSuccess: () => {
      notifications.show({ title: 'Success', message: 'Removed', color: 'green' });
      queryClient.invalidateQueries({ queryKey: ['statutory-rates'] });
    },
  });

  const openCreate = () => { setEditing(null); form.reset(); setModalOpen(true); };
  const openEdit = (item: StatutoryRate) => {
    setEditing(item);
    form.setValues({
      name: item.name, employee_percent: item.employee_percent, employer_percent: item.employer_percent,
      reduces_taxable_income: item.reduces_taxable_income, is_active: item.is_active,
    });
    setModalOpen(true);
  };
  const closeModal = () => { setModalOpen(false); setEditing(null); form.reset(); };

  const confirmDelete = (item: StatutoryRate) => {
    modals.openConfirmModal({
      title: 'Remove Statutory Rate',
      children: <Text size="sm">Remove "{item.name}"?</Text>,
      labels: { confirm: 'Remove', cancel: 'Cancel' },
      confirmProps: { color: 'red' },
      onConfirm: () => deleteMut.mutate(item.id),
    });
  };

  return (
    <Stack gap="md">
      <Text size="xs" c="dimmed">
        NSSF, WCF and SDL are pre-configured — add NHIF or anything else here. Employee % is deducted from pay;
        Employer % is a business cost only, never deducted. Use "Assign" to opt individual employees out (e.g. not an NSSF member).
      </Text>
      <Group justify="space-between">
        <Title order={4}>Statutory Rates</Title>
        <Button leftSection={<IconPlus size={14} />} size="xs" onClick={openCreate}>Add Rate</Button>
      </Group>

      {listQuery.isLoading ? <Center py="md"><Loader size="sm" /></Center> : items.length === 0 ? (
        <Text c="dimmed" size="sm">None configured yet.</Text>
      ) : (
        <Table striped highlightOnHover>
          <Table.Thead>
            <Table.Tr>
              <Table.Th>#</Table.Th>
              <Table.Th>Name</Table.Th>
              <Table.Th>Employee %</Table.Th>
              <Table.Th>Employer %</Table.Th>
              <Table.Th>Pre-tax</Table.Th>
              <Table.Th>Actions</Table.Th>
            </Table.Tr>
          </Table.Thead>
          <Table.Tbody>
            {items.map((item, i) => (
              <Table.Tr key={item.id}>
                <Table.Td>{i + 1}</Table.Td>
                <Table.Td fw={500}>{item.name}</Table.Td>
                <Table.Td>{item.employee_percent}%</Table.Td>
                <Table.Td>{item.employer_percent}%</Table.Td>
                <Table.Td><Badge size="sm" variant="light" color={item.reduces_taxable_income ? 'blue' : 'gray'}>{item.reduces_taxable_income ? 'Yes' : 'No'}</Badge></Table.Td>
                <Table.Td>
                  <Group gap="xs">
                    <Button size="xs" variant="light" onClick={() => setSubscribingTo(item)}>Assign</Button>
                    <ActionIcon variant="subtle" size="sm" onClick={() => openEdit(item)}><IconEdit size={14} /></ActionIcon>
                    <ActionIcon variant="subtle" size="sm" color="red" onClick={() => confirmDelete(item)}><IconTrash size={14} /></ActionIcon>
                  </Group>
                </Table.Td>
              </Table.Tr>
            ))}
          </Table.Tbody>
        </Table>
      )}

      <Modal opened={modalOpen} onClose={closeModal} title={editing ? 'Edit Statutory Rate' : 'Add Statutory Rate'}>
        <form onSubmit={form.onSubmit((values) => editing ? updateMut.mutate(values) : createMut.mutate(values))}>
          <Stack gap="sm">
            <TextInput label="Name" placeholder="e.g. NHIF" required {...form.getInputProps('name')} />
            <NumberInput label="Employee %" min={0} max={100} {...form.getInputProps('employee_percent')} />
            <NumberInput label="Employer %" min={0} max={100} {...form.getInputProps('employer_percent')} />
            <Switch label="Deduct before PAYE (pre-tax, like NSSF)" {...form.getInputProps('reduces_taxable_income', { type: 'checkbox' })} />
            {editing && <Switch label="Active" {...form.getInputProps('is_active', { type: 'checkbox' })} />}
            <Group justify="flex-end">
              <Button variant="default" onClick={closeModal}>Cancel</Button>
              <Button type="submit" loading={createMut.isPending || updateMut.isPending}>{editing ? 'Save' : 'Create'}</Button>
            </Group>
          </Stack>
        </form>
      </Modal>

      {subscribingTo && (
        <StatutorySubscriptionModal item={subscribingTo} onClose={() => setSubscribingTo(null)} />
      )}
    </Stack>
  );
}

function StatutorySubscriptionModal({ item, onClose }: { item: StatutoryRate; onClose: () => void }) {
  const { data, isLoading } = useQuery({
    queryKey: ['statutory-rate-subscriptions', item.id],
    queryFn: () => getStatutoryRateSubscriptions(item.id),
  });

  const subscribeMut = useMutation({
    mutationFn: (vars: { user_id: string; is_active: boolean }) => subscribeStatutoryRate(item.id, vars),
  });

  const users = data?.data?.data?.users ?? [];
  const subscriptions = data?.data?.data?.subscriptions ?? {};

  return (
    <Modal opened onClose={onClose} title={`Assign "${item.name}"`} size="md">
      <Text size="xs" c="dimmed" mb="sm">On = subject to this rate. Off = exempt (opted out).</Text>
      {isLoading ? <Center py="md"><Loader size="sm" /></Center> : (
        <Stack gap="xs">
          {users.map((u) => {
            const sub = subscriptions[u.id];
            return (
              <Group key={u.id} justify="space-between">
                <Text size="sm">{u.name}</Text>
                <Switch
                  checked={sub?.is_active ?? true}
                  onChange={(e) => subscribeMut.mutate({ user_id: u.id, is_active: e.currentTarget.checked })}
                />
              </Group>
            );
          })}
        </Stack>
      )}
    </Modal>
  );
}

function SettingsTab() {
  const queryClient = useQueryClient();
  const { data, isLoading } = useQuery({ queryKey: ['payroll-settings'], queryFn: getPayrollSettings });

  const [brackets, setBrackets] = useState<PayeBracket[]>([]);
  const [loaded, setLoaded] = useState(false);
  const [exemptionModal, setExemptionModal] = useState<'paye' | 'attendance' | 'report' | null>(null);

  if (data?.data?.data && !loaded) {
    setBrackets(data.data.data.paye_brackets);
    setLoaded(true);
  }

  const saveMut = useMutation({
    mutationFn: () => updatePayrollSettings({ paye_brackets: brackets }),
    onSuccess: () => {
      notifications.show({ title: 'Success', message: 'Payroll settings saved', color: 'green' });
      queryClient.invalidateQueries({ queryKey: ['payroll-settings'] });
    },
    onError: (err: any) => notifications.show({
      title: 'Error', message: err.response?.data?.message || 'Failed to save', color: 'red',
    }),
  });

  const updateBracket = (i: number, field: keyof PayeBracket, value: number | null) => {
    setBrackets((prev) => prev.map((b, idx) => idx === i ? { ...b, [field]: value } : b));
  };

  const addBracket = () => setBrackets((prev) => [...prev, { min: 0, max: null, rate: 0, base_deduction: 0 }]);
  const removeBracket = (i: number) => setBrackets((prev) => prev.filter((_, idx) => idx !== i));

  if (isLoading) return <Center py="md"><Loader size="sm" /></Center>;

  return (
    <Stack gap="md">
      <Alert color="yellow" icon={<IconAlertTriangle size={18} />} title="Verify before real use">
        These PAYE brackets (and the default NSSF/WCF/SDL rates under the "Statutory Rates" tab) are seeded
        with commonly-cited default figures — they are <strong>not guaranteed to be current</strong>.
        Tanzania's tax brackets and statutory percentages change with the annual Finance Act. Please verify
        with TRA/your accountant before relying on this for a real payroll run.
      </Alert>

      <Title order={4}>PAYE Brackets</Title>
      <Text size="xs" c="dimmed">tax = base_deduction + rate% × (taxable_income − min). Leave "Max" blank for the top (uncapped) bracket.</Text>
      <Table>
        <Table.Thead>
          <Table.Tr>
            <Table.Th>Min</Table.Th>
            <Table.Th>Max</Table.Th>
            <Table.Th>Rate %</Table.Th>
            <Table.Th>Base Deduction</Table.Th>
            <Table.Th />
          </Table.Tr>
        </Table.Thead>
        <Table.Tbody>
          {brackets.map((b, i) => (
            <Table.Tr key={i}>
              <Table.Td><NumberInput size="xs" value={b.min} onChange={(v) => updateBracket(i, 'min', Number(v) || 0)} /></Table.Td>
              <Table.Td><NumberInput size="xs" value={b.max ?? undefined} placeholder="No limit" onChange={(v) => updateBracket(i, 'max', v === '' ? null : Number(v))} /></Table.Td>
              <Table.Td><NumberInput size="xs" value={b.rate} onChange={(v) => updateBracket(i, 'rate', Number(v) || 0)} /></Table.Td>
              <Table.Td><NumberInput size="xs" value={b.base_deduction} onChange={(v) => updateBracket(i, 'base_deduction', Number(v) || 0)} /></Table.Td>
              <Table.Td><ActionIcon variant="subtle" color="red" size="sm" onClick={() => removeBracket(i)}><IconTrash size={14} /></ActionIcon></Table.Td>
            </Table.Tr>
          ))}
        </Table.Tbody>
      </Table>
      <Button size="xs" variant="light" leftSection={<IconPlus size={14} />} onClick={addBracket} style={{ alignSelf: 'flex-start' }}>
        Add Bracket
      </Button>

      <Stack gap="sm" mt="md">
        <Group justify="space-between">
          <div>
            <Text size="sm" fw={600}>PAYE Exemptions</Text>
            <Text size="xs" c="dimmed">Opt individual employees out of PAYE (e.g. a PAYE-exempt category) — on by default for everyone.</Text>
          </div>
          <Button size="xs" variant="light" onClick={() => setExemptionModal('paye')}>Assign</Button>
        </Group>
        <Group justify="space-between">
          <div>
            <Text size="sm" fw={600}>Attendance Penalty Exemptions</Text>
            <Text size="xs" c="dimmed">Opt individual employees out of attendance-lateness deductions on payroll — on by default for everyone.</Text>
          </div>
          <Button size="xs" variant="light" onClick={() => setExemptionModal('attendance')}>Assign</Button>
        </Group>
        <Group justify="space-between">
          <div>
            <Text size="sm" fw={600}>Late Report Penalty Exemptions</Text>
            <Text size="xs" c="dimmed">Opt individual employees out of late-report deductions on payroll — on by default for everyone.</Text>
          </div>
          <Button size="xs" variant="light" onClick={() => setExemptionModal('report')}>Assign</Button>
        </Group>
      </Stack>

      <Group justify="flex-end">
        <Button loading={saveMut.isPending} onClick={() => saveMut.mutate()}>Save Settings</Button>
      </Group>

      {exemptionModal && <ExemptionSubscriptionModal kind={exemptionModal} onClose={() => setExemptionModal(null)} />}
    </Stack>
  );
}

const EXEMPTION_KINDS = {
  paye: { title: 'Assign PAYE', hint: 'On = subject to PAYE. Off = exempt (opted out).', queryKey: 'paye-subscriptions', getFn: getPayeSubscriptions, subscribeFn: subscribePaye },
  attendance: { title: 'Assign Attendance Penalties', hint: 'On = subject to attendance-lateness deductions. Off = exempt.', queryKey: 'attendance-penalty-subscriptions', getFn: getAttendancePenaltySubscriptions, subscribeFn: subscribeAttendancePenalty },
  report: { title: 'Assign Late Report Penalties', hint: 'On = subject to late-report deductions. Off = exempt.', queryKey: 'report-penalty-subscriptions', getFn: getReportPenaltySubscriptions, subscribeFn: subscribeReportPenalty },
} as const;

function ExemptionSubscriptionModal({ kind, onClose }: { kind: keyof typeof EXEMPTION_KINDS; onClose: () => void }) {
  const { title, hint, queryKey, getFn, subscribeFn } = EXEMPTION_KINDS[kind];
  const { data, isLoading } = useQuery({ queryKey: [queryKey], queryFn: getFn });

  const subscribeMut = useMutation({
    mutationFn: (vars: { user_id: string; is_active: boolean }) => subscribeFn(vars),
  });

  const users = data?.data?.data?.users ?? [];
  const subscriptions = data?.data?.data?.subscriptions ?? {};

  return (
    <Modal opened onClose={onClose} title={title} size="md">
      <Text size="xs" c="dimmed" mb="sm">{hint}</Text>
      {isLoading ? <Center py="md"><Loader size="sm" /></Center> : (
        <Stack gap="xs">
          {users.map((u) => {
            const sub = subscriptions[u.id];
            return (
              <Group key={u.id} justify="space-between">
                <Text size="sm">{u.name}</Text>
                <Switch
                  checked={sub?.is_active ?? true}
                  onChange={(e) => subscribeMut.mutate({ user_id: u.id, is_active: e.currentTarget.checked })}
                />
              </Group>
            );
          })}
        </Stack>
      )}
    </Modal>
  );
}

function MyPayslipsTab() {
  const { data, isLoading } = useQuery({ queryKey: ['my-payslips'], queryFn: getMyPayslips });
  const payslips = data?.data?.data ?? [];

  const download = async (payslipId: string, mk: string) => {
    try {
      const res = await downloadMyPayslipPdf(payslipId);
      downloadBlob(res.data, `payslip-${mk}.pdf`);
    } catch {
      notifications.show({ message: 'Failed to download payslip', color: 'red' });
    }
  };

  if (isLoading) return <Center py="md"><Loader size="sm" /></Center>;
  if (payslips.length === 0) return <Text c="dimmed" size="sm">No payslips yet.</Text>;

  return (
    <Stack gap="xs">
      <Text size="xs" c="dimmed">
        A "Draft" row is this period's payroll still being prepared — deductions shown are current but may still
        change until it's finalized. A downloadable payslip is only available once finalized.
      </Text>
      <Table.ScrollContainer minWidth={700}>
        <Table striped highlightOnHover>
          <Table.Thead>
            <Table.Tr>
              <Table.Th>#</Table.Th>
              <Table.Th>Month</Table.Th>
              <Table.Th>Status</Table.Th>
              <Table.Th>Gross Pay</Table.Th>
              <Table.Th>Deductions</Table.Th>
              <Table.Th>Net Pay</Table.Th>
              <Table.Th />
            </Table.Tr>
          </Table.Thead>
          <Table.Tbody>
            {payslips.map((p, i) => {
              const finalized = p.payroll_run?.status === 'finalized';
              return (
                <Table.Tr key={p.id}>
                  <Table.Td>{i + 1}</Table.Td>
                  <Table.Td>{p.payroll_run?.month_key ?? '—'}</Table.Td>
                  <Table.Td><Badge size="sm" color={finalized ? 'green' : 'yellow'}>{finalized ? 'Finalized' : 'Draft'}</Badge></Table.Td>
                  <Table.Td>{formatCurrency(p.gross_pay)}</Table.Td>
                  <Table.Td>
                    {deductionItems(p).length === 0 ? <Text size="xs" c="dimmed">—</Text> : (
                      <Stack gap={2}>
                        {deductionItems(p).map((it, idx) => (
                          <Text size="xs" key={idx}>{it.name}: {formatCurrency(it.amount)}</Text>
                        ))}
                      </Stack>
                    )}
                  </Table.Td>
                  <Table.Td fw={600}>{formatCurrency(p.net_pay)}</Table.Td>
                  <Table.Td>
                    {finalized ? (
                      <ActionIcon variant="subtle" size="sm" onClick={() => download(p.id, p.payroll_run?.month_key ?? '')}>
                        <IconDownload size={14} />
                      </ActionIcon>
                    ) : (
                      <Text size="xs" c="dimmed">—</Text>
                    )}
                  </Table.Td>
                </Table.Tr>
              );
            })}
          </Table.Tbody>
          <Table.Tfoot>
            <Table.Tr>
              <Table.Th />
              <Table.Th>Total</Table.Th>
              <Table.Th />
              <Table.Th>{formatCurrency(payslips.reduce((sum, p) => sum + num(p.gross_pay), 0))}</Table.Th>
              <Table.Th />
              <Table.Th>{formatCurrency(payslips.reduce((sum, p) => sum + num(p.net_pay), 0))}</Table.Th>
              <Table.Th />
            </Table.Tr>
          </Table.Tfoot>
        </Table>
      </Table.ScrollContainer>
    </Stack>
  );
}
