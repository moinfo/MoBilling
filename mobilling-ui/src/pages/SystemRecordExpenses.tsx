import { useState } from 'react';
import {
  Title, Table, Text, Group, Pagination, ActionIcon, Modal, Button, TextInput,
  NumberInput, Select, Stack, Textarea, FileInput, Anchor, Badge,
} from '@mantine/core';
import { DateInput } from '@mantine/dates';
import { useForm } from '@mantine/form';
import { useDebouncedValue } from '@mantine/hooks';
import { modals } from '@mantine/modals';
import { notifications } from '@mantine/notifications';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { IconPlus, IconEdit, IconTrash, IconSearch, IconUpload, IconDownload } from '@tabler/icons-react';
import dayjs from 'dayjs';
import {
  getSystemRecordExpenses, createSystemRecordExpense, updateSystemRecordExpense, deleteSystemRecordExpense,
  SystemRecordExpense,
} from '../api/systemRecordExpenses';
import { getSystemRecords, SystemRecord } from '../api/systemRecords';
import { formatCurrency } from '../utils/formatCurrency';
import { formatDate } from '../utils/formatDate';
import { usePermissions } from '../hooks/usePermissions';

export default function SystemRecordExpenses() {
  const queryClient = useQueryClient();
  const { can } = usePermissions();
  const canCreate = can('system_record_expenses.create');
  const canUpdate = can('system_record_expenses.update');
  const canDelete = can('system_record_expenses.delete');

  const [page, setPage] = useState(1);
  const [search, setSearch] = useState('');
  const [debouncedSearch] = useDebouncedValue(search, 300);
  const [formOpen, setFormOpen] = useState(false);
  const [editing, setEditing] = useState<SystemRecordExpense | null>(null);

  // Only withdraws can be linked — the same list the balance/remaining
  // figures on System Records already come from (SystemRecordResource).
  const { data: withdrawsData } = useQuery({
    queryKey: ['system-records-withdraws-all'],
    queryFn: () => getSystemRecords({ type: 'withdraw', per_page: 200 }),
  });
  const withdraws: SystemRecord[] = withdrawsData?.data?.data || [];
  const withdrawOptions = withdraws.map((w) => {
    const remaining = w.remaining_amount ?? parseFloat(w.amount);
    return {
      value: w.id,
      label: `${w.system?.name ?? '—'} / ${w.system_property?.name ?? '—'} — ${formatCurrency(w.amount)} on ${formatDate(w.record_date)} (Remaining: ${formatCurrency(remaining)})`,
    };
  });

  const { data } = useQuery({
    queryKey: ['system-record-expenses', page, debouncedSearch],
    queryFn: () => getSystemRecordExpenses({ page, search: debouncedSearch || undefined }),
  });
  const items: SystemRecordExpense[] = data?.data?.data || [];
  const meta = data?.data?.meta;

  const form = useForm({
    initialValues: {
      system_record_id: '',
      amount: 0,
      expense_date: new Date(),
      description: '',
      attachment: null as File | null,
    },
    validate: {
      system_record_id: (v) => (v ? null : 'Required'),
      amount: (v) => (v > 0 ? null : 'Must be greater than 0'),
      description: (v) => (v.trim().length > 0 ? null : 'Required'),
    },
  });

  const closeForm = () => { setFormOpen(false); setEditing(null); form.reset(); };
  const openCreate = () => {
    setEditing(null);
    form.setValues({ system_record_id: '', amount: 0, expense_date: new Date(), description: '', attachment: null });
    setFormOpen(true);
  };
  const openEdit = (e: SystemRecordExpense) => {
    setEditing(e);
    form.setValues({
      system_record_id: e.system_record_id,
      amount: parseFloat(e.amount) || 0,
      expense_date: new Date(e.expense_date),
      description: e.description,
      attachment: null,
    });
    setFormOpen(true);
  };

  const buildPayload = (v: typeof form.values) => ({
    system_record_id: v.system_record_id,
    amount: v.amount,
    expense_date: dayjs(v.expense_date).format('YYYY-MM-DD'),
    description: v.description,
    attachment: v.attachment,
  });

  const createMutation = useMutation({
    mutationFn: (v: typeof form.values) => createSystemRecordExpense(buildPayload(v)),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['system-record-expenses'] });
      queryClient.invalidateQueries({ queryKey: ['system-records-withdraws-all'] });
      queryClient.invalidateQueries({ queryKey: ['system-records'] });
      notifications.show({ title: 'Recorded', message: 'Usage recorded', color: 'green' });
      closeForm();
    },
    onError: (err: any) => notifications.show({ title: 'Error', message: err.response?.data?.message || 'Failed to create', color: 'red' }),
  });

  const updateMutation = useMutation({
    mutationFn: (v: typeof form.values) => updateSystemRecordExpense(editing!.id, buildPayload(v)),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['system-record-expenses'] });
      queryClient.invalidateQueries({ queryKey: ['system-records-withdraws-all'] });
      queryClient.invalidateQueries({ queryKey: ['system-records'] });
      notifications.show({ title: 'Updated', message: 'Usage updated', color: 'green' });
      closeForm();
    },
    onError: (err: any) => notifications.show({ title: 'Error', message: err.response?.data?.message || 'Failed to update', color: 'red' }),
  });

  const deleteMutation = useMutation({
    mutationFn: deleteSystemRecordExpense,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['system-record-expenses'] });
      queryClient.invalidateQueries({ queryKey: ['system-records-withdraws-all'] });
      queryClient.invalidateQueries({ queryKey: ['system-records'] });
      notifications.show({ title: 'Deleted', message: 'Usage entry deleted', color: 'green' });
    },
    onError: (err: any) => notifications.show({ title: 'Error', message: err.response?.data?.message || 'Failed to delete', color: 'red' }),
  });

  const handleDelete = (e: SystemRecordExpense) => modals.openConfirmModal({
    title: 'Delete Usage Entry',
    children: `Delete "${e.description}" (${formatCurrency(e.amount)})?`,
    labels: { confirm: 'Delete', cancel: 'Cancel' },
    confirmProps: { color: 'red' },
    onConfirm: () => deleteMutation.mutate(e.id),
  });

  return (
    <>
      <Group justify="space-between" mb="md" wrap="wrap">
        <div>
          <Title order={2}>Withdraw Usage</Title>
          <Text c="dimmed" size="sm">What each System Records withdrawal was actually spent on.</Text>
        </div>
        <Group wrap="wrap">
          <TextInput placeholder="Search description..." leftSection={<IconSearch size={16} />}
            value={search} onChange={(e) => { setSearch(e.currentTarget.value); setPage(1); }} maw={240} />
          {canCreate && (
            <Button leftSection={<IconPlus size={16} />} onClick={openCreate}>Record Usage</Button>
          )}
        </Group>
      </Group>

      {items.length === 0 ? (
        <Text c="dimmed" ta="center" py="xl">No usage recorded yet</Text>
      ) : (
        <Table.ScrollContainer minWidth={900}>
          <Table striped highlightOnHover>
            <Table.Thead>
              <Table.Tr>
                <Table.Th>Date</Table.Th>
                <Table.Th>Against Withdraw</Table.Th>
                <Table.Th style={{ textAlign: 'right' }}>Amount</Table.Th>
                <Table.Th>Description</Table.Th>
                <Table.Th>Attachment</Table.Th>
                {(canUpdate || canDelete) && <Table.Th w={100}>Actions</Table.Th>}
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {items.map((e) => (
                <Table.Tr key={e.id}>
                  <Table.Td>{formatDate(e.expense_date)}</Table.Td>
                  <Table.Td>
                    {e.system_record ? (
                      <Group gap={6} wrap="nowrap">
                        <Badge size="sm" variant="light" color="orange">{formatCurrency(e.system_record.amount)}</Badge>
                        <Text size="xs" c="dimmed">
                          {e.system_record.system?.name} / {e.system_record.system_property?.name} — {formatDate(e.system_record.record_date)}
                        </Text>
                      </Group>
                    ) : '—'}
                  </Table.Td>
                  <Table.Td style={{ textAlign: 'right' }} fw={600}>{formatCurrency(e.amount)}</Table.Td>
                  <Table.Td><Text size="sm" lineClamp={2}>{e.description}</Text></Table.Td>
                  <Table.Td>
                    {e.attachment_url ? (
                      <Anchor href={e.attachment_url} target="_blank" size="sm">
                        <Group gap={4}><IconDownload size={14} /> View</Group>
                      </Anchor>
                    ) : (
                      <Text size="xs" c="dimmed">—</Text>
                    )}
                  </Table.Td>
                  {(canUpdate || canDelete) && (
                    <Table.Td>
                      <Group gap="xs">
                        {canUpdate && <ActionIcon variant="light" onClick={() => openEdit(e)}><IconEdit size={16} /></ActionIcon>}
                        {canDelete && <ActionIcon variant="light" color="red" onClick={() => handleDelete(e)}><IconTrash size={16} /></ActionIcon>}
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

      <Modal opened={formOpen} onClose={closeForm} title={editing ? 'Edit Usage' : 'Record Usage'} size="md">
        <form onSubmit={form.onSubmit((v) => (editing ? updateMutation : createMutation).mutate(v))}>
          <Stack>
            <Select label="Against Withdraw" required data={withdrawOptions} searchable
              placeholder="Choose which withdrawal this was spent from"
              {...form.getInputProps('system_record_id')} />
            <NumberInput label="Amount Spent" required min={0.01} decimalScale={2} {...form.getInputProps('amount')} />
            <DateInput label="Date" required {...form.getInputProps('expense_date')} />
            <Textarea label="Description" required placeholder="What was this money used for?"
              {...form.getInputProps('description')} />
            <FileInput
              label={editing ? 'Replace attachment (optional)' : 'Attachment (optional)'}
              placeholder="Upload proof of spend (PDF, image) — optional"
              leftSection={<IconUpload size={16} />}
              accept="image/*,.pdf"
              {...form.getInputProps('attachment')}
            />
            {editing?.attachment_url && !form.values.attachment && (
              <Text size="sm">
                Current attachment: <Anchor href={editing.attachment_url} target="_blank" size="sm">View</Anchor>
              </Text>
            )}
            <Group justify="flex-end">
              <Button variant="default" onClick={closeForm}>Cancel</Button>
              <Button type="submit" loading={createMutation.isPending || updateMutation.isPending}>
                {editing ? 'Update' : 'Save'}
              </Button>
            </Group>
          </Stack>
        </form>
      </Modal>
    </>
  );
}
