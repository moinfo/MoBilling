import { useState } from 'react';
import { Title, Table, Text, Group, Pagination, Badge, ActionIcon, Modal, Button, TextInput, NumberInput, Stack, Anchor } from '@mantine/core';
import { useForm } from '@mantine/form';
import { useDebouncedValue } from '@mantine/hooks';
import { modals } from '@mantine/modals';
import { notifications } from '@mantine/notifications';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { IconPlus, IconEdit, IconTrash, IconSearch, IconMapPin } from '@tabler/icons-react';
import { getWorkLocations, createWorkLocation, updateWorkLocation, deleteWorkLocation, WorkLocation } from '../api/workLocations';
import { usePermissions } from '../hooks/usePermissions';

export default function WorkLocations() {
  const queryClient = useQueryClient();
  const { can } = usePermissions();
  const canCreate = can('work_locations.create');
  const canUpdate = can('work_locations.update');
  const canDelete = can('work_locations.delete');

  const [page, setPage] = useState(1);
  const [search, setSearch] = useState('');
  const [debouncedSearch] = useDebouncedValue(search, 300);
  const [formOpen, setFormOpen] = useState(false);
  const [editing, setEditing] = useState<WorkLocation | null>(null);

  const { data } = useQuery({
    queryKey: ['work-locations', page, debouncedSearch],
    queryFn: () => getWorkLocations({ page, search: debouncedSearch || undefined }),
  });

  const items: WorkLocation[] = data?.data?.data || [];
  const meta = data?.data?.meta;

  const form = useForm({
    initialValues: { name: '', latitude: 0, longitude: 0, radius_meters: 150, is_active: true },
    validate: {
      name: (v) => (v.trim().length > 0 ? null : 'Required'),
      latitude: (v) => (v >= -90 && v <= 90 ? null : 'Must be between -90 and 90'),
      longitude: (v) => (v >= -180 && v <= 180 ? null : 'Must be between -180 and 180'),
    },
  });

  const closeForm = () => { setFormOpen(false); setEditing(null); form.reset(); };
  const openCreate = () => { setEditing(null); form.setValues({ name: '', latitude: 0, longitude: 0, radius_meters: 150, is_active: true }); setFormOpen(true); };
  const openEdit = (l: WorkLocation) => { setEditing(l); form.setValues({ name: l.name, latitude: l.latitude, longitude: l.longitude, radius_meters: l.radius_meters, is_active: l.is_active }); setFormOpen(true); };

  const createMutation = useMutation({
    mutationFn: (v: typeof form.values) => createWorkLocation(v),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['work-locations'] });
      notifications.show({ title: 'Created', message: 'Work location added', color: 'green' });
      closeForm();
    },
    onError: (err: any) => notifications.show({ title: 'Error', message: err.response?.data?.message || 'Failed to create', color: 'red' }),
  });

  const updateMutation = useMutation({
    mutationFn: (v: typeof form.values) => updateWorkLocation(editing!.id, v),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['work-locations'] });
      notifications.show({ title: 'Updated', message: 'Work location updated', color: 'green' });
      closeForm();
    },
    onError: (err: any) => notifications.show({ title: 'Error', message: err.response?.data?.message || 'Failed to update', color: 'red' }),
  });

  const deleteMutation = useMutation({
    mutationFn: deleteWorkLocation,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['work-locations'] });
      notifications.show({ title: 'Deleted', message: 'Work location deleted', color: 'green' });
    },
    onError: (err: any) => notifications.show({ title: 'Error', message: err.response?.data?.message || 'Failed to delete', color: 'red' }),
  });

  const handleDelete = (l: WorkLocation) => modals.openConfirmModal({
    title: 'Delete Work Location',
    children: `Delete "${l.name}"? Staff assigned to it will need to be reassigned first.`,
    labels: { confirm: 'Delete', cancel: 'Cancel' },
    confirmProps: { color: 'red' },
    onConfirm: () => deleteMutation.mutate(l.id),
  });

  return (
    <>
      <Group justify="space-between" mb="md">
        <Title order={2}>Work Locations</Title>
        <Group>
          <TextInput placeholder="Search..." leftSection={<IconSearch size={16} />}
            value={search} onChange={(e) => { setSearch(e.currentTarget.value); setPage(1); }} maw={250} />
          {canCreate && (
            <Button leftSection={<IconPlus size={16} />} onClick={openCreate}>Add Work Location</Button>
          )}
        </Group>
      </Group>

      <Text c="dimmed" size="sm" mb="md">
        Offices/sites staff self-check-in (mobile app) is geofenced against. A staff member must be within
        the radius shown below to check in or out.
      </Text>

      {items.length === 0 ? (
        <Text c="dimmed" ta="center" py="xl">No work locations yet</Text>
      ) : (
        <Table striped highlightOnHover>
          <Table.Thead>
            <Table.Tr>
              <Table.Th>Name</Table.Th>
              <Table.Th>Coordinates</Table.Th>
              <Table.Th>Radius</Table.Th>
              <Table.Th>Staff</Table.Th>
              <Table.Th>Status</Table.Th>
              {(canUpdate || canDelete) && <Table.Th w={100}>Actions</Table.Th>}
            </Table.Tr>
          </Table.Thead>
          <Table.Tbody>
            {items.map((l) => (
              <Table.Tr key={l.id}>
                <Table.Td fw={500}>{l.name}</Table.Td>
                <Table.Td>
                  <Anchor href={`https://www.google.com/maps?q=${l.latitude},${l.longitude}`} target="_blank" rel="noopener noreferrer" size="sm">
                    <Group gap={4} wrap="nowrap">
                      <IconMapPin size={14} />
                      <Text size="sm">{l.latitude.toFixed(6)}, {l.longitude.toFixed(6)}</Text>
                    </Group>
                  </Anchor>
                </Table.Td>
                <Table.Td>{l.radius_meters}m</Table.Td>
                <Table.Td>{l.staff_count ?? 0}</Table.Td>
                <Table.Td>
                  <Badge color={l.is_active ? 'green' : 'gray'} variant="light">
                    {l.is_active ? 'Active' : 'Inactive'}
                  </Badge>
                </Table.Td>
                {(canUpdate || canDelete) && (
                  <Table.Td>
                    <Group gap="xs">
                      {canUpdate && <ActionIcon variant="light" onClick={() => openEdit(l)}><IconEdit size={16} /></ActionIcon>}
                      {canDelete && <ActionIcon variant="light" color="red" onClick={() => handleDelete(l)}><IconTrash size={16} /></ActionIcon>}
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

      <Modal opened={formOpen} onClose={closeForm} title={editing ? 'Edit Work Location' : 'New Work Location'} size="md">
        <form onSubmit={form.onSubmit((v) => (editing ? updateMutation : createMutation).mutate(v))}>
          <Stack>
            <TextInput label="Name" required placeholder="e.g. Head Office" {...form.getInputProps('name')} />
            <Group grow>
              <NumberInput label="Latitude" required decimalScale={7} placeholder="-6.7924000" {...form.getInputProps('latitude')} />
              <NumberInput label="Longitude" required decimalScale={7} placeholder="39.2083000" {...form.getInputProps('longitude')} />
            </Group>
            <Text size="xs" c="dimmed">
              Tip: open Google Maps on the phone, long-press the exact spot, and copy the coordinates shown.
            </Text>
            <NumberInput label="Check-in Radius (meters)" min={10} max={5000}
              description="Phone GPS is rarely accurate to better than 10-20m indoors — leave headroom"
              {...form.getInputProps('radius_meters')} />
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
