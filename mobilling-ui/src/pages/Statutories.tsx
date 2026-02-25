import { useState } from 'react';
import { Title, Group, Button, TextInput, Modal, Pagination, Table, Badge, ActionIcon, Text } from '@mantine/core';
import { useDebouncedValue } from '@mantine/hooks';
import { modals } from '@mantine/modals';
import { notifications } from '@mantine/notifications';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { IconPlus, IconSearch, IconEdit, IconTrash } from '@tabler/icons-react';
import { getStatutories, createStatutory, updateStatutory, deleteStatutory, Statutory, StatutoryFormData } from '../api/statutories';
import StatutoryForm from '../components/Statutory/StatutoryForm';
import { formatCurrency } from '../utils/formatCurrency';

export default function Statutories() {
  const queryClient = useQueryClient();
  const [search, setSearch] = useState('');
  const [debouncedSearch] = useDebouncedValue(search, 300);
  const [page, setPage] = useState(1);
  const [formOpen, setFormOpen] = useState(false);
  const [editing, setEditing] = useState<Statutory | null>(null);

  const { data } = useQuery({
    queryKey: ['statutories', debouncedSearch, page],
    queryFn: () => getStatutories({ search: debouncedSearch || undefined, page }),
  });

  const statutories: Statutory[] = data?.data?.data || [];
  const meta = data?.data?.meta;

  const createMutation = useMutation({
    mutationFn: (values: StatutoryFormData) => createStatutory(values),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['statutories'] });
      queryClient.invalidateQueries({ queryKey: ['bills'] });
      setFormOpen(false);
      notifications.show({ title: 'Success', message: 'Obligation registered', color: 'green' });
    },
    onError: () => notifications.show({ title: 'Error', message: 'Failed to register obligation', color: 'red' }),
  });

  const updateMutation = useMutation({
    mutationFn: (values: StatutoryFormData) => updateStatutory(editing!.id, values),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['statutories'] });
      setFormOpen(false);
      setEditing(null);
      notifications.show({ title: 'Success', message: 'Obligation updated', color: 'green' });
    },
    onError: () => notifications.show({ title: 'Error', message: 'Failed to update obligation', color: 'red' }),
  });

  const deleteMutation = useMutation({
    mutationFn: (id: string) => deleteStatutory(id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['statutories'] });
      notifications.show({ title: 'Success', message: 'Obligation deleted', color: 'green' });
    },
  });

  const handleEdit = (s: Statutory) => {
    setEditing(s);
    setFormOpen(true);
  };

  const handleDelete = (s: Statutory) => {
    modals.openConfirmModal({
      title: 'Delete Obligation',
      children: `Delete "${s.name}"? Linked bills will remain.`,
      labels: { confirm: 'Delete', cancel: 'Cancel' },
      confirmProps: { color: 'red' },
      onConfirm: () => deleteMutation.mutate(s.id),
    });
  };

  const handleSubmit = (values: StatutoryFormData) => {
    if (editing) updateMutation.mutate(values);
    else createMutation.mutate(values);
  };

  const cycleLabel = (cycle: string) =>
    ({ once: 'Once', monthly: 'Monthly', quarterly: 'Quarterly', half_yearly: 'Semi-Annual', yearly: 'Annually' }[cycle] || cycle);

  return (
    <>
      <Group justify="space-between" mb="md" wrap="wrap">
        <Title order={2}>Statutory Obligations</Title>
        <Button leftSection={<IconPlus size={16} />} onClick={() => { setEditing(null); setFormOpen(true); }}>
          Register Obligation
        </Button>
      </Group>

      <TextInput
        placeholder="Search obligations..."
        leftSection={<IconSearch size={16} />}
        value={search}
        onChange={(e) => { setSearch(e.currentTarget.value); setPage(1); }}
        mb="md"
        maw={300}
      />

      {statutories.length === 0 ? (
        <Text c="dimmed" ta="center" py="xl">No statutory obligations found</Text>
      ) : (
        <Table.ScrollContainer minWidth={800}>
          <Table striped highlightOnHover>
            <Table.Thead>
              <Table.Tr>
                <Table.Th>Name</Table.Th>
                <Table.Th>Category</Table.Th>
                <Table.Th>Amount</Table.Th>
                <Table.Th>Cycle</Table.Th>
                <Table.Th>Next Due</Table.Th>
                <Table.Th>Days</Table.Th>
                <Table.Th>Status</Table.Th>
                <Table.Th w={100}>Actions</Table.Th>
              </Table.Tr>
            </Table.Thead>
          <Table.Tbody>
            {statutories.map((s) => {
              const days = s.days_remaining ?? 0;
              const status = s.status || 'upcoming';
              const statusConfig: Record<string, { color: string; label: string }> = {
                paid: { color: 'blue', label: 'PAID' },
                overdue: { color: 'red', label: 'EXPIRED' },
                due_soon: { color: 'orange', label: days === 0 ? 'DUE TODAY' : 'DUE SOON' },
                upcoming: { color: 'green', label: 'UPCOMING' },
              };
              const { color, label } = statusConfig[status] || statusConfig.upcoming;

              return (
                <Table.Tr key={s.id}>
                  <Table.Td fw={500}>{s.name}</Table.Td>
                  <Table.Td>
                    {s.bill_category
                      ? `${s.bill_category.parent_name ? s.bill_category.parent_name + ' > ' : ''}${s.bill_category.name}`
                      : '—'}
                  </Table.Td>
                  <Table.Td>{formatCurrency(s.amount)}</Table.Td>
                  <Table.Td>{cycleLabel(s.cycle)}</Table.Td>
                  <Table.Td>{s.next_due_date}</Table.Td>
                  <Table.Td>
                    <Text c={days < 0 ? 'red' : days <= 7 ? 'orange' : 'green'} fw={600} size="sm">
                      {days}
                    </Text>
                  </Table.Td>
                  <Table.Td>
                    <Badge color={color} size="sm">{label}</Badge>
                  </Table.Td>
                  <Table.Td>
                    <Group gap="xs">
                      <ActionIcon variant="light" onClick={() => handleEdit(s)}>
                        <IconEdit size={16} />
                      </ActionIcon>
                      <ActionIcon variant="light" color="red" onClick={() => handleDelete(s)}>
                        <IconTrash size={16} />
                      </ActionIcon>
                    </Group>
                  </Table.Td>
                </Table.Tr>
              );
            })}
            </Table.Tbody>
          </Table>
        </Table.ScrollContainer>
      )}

      {meta && meta.last_page > 1 && (
        <Group justify="center" mt="md">
          <Pagination total={meta.last_page} value={page} onChange={setPage} />
        </Group>
      )}

      <Modal
        opened={formOpen}
        onClose={() => { setFormOpen(false); setEditing(null); }}
        title={editing ? 'Edit Obligation' : 'Register Obligation'}
        size="lg"
      >
        <StatutoryForm
          initialValues={editing ? {
            name: editing.name,
            bill_category_id: editing.bill_category_id || null,
            amount: parseFloat(editing.amount),
            cycle: editing.cycle,
            issue_date: new Date(editing.issue_date),
            remind_days_before: editing.remind_days_before,
            is_active: editing.is_active,
            notes: editing.notes || '',
          } : undefined}
          onSubmit={handleSubmit}
          loading={createMutation.isPending || updateMutation.isPending}
        />
      </Modal>
    </>
  );
}
