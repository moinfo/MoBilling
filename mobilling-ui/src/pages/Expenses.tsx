import { useState } from 'react';
import { Title, Table, Text, Group, Pagination, Badge, ActionIcon, Modal, Button, TextInput, Anchor, Tooltip, FileButton } from '@mantine/core';
import { DateInput } from '@mantine/dates';
import { useDebouncedValue } from '@mantine/hooks';
import dayjs from 'dayjs';
import { modals } from '@mantine/modals';
import { notifications } from '@mantine/notifications';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { IconPlus, IconEdit, IconTrash, IconSearch, IconDownload, IconFileDownload, IconUpload, IconCash, IconCheck, IconAlertTriangle } from '@tabler/icons-react';
import { getExpenses, createExpense, updateExpense, deleteExpense, downloadExpenseVoucher, uploadExpenseVoucher, Expense } from '../api/expenses';
import { getExpenseCategories, ExpenseCategory } from '../api/expenseCategories';
import { getPettyCash } from '../api/pettyCash';
import { formatCurrency } from '../utils/formatCurrency';
import { formatDate } from '../utils/formatDate';
import ExpenseForm from '../components/Expenses/ExpenseForm';
import { usePermissions } from '../hooks/usePermissions';

const methodLabels: Record<string, string> = {
  cash: 'Cash',
  bank: 'Bank Transfer',
  mpesa: 'M-Pesa',
  card: 'Card',
  other: 'Other',
};

export default function Expenses() {
  const queryClient = useQueryClient();
  const { can } = usePermissions();
  const canCreate = can('expenses.create');
  const canUpdate = can('expenses.update');
  const canDelete = can('expenses.delete');
  const canChangeDateRange = can('expenses.date_range');
  const today = dayjs().format('YYYY-MM-DD');
  const [page, setPage] = useState(1);
  const [search, setSearch] = useState('');
  const [debouncedSearch] = useDebouncedValue(search, 300);
  const [dateFrom, setDateFrom] = useState<string>(today);
  const [dateTo, setDateTo] = useState<string>(today);
  const [formOpen, setFormOpen] = useState(false);
  const [editing, setEditing] = useState<Expense | null>(null);

  const { data } = useQuery({
    queryKey: ['expenses', page, debouncedSearch, dateFrom, dateTo],
    queryFn: () => getExpenses({
      page,
      search: debouncedSearch || undefined,
      date_from: dateFrom || undefined,
      date_to: dateTo || undefined,
    }),
  });

  const { data: catData } = useQuery({
    queryKey: ['expense-categories'],
    queryFn: getExpenseCategories,
  });

  // Fetch the tenant's petty cash account once — its id is what the form
  // sends when "Paid from petty cash" is toggled on. Skipped if the user
  // doesn't have petty_cash.read.
  const canReadPettyCash = can('petty_cash.read');
  const { data: pettyCashData } = useQuery({
    queryKey: ['petty-cash'],
    queryFn: async () => (await getPettyCash()).data,
    enabled: canReadPettyCash,
  });
  const pettyCashAccountId = pettyCashData?.account?.id ?? null;

  const expenses: Expense[] = data?.data?.data || [];
  const meta = data?.data?.meta;
  const categories: ExpenseCategory[] = catData?.data?.data || [];

  const [uploadingFor, setUploadingFor] = useState<string | null>(null);

  const handleDownloadVoucher = async (e: Expense) => {
    try {
      const res = await downloadExpenseVoucher(e.id);
      const url = window.URL.createObjectURL(new Blob([res.data], { type: 'application/pdf' }));
      const link = window.document.createElement('a');
      link.href = url;
      link.download = `voucher-${e.id.slice(0, 8)}.pdf`;
      link.click();
      window.URL.revokeObjectURL(url);
    } catch (err: any) {
      let msg = 'Failed to download voucher';
      try {
        const d = err?.response?.data;
        if (d instanceof Blob) msg = JSON.parse(await d.text())?.message || msg;
        else if (d?.message) msg = d.message;
      } catch { /* keep default */ }
      notifications.show({ title: 'Error', message: msg, color: 'red' });
    }
  };

  const handleUploadVoucher = async (e: Expense, file: File | null) => {
    if (!file) return;
    setUploadingFor(e.id);
    try {
      await uploadExpenseVoucher(e.id, file);
      notifications.show({ title: 'Uploaded', message: 'Signed voucher attached — verified balance updated.', color: 'green' });
      queryClient.invalidateQueries({ queryKey: ['expenses'] });
      // Attaching a voucher moves this expense from pending → signed in the
      // strict imprest model, so the petty-cash balance card needs to refresh.
      queryClient.invalidateQueries({ queryKey: ['petty-cash'] });
    } catch (err: any) {
      notifications.show({
        title: 'Error',
        message: err.response?.data?.message || 'Failed to upload voucher',
        color: 'red',
      });
    } finally {
      setUploadingFor(null);
    }
  };

  const createMutation = useMutation({
    mutationFn: (values: any) => createExpense(values),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['expenses'] });
      queryClient.invalidateQueries({ queryKey: ['petty-cash'] });
      closeForm();
      notifications.show({ title: 'Success', message: 'Expense created', color: 'green' });
    },
    onError: (err: any) => notifications.show({
      title: 'Error',
      message: err.response?.data?.message || 'Failed to create expense',
      color: 'red',
    }),
  });

  const updateMutation = useMutation({
    mutationFn: (values: any) => updateExpense(editing!.id, values),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['expenses'] });
      queryClient.invalidateQueries({ queryKey: ['petty-cash'] });
      closeForm();
      notifications.show({ title: 'Success', message: 'Expense updated', color: 'green' });
    },
    onError: (err: any) => notifications.show({
      title: 'Error',
      message: err.response?.data?.message || 'Failed to update expense',
      color: 'red',
    }),
  });

  const deleteMutation = useMutation({
    mutationFn: (id: string) => deleteExpense(id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['expenses'] });
      queryClient.invalidateQueries({ queryKey: ['petty-cash'] });
      notifications.show({ title: 'Success', message: 'Expense deleted', color: 'green' });
    },
    onError: (err: any) => notifications.show({
      title: 'Error',
      message: err.response?.data?.message || 'Failed to delete expense',
      color: 'red',
    }),
  });

  const closeForm = () => {
    setFormOpen(false);
    setEditing(null);
  };

  const openCreate = () => {
    setEditing(null);
    setFormOpen(true);
  };

  const openEdit = (expense: Expense) => {
    setEditing(expense);
    setFormOpen(true);
  };

  const handleDelete = (expense: Expense) => {
    modals.openConfirmModal({
      title: 'Delete Expense',
      children: `Delete "${expense.description}" (${formatCurrency(expense.amount)})?`,
      labels: { confirm: 'Delete', cancel: 'Cancel' },
      confirmProps: { color: 'red' },
      onConfirm: () => deleteMutation.mutate(expense.id),
    });
  };

  const handleSubmit = (values: any) => {
    if (editing) {
      updateMutation.mutate(values);
    } else {
      createMutation.mutate(values);
    }
  };

  return (
    <>
      <Group justify="space-between" mb="md" wrap="wrap">
        <Title order={2}>Expenses</Title>
        <Group wrap="wrap">
          <TextInput
            placeholder="Search expenses..."
            leftSection={<IconSearch size={16} />}
            value={search}
            onChange={(e) => { setSearch(e.currentTarget.value); setPage(1); }}
            maw={250}
          />
          {canCreate && (
            <Button leftSection={<IconPlus size={16} />} onClick={openCreate}>
              Add Expense
            </Button>
          )}
        </Group>
      </Group>

      <Group mb="md" wrap="wrap">
        <DateInput
          label="From"
          value={dateFrom ? new Date(dateFrom) : null}
          onChange={(v) => { setDateFrom(v ? dayjs(v).format('YYYY-MM-DD') : today); setPage(1); }}
          disabled={!canChangeDateRange}
          maw={160}
          size="sm"
        />
        <DateInput
          label="To"
          value={dateTo ? new Date(dateTo) : null}
          onChange={(v) => { setDateTo(v ? dayjs(v).format('YYYY-MM-DD') : today); setPage(1); }}
          disabled={!canChangeDateRange}
          maw={160}
          size="sm"
        />
      </Group>

      {expenses.length === 0 ? (
        <Text c="dimmed" ta="center" py="xl">No expenses found</Text>
      ) : (
        <Table.ScrollContainer minWidth={900}>
          <Table striped highlightOnHover>
            <Table.Thead>
            <Table.Tr>
              <Table.Th>Description</Table.Th>
              <Table.Th>Category</Table.Th>
              <Table.Th>Sub Category</Table.Th>
              <Table.Th>Amount</Table.Th>
              <Table.Th>Date</Table.Th>
              <Table.Th>Method</Table.Th>
              <Table.Th>Control #</Table.Th>
              <Table.Th>Attachment</Table.Th>
              {(canUpdate || canDelete) && <Table.Th w={100}>Actions</Table.Th>}
            </Table.Tr>
          </Table.Thead>
          <Table.Tbody>
            {expenses.map((e) => (
              <Table.Tr key={e.id}>
                <Table.Td fw={500}>{e.description}</Table.Td>
                <Table.Td>{e.sub_category?.category?.name || '—'}</Table.Td>
                <Table.Td>{e.sub_category?.name || '—'}</Table.Td>
                <Table.Td>{formatCurrency(e.amount)}</Table.Td>
                <Table.Td>{formatDate(e.expense_date)}</Table.Td>
                <Table.Td>
                  <Group gap={4} wrap="nowrap">
                    <Badge variant="light" size="sm">{methodLabels[e.payment_method] || e.payment_method}</Badge>
                    {e.petty_cash_account_id && (
                      <Tooltip label="Paid from petty cash">
                        <Badge color="violet" variant="light" size="sm" leftSection={<IconCash size={10} />}>PC</Badge>
                      </Tooltip>
                    )}
                    {/* Voucher state — persistent visual confirmation. The
                        "Signed" badge is a link that opens the uploaded PDF;
                        "Unsigned" reminds the user paperwork is missing and
                        that the expense isn't reducing verified balance yet. */}
                    {e.petty_cash_account_id && (
                      e.voucher_attachment_url ? (
                        <Tooltip label="Voucher signed and on file — click to view">
                          <Badge
                            component="a"
                            href={e.voucher_attachment_url}
                            target="_blank"
                            color="green"
                            variant="light"
                            size="sm"
                            leftSection={<IconCheck size={10} />}
                            style={{ cursor: 'pointer' }}
                          >
                            Signed
                          </Badge>
                        </Tooltip>
                      ) : (
                        <Tooltip label="Print the voucher, get it signed by both parties, then upload it via the purple icon">
                          <Badge color="yellow" variant="light" size="sm" leftSection={<IconAlertTriangle size={10} />}>
                            Unsigned
                          </Badge>
                        </Tooltip>
                      )
                    )}
                  </Group>
                </Table.Td>
                <Table.Td>{e.control_number || '—'}</Table.Td>
                <Table.Td>
                  {e.attachment_url ? (
                    <Anchor href={e.attachment_url} target="_blank" size="sm">
                      <IconDownload size={16} />
                    </Anchor>
                  ) : '—'}
                </Table.Td>
                {(canUpdate || canDelete) && (
                  <Table.Td>
                    <Group gap="xs" wrap="nowrap">
                      {canUpdate && (
                        <ActionIcon variant="light" onClick={() => openEdit(e)}>
                          <IconEdit size={16} />
                        </ActionIcon>
                      )}
                      {/* Voucher actions: only meaningful for petty cash expenses */}
                      {e.petty_cash_account_id && (
                        <>
                          <Tooltip label="Download voucher PDF">
                            <ActionIcon variant="light" color="blue" onClick={() => handleDownloadVoucher(e)}>
                              <IconFileDownload size={16} />
                            </ActionIcon>
                          </Tooltip>
                          {canUpdate && (
                            <FileButton onChange={(f) => handleUploadVoucher(e, f)} accept="application/pdf,image/*">
                              {(props) => (
                                <Tooltip label={e.voucher_attachment_url ? 'Replace signed voucher' : 'Upload signed voucher'}>
                                  <ActionIcon variant="light" color="violet" loading={uploadingFor === e.id} {...props}>
                                    <IconUpload size={16} />
                                  </ActionIcon>
                                </Tooltip>
                              )}
                            </FileButton>
                          )}
                        </>
                      )}
                      {canDelete && (
                        <ActionIcon variant="light" color="red" onClick={() => handleDelete(e)}>
                          <IconTrash size={16} />
                        </ActionIcon>
                      )}
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

      <Modal opened={formOpen} onClose={closeForm} title={editing ? 'Edit Expense' : 'New Expense'} size="lg">
        <ExpenseForm
          expense={editing}
          categories={categories}
          onSubmit={handleSubmit}
          loading={createMutation.isPending || updateMutation.isPending}
          pettyCashAccountId={pettyCashAccountId}
        />
      </Modal>
    </>
  );
}
