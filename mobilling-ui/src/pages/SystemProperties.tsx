import { useState } from 'react';
import { Title, Table, Text, Group, Pagination, Badge, ActionIcon, Modal, Button, TextInput, Stack } from '@mantine/core';
import { useForm } from '@mantine/form';
import { useDebouncedValue } from '@mantine/hooks';
import { modals } from '@mantine/modals';
import { notifications } from '@mantine/notifications';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { IconPlus, IconEdit, IconTrash, IconSearch } from '@tabler/icons-react';
import { getSystemProperties, createSystemProperty, updateSystemProperty, deleteSystemProperty, SystemProperty } from '../api/systemProperties';
import { usePermissions } from '../hooks/usePermissions';

export default function SystemProperties() {
  const queryClient = useQueryClient();
  const { can } = usePermissions();
  const canCreate = can('system_properties.create');
  const canUpdate = can('system_properties.update');
  const canDelete = can('system_properties.delete');

  const [page, setPage] = useState(1);
  const [search, setSearch] = useState('');
  const [debouncedSearch] = useDebouncedValue(search, 300);
  const [formOpen, setFormOpen] = useState(false);
  const [editing, setEditing] = useState<SystemProperty | null>(null);

  const { data } = useQuery({
    queryKey: ['system-properties', page, debouncedSearch],
    queryFn: () => getSystemProperties({ page, search: debouncedSearch || undefined }),
  });

  const items: SystemProperty[] = data?.data?.data || [];
  const meta = data?.data?.meta;

  const form = useForm({
    initialValues: { name: '', is_active: true },
    validate: { name: (v) => (v.trim().length > 0 ? null : 'Required') },
  });

  const closeForm = () => { setFormOpen(false); setEditing(null); form.reset(); };
  const openCreate = () => { setEditing(null); form.setValues({ name: '', is_active: true }); setFormOpen(true); };
  const openEdit = (p: SystemProperty) => { setEditing(p); form.setValues({ name: p.name, is_active: p.is_active }); setFormOpen(true); };

  const createMutation = useMutation({
    mutationFn: createSystemProperty,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['system-properties'] });
      notifications.show({ title: 'Created', message: 'Property added', color: 'green' });
      closeForm();
    },
    onError: (err: any) => notifications.show({ title: 'Error', message: err.response?.data?.message || 'Failed to create', color: 'red' }),
  });

  const updateMutation = useMutation({
    mutationFn: (values: any) => updateSystemProperty(editing!.id, values),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['system-properties'] });
      notifications.show({ title: 'Updated', message: 'Property updated', color: 'green' });
      closeForm();
    },
    onError: (err: any) => notifications.show({ title: 'Error', message: err.response?.data?.message || 'Failed to update', color: 'red' }),
  });

  const deleteMutation = useMutation({
    mutationFn: deleteSystemProperty,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['system-properties'] });
      notifications.show({ title: 'Deleted', message: 'Property deleted', color: 'green' });
    },
    onError: (err: any) => notifications.show({ title: 'Error', message: err.response?.data?.message || 'Failed to delete', color: 'red' }),
  });

  const handleDelete = (p: SystemProperty) => modals.openConfirmModal({
    title: 'Delete System Property',
    children: `Delete "${p.name}"?`,
    labels: { confirm: 'Delete', cancel: 'Cancel' },
    confirmProps: { color: 'red' },
    onConfirm: () => deleteMutation.mutate(p.id),
  });

  return (
    <>
      <Group justify="space-between" mb="md">
        <Title order={2}>System Properties</Title>
        <Group>
          <TextInput placeholder="Search..." leftSection={<IconSearch size={16} />}
            value={search} onChange={(e) => { setSearch(e.currentTarget.value); setPage(1); }} maw={250} />
          {canCreate && (
            <Button leftSection={<IconPlus size={16} />} onClick={openCreate}>Add Property</Button>
          )}
        </Group>
      </Group>

      {items.length === 0 ? (
        <Text c="dimmed" ta="center" py="xl">No properties yet</Text>
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
            {items.map((p) => (
              <Table.Tr key={p.id}>
                <Table.Td fw={500}>{p.name}</Table.Td>
                <Table.Td>
                  <Badge color={p.is_active ? 'green' : 'gray'} variant="light">
                    {p.is_active ? 'Active' : 'Inactive'}
                  </Badge>
                </Table.Td>
                {(canUpdate || canDelete) && (
                  <Table.Td>
                    <Group gap="xs">
                      {canUpdate && <ActionIcon variant="light" onClick={() => openEdit(p)}><IconEdit size={16} /></ActionIcon>}
                      {canDelete && <ActionIcon variant="light" color="red" onClick={() => handleDelete(p)}><IconTrash size={16} /></ActionIcon>}
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

      <Modal opened={formOpen} onClose={closeForm} title={editing ? 'Edit Property' : 'New Property'} size="md">
        <form onSubmit={form.onSubmit((v) => (editing ? updateMutation : createMutation).mutate(v))}>
          <Stack>
            <TextInput label="Name" required placeholder="Property name" {...form.getInputProps('name')} />
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
