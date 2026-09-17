import { useState } from 'react';
import { Title, Table, Text, Group, Pagination, ActionIcon, Modal, Button, TextInput, NumberInput, Select, Stack, Textarea, FileInput, Anchor, Badge, Tooltip } from '@mantine/core';
import { DateInput } from '@mantine/dates';
import { useForm } from '@mantine/form';
import { useDebouncedValue } from '@mantine/hooks';
import { modals } from '@mantine/modals';
import { notifications } from '@mantine/notifications';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { IconPlus, IconEdit, IconTrash, IconSearch, IconUpload, IconDownload, IconMessage, IconFileSpreadsheet, IconAlertTriangle, IconNote } from '@tabler/icons-react';
import dayjs from 'dayjs';
import {
  getSystemRecords, createSystemRecord, updateSystemRecord, deleteSystemRecord,
  toggleSmsConfirmation, toggleStatementConfirmation, updateReconciliationNote, SystemRecord, SystemRecordType,
} from '../api/systemRecords';
import { getSystems, System } from '../api/systems';
import { getSystemProperties, SystemProperty } from '../api/systemProperties';
import { getBankAccounts, BankAccount } from '../api/bankAccounts';
import { formatCurrency } from '../utils/formatCurrency';
import { formatDate } from '../utils/formatDate';
import { usePermissions } from '../hooks/usePermissions';

const TYPE_OPTIONS = [
  { value: 'deposit', label: 'Deposit' },
  { value: 'withdraw', label: 'Withdraw' },
  { value: 'charge', label: 'Charge' },
];
const TYPE_COLOR: Record<SystemRecordType, string> = { deposit: 'green', withdraw: 'red', charge: 'orange' };

export default function SystemRecords() {
  const queryClient = useQueryClient();
  const { can } = usePermissions();
  const canCreate = can('system_records.create');
  const canUpdate = can('system_records.update');
  const canDelete = can('system_records.delete');
  const canReconcile = can('system_records.reconcile');

  const [page, setPage] = useState(1);
  const [search, setSearch] = useState('');
  const [debouncedSearch] = useDebouncedValue(search, 300);
  const [filterSystem, setFilterSystem] = useState<string | null>(null);
  const [filterProperty, setFilterProperty] = useState<string | null>(null);
  const [filterBank, setFilterBank] = useState<string | null>(null);
  const [filterType, setFilterType] = useState<string | null>(null);
  const [dateFrom, setDateFrom] = useState<string | null>(null);
  const [dateTo, setDateTo] = useState<string | null>(null);
  const [formOpen, setFormOpen] = useState(false);
  const [editing, setEditing] = useState<SystemRecord | null>(null);

  // Reference data for the form dropdowns + filters
  const { data: systemsData } = useQuery({
    queryKey: ['systems-all'],
    queryFn: () => getSystems({ per_page: 200 }),
  });
  const { data: propsData } = useQuery({
    queryKey: ['system-properties-all'],
    queryFn: () => getSystemProperties({ per_page: 200 }),
  });
  const { data: banksData } = useQuery({
    queryKey: ['bank-accounts-all'],
    queryFn: () => getBankAccounts({ per_page: 200 }),
  });
  const systems: System[] = systemsData?.data?.data || [];
  const properties: SystemProperty[] = propsData?.data?.data || [];
  const banks: BankAccount[] = banksData?.data?.data || [];
  const systemOptions = systems.filter((s) => s.is_active).map((s) => ({ value: s.id, label: s.name }));
  const propertyOptions = properties.filter((p) => p.is_active).map((p) => ({ value: p.id, label: p.name }));
  const bankOptions = banks.filter((b) => b.is_active).map((b) => ({
    value: b.id,
    label: `${b.bank_name} · ${b.account_number}`,
  }));

  const { data } = useQuery({
    queryKey: ['system-records', page, debouncedSearch, filterSystem, filterProperty, filterBank, filterType, dateFrom, dateTo],
    queryFn: () => getSystemRecords({
      page,
      search: debouncedSearch || undefined,
      system_id: filterSystem || undefined,
      system_property_id: filterProperty || undefined,
      bank_account_id: filterBank || undefined,
      type: (filterType as SystemRecordType) || undefined,
      date_from: dateFrom || undefined,
      date_to: dateTo || undefined,
    }),
  });
  const items: SystemRecord[] = data?.data?.data || [];
  const meta = data?.data?.meta;

  const form = useForm({
    initialValues: {
      system_id: '',
      system_property_id: '',
      bank_account_id: '',
      type: 'deposit' as SystemRecordType,
      transaction_reference: '',
      record_date: new Date(),
      amount: 0,
      notes: '',
      receipt: null as File | null,
    },
    validate: {
      system_id: (v) => (v ? null : 'Required'),
      system_property_id: (v) => (v ? null : 'Required'),
      type: (v) => (v ? null : 'Required'),
      transaction_reference: (v, values) =>
        (values.type === 'deposit' && !v.trim()) ? 'Required for deposits — prevents the same slip being recorded twice' : null,
      amount: (v) => (v >= 0 ? null : 'Must be 0 or greater'),
      // The browser-level required attribute handles the create case but
      // we double-check at form-validate time too in case JS-only paths
      // (e.g. drag-drop replacement) bypass the native control.
      receipt: (v, values) => {
        // When editing, receipt is optional (one's already attached). A
        // "charge" has no physical slip to attach, unlike deposit/withdraw.
        if (editing || values.type === 'charge') return null;
        return v ? null : 'Receipt is required';
      },
    },
  });

  const closeForm = () => { setFormOpen(false); setEditing(null); form.reset(); };
  const openCreate = () => {
    setEditing(null);
    form.setValues({ system_id: '', system_property_id: '', bank_account_id: '', type: 'deposit', transaction_reference: '', record_date: new Date(), amount: 0, notes: '', receipt: null });
    setFormOpen(true);
  };
  const openEdit = (r: SystemRecord) => {
    setEditing(r);
    form.setValues({
      system_id: r.system_id,
      system_property_id: r.system_property_id,
      bank_account_id: r.bank_account_id || '',
      type: r.type,
      transaction_reference: r.transaction_reference || '',
      record_date: new Date(r.record_date),
      amount: parseFloat(r.amount) || 0,
      notes: r.notes || '',
      receipt: null,
    });
    setFormOpen(true);
  };

  const buildPayload = (v: typeof form.values) => ({
    system_id: v.system_id,
    system_property_id: v.system_property_id,
    bank_account_id: v.bank_account_id || null,
    type: v.type,
    transaction_reference: v.transaction_reference.trim() || undefined,
    record_date: dayjs(v.record_date).format('YYYY-MM-DD'),
    amount: v.amount,
    notes: v.notes || undefined,
    receipt: v.receipt,
  });

  const createMutation = useMutation({
    mutationFn: (v: typeof form.values) => createSystemRecord(buildPayload(v)),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['system-records'] });
      notifications.show({ title: 'Created', message: 'Record added', color: 'green' });
      closeForm();
    },
    onError: (err: any) => notifications.show({ title: 'Error', message: err.response?.data?.message || 'Failed to create', color: 'red' }),
  });

  const updateMutation = useMutation({
    mutationFn: (v: typeof form.values) => updateSystemRecord(editing!.id, buildPayload(v)),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['system-records'] });
      notifications.show({ title: 'Updated', message: 'Record updated', color: 'green' });
      closeForm();
    },
    onError: (err: any) => notifications.show({ title: 'Error', message: err.response?.data?.message || 'Failed to update', color: 'red' }),
  });

  const deleteMutation = useMutation({
    mutationFn: deleteSystemRecord,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['system-records'] });
      notifications.show({ title: 'Deleted', message: 'Record deleted', color: 'green' });
    },
    onError: (err: any) => notifications.show({ title: 'Error', message: err.response?.data?.message || 'Failed to delete', color: 'red' }),
  });

  const handleDelete = (r: SystemRecord) => modals.openConfirmModal({
    title: 'Delete Record',
    children: `Delete record of ${formatCurrency(r.amount)} on ${formatDate(r.record_date)}?`,
    labels: { confirm: 'Delete', cancel: 'Cancel' },
    confirmProps: { color: 'red' },
    onConfirm: () => deleteMutation.mutate(r.id),
  });

  const smsToggleMutation = useMutation({
    mutationFn: toggleSmsConfirmation,
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['system-records'] }),
    onError: (err: any) => notifications.show({ title: 'Error', message: err.response?.data?.message || 'Failed to update', color: 'red' }),
  });
  const statementToggleMutation = useMutation({
    mutationFn: toggleStatementConfirmation,
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['system-records'] }),
    onError: (err: any) => notifications.show({ title: 'Error', message: err.response?.data?.message || 'Failed to update', color: 'red' }),
  });

  const [noteFor, setNoteFor] = useState<SystemRecord | null>(null);
  const [noteText, setNoteText] = useState('');
  const noteMutation = useMutation({
    mutationFn: () => updateReconciliationNote(noteFor!.id, noteText.trim()),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['system-records'] });
      setNoteFor(null);
    },
    onError: (err: any) => notifications.show({ title: 'Error', message: err.response?.data?.message || 'Failed to save note', color: 'red' }),
  });
  const openNote = (r: SystemRecord) => { setNoteFor(r); setNoteText(r.reconciliation_note || ''); };

  return (
    <>
      <Group justify="space-between" mb="md" wrap="wrap">
        <Title order={2}>System Records</Title>
        <Group wrap="wrap">
          <TextInput placeholder="Search notes or transaction ref..." leftSection={<IconSearch size={16} />}
            value={search} onChange={(e) => { setSearch(e.currentTarget.value); setPage(1); }} maw={220} />
          {canCreate && (
            <Button leftSection={<IconPlus size={16} />} onClick={openCreate}>Add Record</Button>
          )}
        </Group>
      </Group>

      <Group mb="md" wrap="wrap">
        <Select placeholder="All systems" data={systemOptions} clearable searchable
          value={filterSystem} onChange={(v) => { setFilterSystem(v); setPage(1); }} maw={220} />
        <Select placeholder="All properties" data={propertyOptions} clearable searchable
          value={filterProperty} onChange={(v) => { setFilterProperty(v); setPage(1); }} maw={220} />
        <Select placeholder="All bank accounts" data={bankOptions} clearable searchable
          value={filterBank} onChange={(v) => { setFilterBank(v); setPage(1); }} maw={240} />
        <Select placeholder="All types" data={TYPE_OPTIONS} clearable
          value={filterType} onChange={(v) => { setFilterType(v); setPage(1); }} maw={160} />
        <DateInput placeholder="From" clearable
          value={dateFrom ? new Date(dateFrom) : null}
          onChange={(v) => { setDateFrom(v ? dayjs(v).format('YYYY-MM-DD') : null); setPage(1); }} maw={160} />
        <DateInput placeholder="To" clearable
          value={dateTo ? new Date(dateTo) : null}
          onChange={(v) => { setDateTo(v ? dayjs(v).format('YYYY-MM-DD') : null); setPage(1); }} maw={160} />
      </Group>

      {items.length === 0 ? (
        <Text c="dimmed" ta="center" py="xl">No records found</Text>
      ) : (
        <Table.ScrollContainer minWidth={800}>
          <Table striped highlightOnHover>
            <Table.Thead>
              <Table.Tr>
                <Table.Th>Date</Table.Th>
                <Table.Th>Type</Table.Th>
                <Table.Th>System</Table.Th>
                <Table.Th>System Property</Table.Th>
                <Table.Th>Bank Account</Table.Th>
                <Table.Th style={{ textAlign: 'right' }}>Amount</Table.Th>
                <Table.Th>Transaction Ref</Table.Th>
                <Table.Th>Receipt</Table.Th>
                <Table.Th>Reconciliation</Table.Th>
                <Table.Th>Notes</Table.Th>
                {(canUpdate || canDelete) && <Table.Th w={100}>Actions</Table.Th>}
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {items.map((r) => (
                <Table.Tr key={r.id}>
                  <Table.Td>{formatDate(r.record_date)}</Table.Td>
                  <Table.Td>
                    <Badge size="sm" variant="light" color={TYPE_COLOR[r.type]} tt="capitalize">{r.type}</Badge>
                  </Table.Td>
                  <Table.Td fw={500}>{r.system?.name || '—'}</Table.Td>
                  <Table.Td>{r.system_property?.name || '—'}</Table.Td>
                  <Table.Td>
                    {r.bank_account ? (
                      <Text size="sm">
                        {r.bank_account.bank_name}
                        <Text span size="xs" c="dimmed"> · {r.bank_account.account_number}</Text>
                      </Text>
                    ) : (
                      <Text size="xs" c="dimmed">—</Text>
                    )}
                  </Table.Td>
                  <Table.Td style={{ textAlign: 'right' }} fw={600}>{formatCurrency(r.amount)}</Table.Td>
                  <Table.Td>
                    {r.transaction_reference ? <Text size="sm">{r.transaction_reference}</Text> : <Text size="xs" c="dimmed">—</Text>}
                  </Table.Td>
                  <Table.Td>
                    {r.receipt_attachment_url ? (
                      <Anchor href={r.receipt_attachment_url} target="_blank" size="sm">
                        <Group gap={4}><IconDownload size={14} /> View</Group>
                      </Anchor>
                    ) : (
                      <Text size="xs" c="dimmed">—</Text>
                    )}
                  </Table.Td>
                  <Table.Td>
                    <Group gap={6} wrap="nowrap">
                      <Tooltip label={r.sms_confirmed_at
                        ? `SMS confirmed by ${r.sms_confirmed_by?.name ?? '—'} on ${formatDate(r.sms_confirmed_at)}`
                        : 'Confirm bank SMS received'}>
                        <ActionIcon
                          variant={r.sms_confirmed_at ? 'filled' : 'outline'}
                          color={r.sms_confirmed_at ? 'green' : 'gray'}
                          size="sm"
                          disabled={!canReconcile}
                          loading={smsToggleMutation.isPending && smsToggleMutation.variables === r.id}
                          onClick={() => smsToggleMutation.mutate(r.id)}
                        >
                          <IconMessage size={14} />
                        </ActionIcon>
                      </Tooltip>
                      <Tooltip label={r.statement_confirmed_at
                        ? `Statement confirmed by ${r.statement_confirmed_by?.name ?? '—'} on ${formatDate(r.statement_confirmed_at)}`
                        : 'Confirm seen on bank statement'}>
                        <ActionIcon
                          variant={r.statement_confirmed_at ? 'filled' : 'outline'}
                          color={r.statement_confirmed_at ? 'green' : 'gray'}
                          size="sm"
                          disabled={!canReconcile}
                          loading={statementToggleMutation.isPending && statementToggleMutation.variables === r.id}
                          onClick={() => statementToggleMutation.mutate(r.id)}
                        >
                          <IconFileSpreadsheet size={14} />
                        </ActionIcon>
                      </Tooltip>
                      {canReconcile && (
                        <Tooltip label={r.reconciliation_note || 'Flag a discrepancy (optional)'}>
                          <ActionIcon
                            variant={r.reconciliation_note ? 'filled' : 'subtle'}
                            color={r.reconciliation_note ? 'red' : 'gray'}
                            size="sm"
                            onClick={() => openNote(r)}
                          >
                            {r.reconciliation_note ? <IconAlertTriangle size={14} /> : <IconNote size={14} />}
                          </ActionIcon>
                        </Tooltip>
                      )}
                      {r.reconciled && <Badge size="xs" color="green" variant="light">Reconciled</Badge>}
                    </Group>
                  </Table.Td>
                  <Table.Td>
                    <Text size="sm" c="dimmed" lineClamp={2}>{r.notes || '—'}</Text>
                  </Table.Td>
                  {(canUpdate || canDelete) && (
                    <Table.Td>
                      <Group gap="xs">
                        {canUpdate && <ActionIcon variant="light" onClick={() => openEdit(r)}><IconEdit size={16} /></ActionIcon>}
                        {canDelete && <ActionIcon variant="light" color="red" onClick={() => handleDelete(r)}><IconTrash size={16} /></ActionIcon>}
                      </Group>
                    </Table.Td>
                  )}
                </Table.Tr>
              ))}
            </Table.Tbody>
          </Table>
        </Table.ScrollContainer>
      )}

      {meta && meta.last_page > 1 && (
        <Group justify="center" mt="md">
          <Pagination total={meta.last_page} value={page} onChange={setPage} />
        </Group>
      )}

      <Modal opened={formOpen} onClose={closeForm} title={editing ? 'Edit Record' : 'New Record'} size="md">
        <form onSubmit={form.onSubmit((v) => (editing ? updateMutation : createMutation).mutate(v))}>
          <Stack>
            <Select label="System" required data={systemOptions} searchable
              placeholder="Choose a system" {...form.getInputProps('system_id')} />
            <Select label="System Property" required data={propertyOptions} searchable
              placeholder="Choose a property" {...form.getInputProps('system_property_id')} />
            <Select label="Bank Account" data={bankOptions} searchable clearable
              placeholder="Choose a bank account (optional)"
              {...form.getInputProps('bank_account_id')} />
            <Select label="Type" required data={TYPE_OPTIONS} {...form.getInputProps('type')} />
            {form.values.type === 'deposit' && (
              <TextInput label="Transaction ID / Slip Reference" required
                placeholder="e.g. M-Pesa code or bank slip number"
                description="Prevents the same deposit slip from being recorded twice"
                {...form.getInputProps('transaction_reference')} />
            )}
            <DateInput label="Date" required {...form.getInputProps('record_date')} />
            <NumberInput label="Amount" required min={0} decimalScale={2} {...form.getInputProps('amount')} />
            <FileInput
              label={editing ? 'Replace receipt (optional)' : form.values.type === 'charge' ? 'Receipt (optional)' : 'Receipt'}
              required={!editing && form.values.type !== 'charge'}
              placeholder={editing ? 'Upload a new receipt to replace the current one' : 'Upload receipt (PDF, image)'}
              leftSection={<IconUpload size={16} />}
              accept="image/*,.pdf"
              {...form.getInputProps('receipt')}
            />
            {editing?.receipt_attachment_url && !form.values.receipt && (
              <Text size="sm">
                Current receipt:{' '}
                <Anchor href={editing.receipt_attachment_url} target="_blank" size="sm">View attachment</Anchor>
              </Text>
            )}
            <Textarea label="Notes" placeholder="Optional notes" {...form.getInputProps('notes')} />
            <Group justify="flex-end">
              <Button variant="default" onClick={closeForm}>Cancel</Button>
              <Button type="submit" loading={createMutation.isPending || updateMutation.isPending}>
                {editing ? 'Update' : 'Create'}
              </Button>
            </Group>
          </Stack>
        </form>
      </Modal>

      <Modal opened={!!noteFor} onClose={() => setNoteFor(null)} title="Reconciliation Note" size="sm">
        <Stack>
          <Text size="sm" c="dimmed">
            Use this to flag a discrepancy — e.g. "not seen on statement yet" — visible to whoever else is reconciling this record.
          </Text>
          <Textarea
            placeholder="Describe the issue (leave blank to clear)"
            minRows={3}
            value={noteText}
            onChange={(e) => setNoteText(e.currentTarget.value)}
          />
          <Group justify="flex-end">
            <Button variant="default" onClick={() => setNoteFor(null)}>Cancel</Button>
            <Button loading={noteMutation.isPending} onClick={() => noteMutation.mutate()}>Save</Button>
          </Group>
        </Stack>
      </Modal>
    </>
  );
}
