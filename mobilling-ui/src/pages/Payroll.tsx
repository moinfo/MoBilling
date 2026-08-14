import { useState } from 'react';
import {
  Title, Text, Tabs, Paper, Table, Badge, Button, Group, Stack, SimpleGrid,
  Modal, TextInput, Select, NumberInput, ActionIcon, Switch, Center, Loader, Alert,
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
  getPayrollRuns, getPayrollRun, generatePayrollRun, finalizePayrollRun, downloadPayslipPdf,
  getMyPayslips, downloadMyPayslipPdf,
  PayeBracket, Allowance, Deduction, PayrollRun,
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

export default function Payroll() {
  const { can } = usePermissions();
  const canManage = can('payroll.manage');
  const canView = can('payroll.manage') || can('payroll.view');

  return (
    <Stack gap="lg">
      <Title order={2}>Payroll</Title>
      <Tabs defaultValue="runs" keepMounted={false}>
        <Tabs.List>
          {canView && <Tabs.Tab value="runs">Runs</Tabs.Tab>}
          {canManage && <Tabs.Tab value="salaries">Salaries</Tabs.Tab>}
          {canManage && <Tabs.Tab value="allowances">Allowances</Tabs.Tab>}
          {canManage && <Tabs.Tab value="deductions">Deductions</Tabs.Tab>}
          {canManage && <Tabs.Tab value="settings">Settings</Tabs.Tab>}
          <Tabs.Tab value="mine">My Payslips</Tabs.Tab>
        </Tabs.List>

        {canView && <Tabs.Panel value="runs" pt="md"><RunsTab canManage={canManage} /></Tabs.Panel>}
        {canManage && <Tabs.Panel value="salaries" pt="md"><SalariesTab /></Tabs.Panel>}
        {canManage && <Tabs.Panel value="allowances" pt="md"><CatalogTab kind="allowance" /></Tabs.Panel>}
        {canManage && <Tabs.Panel value="deductions" pt="md"><CatalogTab kind="deduction" /></Tabs.Panel>}
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
                    <Button size="xs" variant="light" color="green" leftSection={<IconLock size={14} />} onClick={() => confirmFinalize(r)}>
                      Finalize
                    </Button>
                  )}
                </Table.Td>
              </Table.Tr>
            ))}
          </Table.Tbody>
        </Table>
      )}

      {expandedRun && runDetail?.data?.data && (
        <Paper withBorder p="md" radius="md">
          <Title order={5} mb="sm">Payslips — {runDetail.data.data.month_key}</Title>
          <Table.ScrollContainer minWidth={700}>
            <Table striped highlightOnHover>
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>Employee</Table.Th>
                  <Table.Th>Gross</Table.Th>
                  <Table.Th>Deductions</Table.Th>
                  <Table.Th>Net Pay</Table.Th>
                  <Table.Th />
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {(runDetail.data.data.payslips ?? []).map((p) => (
                  <Table.Tr key={p.id}>
                    <Table.Td>{p.user?.name ?? '—'}</Table.Td>
                    <Table.Td>{formatCurrency(p.gross_pay)}</Table.Td>
                    <Table.Td>{formatCurrency(p.nssf_employee_amount + p.paye_amount + p.other_deductions_total)}</Table.Td>
                    <Table.Td fw={600}>{formatCurrency(p.net_pay)}</Table.Td>
                    <Table.Td>
                      <ActionIcon variant="subtle" size="sm" onClick={() => downloadPdf(p.id, p.user?.name ?? 'payslip', runDetail.data!.data.month_key)}>
                        <IconDownload size={14} />
                      </ActionIcon>
                    </Table.Td>
                  </Table.Tr>
                ))}
              </Table.Tbody>
            </Table>
          </Table.ScrollContainer>
        </Paper>
      )}
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
              <Table.Th>Employee</Table.Th>
              <Table.Th>Basic Salary</Table.Th>
              <Table.Th>Effective From</Table.Th>
              <Table.Th />
            </Table.Tr>
          </Table.Thead>
          <Table.Tbody>
            {salaries.map((s) => (
              <Table.Tr key={s.id}>
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
              <Table.Th>Name</Table.Th>
              <Table.Th>Type</Table.Th>
              <Table.Th>Default Amount</Table.Th>
              <Table.Th>Actions</Table.Th>
            </Table.Tr>
          </Table.Thead>
          <Table.Tbody>
            {items.map((item) => (
              <Table.Tr key={item.id}>
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

function SettingsTab() {
  const queryClient = useQueryClient();
  const { data, isLoading } = useQuery({ queryKey: ['payroll-settings'], queryFn: getPayrollSettings });

  const [brackets, setBrackets] = useState<PayeBracket[]>([]);
  const [rates, setRates] = useState({ nssf_employee_percent: 10, nssf_employer_percent: 10, wcf_percent: 0.5, sdl_percent: 3.5 });
  const [loaded, setLoaded] = useState(false);

  if (data?.data?.data && !loaded) {
    setBrackets(data.data.data.paye_brackets);
    setRates({
      nssf_employee_percent: data.data.data.nssf_employee_percent,
      nssf_employer_percent: data.data.data.nssf_employer_percent,
      wcf_percent: data.data.data.wcf_percent,
      sdl_percent: data.data.data.sdl_percent,
    });
    setLoaded(true);
  }

  const saveMut = useMutation({
    mutationFn: () => updatePayrollSettings({ paye_brackets: brackets, ...rates }),
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
        These statutory rates (PAYE brackets, NSSF/WCF/SDL) are seeded with commonly-cited default figures —
        they are <strong>not guaranteed to be current</strong>. Tanzania's tax brackets and NSSF/WCF/SDL
        percentages change with the annual Finance Act. Please verify with TRA/your accountant before
        relying on this for a real payroll run.
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

      <Title order={4} mt="md">NSSF / WCF / SDL</Title>
      <SimpleGrid cols={{ base: 2, sm: 4 }}>
        <NumberInput label="NSSF (Employee) %" min={0} max={100} value={rates.nssf_employee_percent} onChange={(v) => setRates((r) => ({ ...r, nssf_employee_percent: Number(v) || 0 }))} />
        <NumberInput label="NSSF (Employer) %" min={0} max={100} value={rates.nssf_employer_percent} onChange={(v) => setRates((r) => ({ ...r, nssf_employer_percent: Number(v) || 0 }))} />
        <NumberInput label="WCF %" min={0} max={100} value={rates.wcf_percent} onChange={(v) => setRates((r) => ({ ...r, wcf_percent: Number(v) || 0 }))} />
        <NumberInput label="SDL %" min={0} max={100} value={rates.sdl_percent} onChange={(v) => setRates((r) => ({ ...r, sdl_percent: Number(v) || 0 }))} />
      </SimpleGrid>

      <Group justify="flex-end">
        <Button loading={saveMut.isPending} onClick={() => saveMut.mutate()}>Save Settings</Button>
      </Group>
    </Stack>
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
    <Table striped highlightOnHover>
      <Table.Thead>
        <Table.Tr>
          <Table.Th>Month</Table.Th>
          <Table.Th>Gross Pay</Table.Th>
          <Table.Th>Net Pay</Table.Th>
          <Table.Th />
        </Table.Tr>
      </Table.Thead>
      <Table.Tbody>
        {payslips.map((p) => (
          <Table.Tr key={p.id}>
            <Table.Td>{p.payroll_run?.month_key ?? '—'}</Table.Td>
            <Table.Td>{formatCurrency(p.gross_pay)}</Table.Td>
            <Table.Td fw={600}>{formatCurrency(p.net_pay)}</Table.Td>
            <Table.Td>
              <ActionIcon variant="subtle" size="sm" onClick={() => download(p.id, p.payroll_run?.month_key ?? '')}>
                <IconDownload size={14} />
              </ActionIcon>
            </Table.Td>
          </Table.Tr>
        ))}
      </Table.Tbody>
    </Table>
  );
}
