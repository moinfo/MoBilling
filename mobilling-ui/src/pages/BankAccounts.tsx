import { useState } from 'react';
import { Title, Table, Text, Group, Pagination, Badge, ActionIcon, Modal, Button, TextInput, Stack } from '@mantine/core';
import { useForm } from '@mantine/form';
import { useDebouncedValue } from '@mantine/hooks';
import { modals } from '@mantine/modals';
import { notifications } from '@mantine/notifications';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { IconPlus, IconEdit, IconTrash, IconSearch } from '@tabler/icons-react';
import { getBankAccounts, createBankAccount, updateBankAccount, deleteBankAccount, BankAccount } from '../api/bankAccounts';
import { usePermissions } from '../hooks/usePermissions';

export default function BankAccounts() {
  const queryClient = useQueryClient();
  const { can } = usePermissions();
  const canCreate = can('bank_accounts.create');
  const canUpdate = can('bank_accounts.update');
  const canDelete = can('bank_accounts.delete');

  const [page, setPage] = useState(1);
  const [search, setSearch] = useState('');
  const [debouncedSearch] = useDebouncedValue(search, 300);
  const [formOpen, setFormOpen] = useState(false);
  const [editing, setEditing] = useState<BankAccount | null>(null);

  const { data } = useQuery({
    queryKey: ['bank-accounts', page, debouncedSearch],
    queryFn: () => getBankAccounts({ page, search: debouncedSearch || undefined }),
  });

  const items: BankAccount[] = data?.data?.data || [];
  const meta = data?.data?.meta;

  const form = useForm({
    initialValues: { bank_name: '', account_number: '', is_active: true },
    validate: {
      bank_name: (v) => (v.trim().length > 0 ? null : 'Required'),
      account_number: (v) => (v.trim().length > 0 ? null : 'Required'),
    },
  });

  const closeForm = () => { setFormOpen(false); setEditing(null); form.reset(); };
  const openCreate = () => { setEditing(null); form.setValues({ bank_name: '', account_number: '', is_active: true }); setFormOpen(true); };
  const openEdit = (b: BankAccount) => { setEditing(b); form.setValues({ bank_name: b.bank_name, account_number: b.account_number, is_active: b.is_active }); setFormOpen(true); };

  const createMutation = useMutation({
    mutationFn: createBankAccount,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['bank-accounts'] });
      notifications.show({ title: 'Created', message: 'Bank account added', color: 'green' });
      closeForm();
    },
    onError: (err: any) => notifications.show({ title: 'Error', message: err.response?.data?.message || 'Failed to create', color: 'red' }),
  });

  const updateMutation = useMutation({
    mutationFn: (values: any) => updateBankAccount(editing!.id, values),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['bank-accounts'] });
      notifications.show({ title: 'Updated', message: 'Bank account updated', color: 'green' });
      closeForm();
    },
    onError: (err: any) => notifications.show({ title: 'Error', message: err.response?.data?.message || 'Failed to update', color: 'red' }),
  });

  const deleteMutation = useMutation({
    mutationFn: deleteBankAccount,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['bank-accounts'] });
      notifications.show({ title: 'Deleted', message: 'Bank account deleted', color: 'green' });
    },
    onError: (err: any) => notifications.show({ title: 'Error', message: err.response?.data?.message || 'Failed to delete', color: 'red' }),
  });

  const handleDelete = (b: BankAccount) => modals.openConfirmModal({
    title: 'Delete Bank Account',
    children: `Delete "${b.bank_name} — ${b.account_number}"?`,
    labels: { confirm: 'Delete', cancel: 'Cancel' },
    confirmProps: { color: 'red' },
    onConfirm: () => deleteMutation.mutate(b.id),
  });

  return (
    <>
      <Group justify="space-between" mb="md">
        <Title order={2}>Bank Accounts</Title>
        <Group>
          <TextInput placeholder="Search..." leftSection={<IconSearch size={16} />}
            value={search} onChange={(e) => { setSearch(e.currentTarget.value); setPage(1); }} maw={250} />
          {canCreate && (
            <Button leftSection={<IconPlus size={16} />} onClick={openCreate}>Add Bank Account</Button>
          )}
        </Group>
      </Group>

      {items.length === 0 ? (
        <Text c="dimmed" ta="center" py="xl">No bank accounts yet</Text>
      ) : (
        <Table striped highlightOnHover>
          <Table.Thead>
            <Table.Tr>
              <Table.Th>Bank Name</Table.Th>
              <Table.Th>Account Number</Table.Th>
              <Table.Th>Status</Table.Th>
              {(canUpdate || canDelete) && <Table.Th w={100}>Actions</Table.Th>}
            </Table.Tr>
          </Table.Thead>
          <Table.Tbody>
            {items.map((b) => (
              <Table.Tr key={b.id}>
                <Table.Td fw={500}>{b.bank_name}</Table.Td>
                <Table.Td>{b.account_number}</Table.Td>
                <Table.Td>
                  <Badge color={b.is_active ? 'green' : 'gray'} variant="light">
                    {b.is_active ? 'Active' : 'Inactive'}
                  </Badge>
                </Table.Td>
                {(canUpdate || canDelete) && (
                  <Table.Td>
                    <Group gap="xs">
                      {canUpdate && <ActionIcon variant="light" onClick={() => openEdit(b)}><IconEdit size={16} /></ActionIcon>}
                      {canDelete && <ActionIcon variant="light" color="red" onClick={() => handleDelete(b)}><IconTrash size={16} /></ActionIcon>}
                    </Group>
                  </Table.Td>
                )}
              </Table.Tr>
            ))}
          </Table.Tbody>
        </Table>
      )}

      {meta && meta.last_page > 1 && (
        <Group justify="center" mt="md">
          <Pagination total={meta.last_page} value={page} onChange={setPage} />
        </Group>
      )}

      <Modal opened={formOpen} onClose={closeForm} title={editing ? 'Edit Bank Account' : 'New Bank Account'} size="md">
        <form onSubmit={form.onSubmit((v) => (editing ? updateMutation : createMutation).mutate(v))}>
          <Stack>
            <TextInput label="Bank Name" required placeholder="e.g. CRDB" {...form.getInputProps('bank_name')} />
            <TextInput label="Account Number" required placeholder="e.g. 0150851484300" {...form.getInputProps('account_number')} />
            <Group justify="flex-end">
              <Button variant="default" onClick={closeForm}>Cancel</Button>
              <Button type="submit" loading={createMutation.isPending || updateMutation.isPending}>
                {editing ? 'Update' : 'Create'}
              </Button>
            </Group>
          </Stack>
        </form>
      </Modal>
    </>
  );
}
