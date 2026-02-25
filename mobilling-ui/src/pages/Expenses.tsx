import { useState } from 'react';
import { Title, Table, Text, Group, Pagination, Badge, ActionIcon, Modal, Button, TextInput, Anchor } from '@mantine/core';
import { useDebouncedValue } from '@mantine/hooks';
import { modals } from '@mantine/modals';
import { notifications } from '@mantine/notifications';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { IconPlus, IconEdit, IconTrash, IconSearch, IconDownload } from '@tabler/icons-react';
import { getExpenses, createExpense, updateExpense, deleteExpense, Expense } from '../api/expenses';
import { getExpenseCategories, ExpenseCategory } from '../api/expenseCategories';
import { formatCurrency } from '../utils/formatCurrency';
import { formatDate } from '../utils/formatDate';
import ExpenseForm from '../components/Expenses/ExpenseForm';

const methodLabels: Record<string, string> = {
  cash: 'Cash',
  bank: 'Bank Transfer',
  mpesa: 'M-Pesa',
  card: 'Card',
  other: 'Other',
};

export default function Expenses() {
  const queryClient = useQueryClient();
  const [page, setPage] = useState(1);
  const [search, setSearch] = useState('');
  const [debouncedSearch] = useDebouncedValue(search, 300);
  const [formOpen, setFormOpen] = useState(false);
  const [editing, setEditing] = useState<Expense | null>(null);

  const { data } = useQuery({
    queryKey: ['expenses', page, debouncedSearch],
    queryFn: () => getExpenses({ page, search: debouncedSearch || undefined }),
  });

  const { data: catData } = useQuery({
    queryKey: ['expense-categories'],
    queryFn: getExpenseCategories,
  });

  const expenses: Expense[] = data?.data?.data || [];
  const meta = data?.data?.meta;
  const categories: ExpenseCategory[] = catData?.data?.data || [];

  const createMutation = useMutation({
    mutationFn: (values: any) => createExpense(values),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['expenses'] });
      closeForm();
      notifications.show({ title: 'Success', message: 'Expense created', color: 'green' });
    },
    onError: () => notifications.show({ title: 'Error', message: 'Failed to create expense', color: 'red' }),
  });

  const updateMutation = useMutation({
    mutationFn: (values: any) => updateExpense(editing!.id, values),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['expenses'] });
      closeForm();
      notifications.show({ title: 'Success', message: 'Expense updated', color: 'green' });
    },
    onError: () => notifications.show({ title: 'Error', message: 'Failed to update expense', color: 'red' }),
  });

  const deleteMutation = useMutation({
    mutationFn: (id: string) => deleteExpense(id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['expenses'] });
      notifications.show({ title: 'Success', message: 'Expense deleted', color: 'green' });
    },
    onError: () => notifications.show({ title: 'Error', message: 'Failed to delete expense', color: 'red' }),
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
          <Button leftSection={<IconPlus size={16} />} onClick={openCreate}>
            Add Expense
          </Button>
        </Group>
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
              <Table.Th w={100}>Actions</Table.Th>
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
                  <Badge variant="light" size="sm">{methodLabels[e.payment_method] || e.payment_method}</Badge>
                </Table.Td>
                <Table.Td>{e.control_number || '—'}</Table.Td>
                <Table.Td>
                  {e.attachment_url ? (
                    <Anchor href={e.attachment_url} target="_blank" size="sm">
                      <IconDownload size={16} />
                    </Anchor>
                  ) : '—'}
                </Table.Td>
                <Table.Td>
                  <Group gap="xs">
                    <ActionIcon variant="light" onClick={() => openEdit(e)}>
                      <IconEdit size={16} />
                    </ActionIcon>
                    <ActionIcon variant="light" color="red" onClick={() => handleDelete(e)}>
                      <IconTrash size={16} />
                    </ActionIcon>
                  </Group>
                </Table.Td>
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
        />
      </Modal>
    </>
  );
}
