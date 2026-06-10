import { useState } from 'react';
import { Title, Table, Text, Group, Pagination, Badge, ActionIcon, Modal, Button, TextInput, Stack } from '@mantine/core';
import { useForm } from '@mantine/form';
import { useDebouncedValue } from '@mantine/hooks';
import { modals } from '@mantine/modals';
import { notifications } from '@mantine/notifications';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { IconPlus, IconEdit, IconTrash, IconSearch } from '@tabler/icons-react';
import { getSystems, createSystem, updateSystem, deleteSystem, System } from '../api/systems';
import { usePermissions } from '../hooks/usePermissions';

export default function Systems() {
  const queryClient = useQueryClient();
  const { can } = usePermissions();
  const canCreate = can('systems.create');
  const canUpdate = can('systems.update');
  const canDelete = can('systems.delete');

  const [page, setPage] = useState(1);
  const [search, setSearch] = useState('');
  const [debouncedSearch] = useDebouncedValue(search, 300);
  const [formOpen, setFormOpen] = useState(false);
  const [editing, setEditing] = useState<System | null>(null);

  const { data } = useQuery({
    queryKey: ['systems', page, debouncedSearch],
    queryFn: () => getSystems({ page, search: debouncedSearch || undefined }),
  });

  const items: System[] = data?.data?.data || [];
  const meta = data?.data?.meta;

  const form = useForm({
    initialValues: { name: '', is_active: true },
    validate: { name: (v) => (v.trim().length > 0 ? null : 'Required') },
  });

  const closeForm = () => { setFormOpen(false); setEditing(null); form.reset(); };
  const openCreate = () => { setEditing(null); form.setValues({ name: '', is_active: true }); setFormOpen(true); };
  const openEdit = (s: System) => { setEditing(s); form.setValues({ name: s.name, is_active: s.is_active }); setFormOpen(true); };

  const createMutation = useMutation({
    mutationFn: createSystem,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['systems'] });
      notifications.show({ title: 'Created', message: 'System added', color: 'green' });
      closeForm();
    },
    onError: (err: any) => notifications.show({ title: 'Error', message: err.response?.data?.message || 'Failed to create', color: 'red' }),
  });

  const updateMutation = useMutation({
    mutationFn: (values: any) => updateSystem(editing!.id, values),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['systems'] });
      notifications.show({ title: 'Updated', message: 'System updated', color: 'green' });
      closeForm();
    },
    onError: (err: any) => notifications.show({ title: 'Error', message: err.response?.data?.message || 'Failed to update', color: 'red' }),
  });

  const deleteMutation = useMutation({
    mutationFn: deleteSystem,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['systems'] });
      notifications.show({ title: 'Deleted', message: 'System deleted', color: 'green' });
    },
    onError: (err: any) => notifications.show({ title: 'Error', message: err.response?.data?.message || 'Failed to delete', color: 'red' }),
  });

  const handleDelete = (s: System) => modals.openConfirmModal({
    title: 'Delete System',
    children: `Delete "${s.name}"?`,
    labels: { confirm: 'Delete', cancel: 'Cancel' },
    confirmProps: { color: 'red' },
    onConfirm: () => deleteMutation.mutate(s.id),
  });

  return (
    <>
      <Group justify="space-between" mb="md">
        <Title order={2}>Systems</Title>
        <Group>
          <TextInput placeholder="Search..." leftSection={<IconSearch size={16} />}
            value={search} onChange={(e) => { setSearch(e.currentTarget.value); setPage(1); }} maw={250} />
          {canCreate && (
            <Button leftSection={<IconPlus size={16} />} onClick={openCreate}>Add System</Button>
          )}
        </Group>
      </Group>

      {items.length === 0 ? (
        <Text c="dimmed" ta="center" py="xl">No systems yet</Text>
      ) : (
        <Table striped highlightOnHover>
          <Table.Thead>
            <Table.Tr>
              <Table.Th>Name</Table.Th>
              <Table.Th>Status</Table.Th>
              {(canUpdate || canDelete) && <Table.Th w={100}>Actions</Table.Th>}
            </Table.Tr>
          </Table.Thead>
          <Table.Tbody>
            {items.map((s) => (
              <Table.Tr key={s.id}>
                <Table.Td fw={500}>{s.name}</Table.Td>
                <Table.Td>
                  <Badge color={s.is_active ? 'green' : 'gray'} variant="light">
                    {s.is_active ? 'Active' : 'Inactive'}
                  </Badge>
                </Table.Td>
                {(canUpdate || canDelete) && (
                  <Table.Td>
                    <Group gap="xs">
                      {canUpdate && <ActionIcon variant="light" onClick={() => openEdit(s)}><IconEdit size={16} /></ActionIcon>}
                      {canDelete && <ActionIcon variant="light" color="red" onClick={() => handleDelete(s)}><IconTrash size={16} /></ActionIcon>}
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

      <Modal opened={formOpen} onClose={closeForm} title={editing ? 'Edit System' : 'New System'} size="md">
        <form onSubmit={form.onSubmit((v) => (editing ? updateMutation : createMutation).mutate(v))}>
          <Stack>
            <TextInput label="Name" required placeholder="System name" {...form.getInputProps('name')} />
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
