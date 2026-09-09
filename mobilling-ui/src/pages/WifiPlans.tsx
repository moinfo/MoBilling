import { useState } from 'react';
import { Title, Table, Text, Group, Pagination, Badge, ActionIcon, Modal, Button, TextInput, NumberInput, Select, Switch, Stack } from '@mantine/core';
import { useForm } from '@mantine/form';
import { modals } from '@mantine/modals';
import { notifications } from '@mantine/notifications';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { IconPlus, IconEdit, IconTrash } from '@tabler/icons-react';
import { getWifiPlans, createWifiPlan, updateWifiPlan, deleteWifiPlan, WifiPlan, WifiDurationUnit } from '../api/wifiPlans';
import { getMikrotikRouters, MikrotikRouter } from '../api/mikrotikRouters';
import { usePermissions } from '../hooks/usePermissions';
import { formatCurrency } from '../utils/formatCurrency';

const UNIT_OPTIONS = [
  { value: 'hours', label: 'Hours' },
  { value: 'days', label: 'Days' },
  { value: 'weeks', label: 'Weeks' },
];

export default function WifiPlans() {
  const queryClient = useQueryClient();
  const { can } = usePermissions();
  const canCreate = can('wifi_plans.create');
  const canUpdate = can('wifi_plans.update');
  const canDelete = can('wifi_plans.delete');

  const [page, setPage] = useState(1);
  const [filterRouter, setFilterRouter] = useState<string | null>(null);
  const [formOpen, setFormOpen] = useState(false);
  const [editing, setEditing] = useState<WifiPlan | null>(null);

  const { data: routersData } = useQuery({
    queryKey: ['mikrotik-routers-all'],
    queryFn: () => getMikrotikRouters({ per_page: 200 }),
  });
  const routers: MikrotikRouter[] = routersData?.data?.data || [];
  const routerOptions = routers.map((r) => ({ value: r.id, label: r.name }));

  const { data } = useQuery({
    queryKey: ['wifi-plans', page, filterRouter],
    queryFn: () => getWifiPlans({ page, mikrotik_router_id: filterRouter || undefined }),
  });
  const items: WifiPlan[] = data?.data?.data || [];
  const meta = data?.data?.meta;

  const form = useForm({
    initialValues: {
      mikrotik_router_id: '', name: '', duration_value: 1, duration_unit: 'days' as WifiDurationUnit,
      price: 0, hotspot_profile: '', is_active: true,
    },
    validate: {
      mikrotik_router_id: (v) => (v ? null : 'Required'),
      name: (v) => (v.trim().length > 0 ? null : 'Required'),
      duration_value: (v) => (v >= 1 ? null : 'Must be at least 1'),
      price: (v) => (v >= 0 ? null : 'Must be 0 or greater'),
    },
  });

  const closeForm = () => { setFormOpen(false); setEditing(null); form.reset(); };
  const openCreate = () => {
    setEditing(null);
    form.setValues({ mikrotik_router_id: filterRouter || '', name: '', duration_value: 1, duration_unit: 'days', price: 0, hotspot_profile: '', is_active: true });
    setFormOpen(true);
  };
  const openEdit = (p: WifiPlan) => {
    setEditing(p);
    form.setValues({
      mikrotik_router_id: p.mikrotik_router_id, name: p.name, duration_value: p.duration_value,
      duration_unit: p.duration_unit, price: parseFloat(p.price) || 0, hotspot_profile: p.hotspot_profile || '', is_active: p.is_active,
    });
    setFormOpen(true);
  };

  const buildPayload = (v: typeof form.values) => ({
    ...v,
    hotspot_profile: v.hotspot_profile || undefined,
  });

  const createMutation = useMutation({
    mutationFn: (v: typeof form.values) => createWifiPlan(buildPayload(v)),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['wifi-plans'] });
      notifications.show({ title: 'Created', message: 'Plan added', color: 'green' });
      closeForm();
    },
    onError: (err: any) => notifications.show({ title: 'Error', message: err.response?.data?.message || 'Failed to create', color: 'red' }),
  });

  const updateMutation = useMutation({
    mutationFn: (v: typeof form.values) => updateWifiPlan(editing!.id, buildPayload(v)),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['wifi-plans'] });
      notifications.show({ title: 'Updated', message: 'Plan updated', color: 'green' });
      closeForm();
    },
    onError: (err: any) => notifications.show({ title: 'Error', message: err.response?.data?.message || 'Failed to update', color: 'red' }),
  });

  const deleteMutation = useMutation({
    mutationFn: deleteWifiPlan,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['wifi-plans'] });
      notifications.show({ title: 'Deleted', message: 'Plan deleted', color: 'green' });
    },
    onError: (err: any) => notifications.show({ title: 'Error', message: err.response?.data?.message || 'Failed to delete', color: 'red' }),
  });

  const handleDelete = (p: WifiPlan) => modals.openConfirmModal({
    title: 'Delete Plan',
    children: `Delete "${p.name}"?`,
    labels: { confirm: 'Delete', cancel: 'Cancel' },
    confirmProps: { color: 'red' },
    onConfirm: () => deleteMutation.mutate(p.id),
  });

  return (
    <>
      <Group justify="space-between" mb="md" wrap="wrap">
        <Title order={2}>WiFi Plans</Title>
        <Group wrap="wrap">
          <Select placeholder="All routers" data={routerOptions} clearable searchable
            value={filterRouter} onChange={(v) => { setFilterRouter(v); setPage(1); }} maw={220} />
          {canCreate && (
            <Button leftSection={<IconPlus size={16} />} onClick={openCreate}>Add Plan</Button>
          )}
        </Group>
      </Group>

      {items.length === 0 ? (
        <Text c="dimmed" ta="center" py="xl">No plans yet</Text>
      ) : (
        <Table striped highlightOnHover>
          <Table.Thead>
            <Table.Tr>
              <Table.Th>Name</Table.Th>
              <Table.Th>Router</Table.Th>
              <Table.Th>Duration</Table.Th>
              <Table.Th style={{ textAlign: 'right' }}>Price</Table.Th>
              <Table.Th>Status</Table.Th>
              {(canUpdate || canDelete) && <Table.Th w={100}>Actions</Table.Th>}
            </Table.Tr>
          </Table.Thead>
          <Table.Tbody>
            {items.map((p) => (
              <Table.Tr key={p.id}>
                <Table.Td fw={500}>{p.name}</Table.Td>
                <Table.Td>{p.router?.name || '—'}</Table.Td>
                <Table.Td>{p.duration_value} {p.duration_unit}</Table.Td>
                <Table.Td style={{ textAlign: 'right' }}>{formatCurrency(p.price)}</Table.Td>
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

      <Modal opened={formOpen} onClose={closeForm} title={editing ? 'Edit Plan' : 'New Plan'} size="md">
        <form onSubmit={form.onSubmit((v) => (editing ? updateMutation : createMutation).mutate(v))}>
          <Stack>
            <Select label="Router" required data={routerOptions} searchable {...form.getInputProps('mikrotik_router_id')} />
            <TextInput label="Name" required placeholder="e.g. 1 Day Unlimited" {...form.getInputProps('name')} />
            <Group grow>
              <NumberInput label="Duration" required min={1} {...form.getInputProps('duration_value')} />
              <Select label="Unit" required data={UNIT_OPTIONS} {...form.getInputProps('duration_unit')} />
            </Group>
            <NumberInput label="Price" required min={0} decimalScale={2} {...form.getInputProps('price')} />
            <TextInput label="Hotspot Profile (optional)"
              description="RouterOS user profile to assign (e.g. a speed-limit profile) — leave blank for the router's default"
              {...form.getInputProps('hotspot_profile')} />
            <Switch label="Active" {...form.getInputProps('is_active', { type: 'checkbox' })} />
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
