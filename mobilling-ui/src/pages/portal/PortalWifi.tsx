import { useState } from 'react';
import {
  Stack, Paper, Title, Text, Group, Badge, Table, Button, Modal, TextInput, NumberInput, Select,
  Switch, Tabs, Center, Loader, ActionIcon, Tooltip, SimpleGrid,
} from '@mantine/core';
import { useForm } from '@mantine/form';
import { modals } from '@mantine/modals';
import { notifications } from '@mantine/notifications';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { IconPlus, IconEdit, IconTrash, IconWifi, IconTicket, IconCoin } from '@tabler/icons-react';
import {
  getPortalWifiRouters, getPortalWifiPlans, createPortalWifiPlan, updatePortalWifiPlan, deletePortalWifiPlan,
  getPortalWifiVouchers, getPortalWifiEarningsSummary, PortalWifiPlan,
} from '../../api/portal';
import { formatCurrency } from '../../utils/formatCurrency';
import dayjs from 'dayjs';

const UNIT_OPTIONS = [
  { value: 'hours', label: 'Hours' },
  { value: 'days', label: 'Days' },
  { value: 'weeks', label: 'Weeks' },
];

function RoutersTab() {
  const { data, isLoading } = useQuery({ queryKey: ['portal-wifi-routers'], queryFn: getPortalWifiRouters });
  const routers = data?.data?.data ?? [];

  if (isLoading) return <Center py="xl"><Loader /></Center>;
  if (routers.length === 0) {
    return <Text c="dimmed" ta="center" py="xl">No routers have been assigned to you yet — ask us to set one up.</Text>;
  }

  return (
    <Paper withBorder p="md">
      <Table.ScrollContainer minWidth={600}>
        <Table striped highlightOnHover>
          <Table.Thead>
            <Table.Tr>
              <Table.Th>Name</Table.Th>
              <Table.Th>Host</Table.Th>
              <Table.Th>Packages</Table.Th>
              <Table.Th>Payment</Table.Th>
              <Table.Th>Status</Table.Th>
            </Table.Tr>
          </Table.Thead>
          <Table.Tbody>
            {routers.map((r) => (
              <Table.Tr key={r.id}>
                <Table.Td fw={500}>{r.name}</Table.Td>
                <Table.Td>{r.host}</Table.Td>
                <Table.Td>{r.plans_count}</Table.Td>
                <Table.Td>
                  <Badge size="sm" variant="light" color={r.payment_mode === 'platform_collected' ? 'violet' : 'gray'}>
                    {r.payment_mode === 'platform_collected' ? 'We collect for you' : 'You collect directly'}
                  </Badge>
                </Table.Td>
                <Table.Td>
                  <Badge color={r.is_active ? 'green' : 'gray'} variant="light">{r.is_active ? 'Active' : 'Inactive'}</Badge>
                </Table.Td>
              </Table.Tr>
            ))}
          </Table.Tbody>
        </Table>
      </Table.ScrollContainer>
    </Paper>
  );
}

function PlansTab() {
  const qc = useQueryClient();
  const [formOpen, setFormOpen] = useState(false);
  const [editing, setEditing] = useState<PortalWifiPlan | null>(null);

  const { data: plansData, isLoading } = useQuery({ queryKey: ['portal-wifi-plans'], queryFn: getPortalWifiPlans });
  const plans = plansData?.data?.data ?? [];
  const { data: routersData } = useQuery({ queryKey: ['portal-wifi-routers'], queryFn: getPortalWifiRouters });
  const routerOptions = (routersData?.data?.data ?? []).map((r) => ({ value: r.id, label: r.name }));

  const form = useForm({
    initialValues: {
      mikrotik_router_id: '', name: '', time_limited: true,
      duration_value: 1, duration_unit: 'days' as 'hours' | 'days' | 'weeks', data_cap_mb: undefined as number | undefined,
      speed_limit_mbps: undefined as number | undefined, price: 0, hotspot_profile: '', is_active: true,
    },
    validate: {
      mikrotik_router_id: (v) => (v ? null : 'Required'),
      name: (v) => (v.trim().length > 0 ? null : 'Required'),
    },
  });

  const closeForm = () => { setFormOpen(false); setEditing(null); form.reset(); };
  const openCreate = () => {
    setEditing(null);
    form.setValues({
      mikrotik_router_id: routerOptions[0]?.value ?? '', name: '', time_limited: true,
      duration_value: 1, duration_unit: 'days', data_cap_mb: undefined, speed_limit_mbps: undefined,
      price: 0, hotspot_profile: '', is_active: true,
    });
    setFormOpen(true);
  };
  const openEdit = (p: PortalWifiPlan) => {
    setEditing(p);
    form.setValues({
      mikrotik_router_id: p.mikrotik_router_id, name: p.name, time_limited: !!p.duration_unit,
      duration_value: p.duration_value ?? 1, duration_unit: p.duration_unit ?? 'days',
      data_cap_mb: p.data_cap_mb ?? undefined, speed_limit_mbps: p.speed_limit_mbps ?? undefined,
      price: p.price, hotspot_profile: p.hotspot_profile ?? '', is_active: p.is_active,
    });
    setFormOpen(true);
  };

  const buildPayload = (v: typeof form.values) => ({
    mikrotik_router_id: v.mikrotik_router_id,
    name: v.name,
    duration_value: v.time_limited ? v.duration_value : null,
    duration_unit: v.time_limited ? v.duration_unit : null,
    data_cap_mb: v.data_cap_mb || null,
    speed_limit_mbps: v.speed_limit_mbps || null,
    price: v.price,
    hotspot_profile: v.hotspot_profile || null,
    is_active: v.is_active,
  });

  const createMutation = useMutation({
    mutationFn: () => createPortalWifiPlan(buildPayload(form.values)),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['portal-wifi-plans'] });
      qc.invalidateQueries({ queryKey: ['portal-wifi-routers'] });
      notifications.show({ title: 'Created', message: 'Package added', color: 'green' });
      closeForm();
    },
    onError: (e: any) => notifications.show({ title: 'Error', message: e.response?.data?.message || 'Failed to create', color: 'red' }),
  });
  const updateMutation = useMutation({
    mutationFn: () => updatePortalWifiPlan(editing!.id, buildPayload(form.values)),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['portal-wifi-plans'] });
      notifications.show({ title: 'Updated', message: 'Package updated', color: 'green' });
      closeForm();
    },
    onError: (e: any) => notifications.show({ title: 'Error', message: e.response?.data?.message || 'Failed to update', color: 'red' }),
  });
  const deleteMutation = useMutation({
    mutationFn: deletePortalWifiPlan,
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['portal-wifi-plans'] });
      qc.invalidateQueries({ queryKey: ['portal-wifi-routers'] });
      notifications.show({ title: 'Deleted', message: 'Package removed', color: 'green' });
    },
    onError: (e: any) => notifications.show({ title: 'Error', message: e.response?.data?.message || 'Failed to delete', color: 'red' }),
  });

  const handleDelete = (p: PortalWifiPlan) => modals.openConfirmModal({
    title: 'Delete package',
    children: `Delete "${p.name}"? Customers will no longer be able to buy it.`,
    labels: { confirm: 'Delete', cancel: 'Cancel' },
    confirmProps: { color: 'red' },
    onConfirm: () => deleteMutation.mutate(p.id),
  });

  if (isLoading) return <Center py="xl"><Loader /></Center>;

  return (
    <Stack gap="md">
      <Group justify="flex-end">
        <Button leftSection={<IconPlus size={16} />} onClick={openCreate} disabled={routerOptions.length === 0}>
          Add Package
        </Button>
      </Group>

      {plans.length === 0 ? (
        <Text c="dimmed" ta="center" py="xl">No packages yet — add one so your customers have something to buy.</Text>
      ) : (
        <Paper withBorder p="md">
          <Table.ScrollContainer minWidth={700}>
            <Table striped highlightOnHover>
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>Router</Table.Th>
                  <Table.Th>Name</Table.Th>
                  <Table.Th>Limits</Table.Th>
                  <Table.Th>Price</Table.Th>
                  <Table.Th>Status</Table.Th>
                  <Table.Th w={100}>Actions</Table.Th>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {plans.map((p) => (
                  <Table.Tr key={p.id}>
                    <Table.Td>{p.router?.name ?? '—'}</Table.Td>
                    <Table.Td fw={500}>{p.name}</Table.Td>
                    <Table.Td>
                      <Text size="sm" c="dimmed">
                        {[p.duration_value && p.duration_unit ? `${p.duration_value} ${p.duration_unit}` : null,
                          p.data_cap_mb ? `${p.data_cap_mb} MB` : null]
                          .filter(Boolean).join(' · ') || '—'}
                      </Text>
                    </Table.Td>
                    <Table.Td>{formatCurrency(p.price)}</Table.Td>
                    <Table.Td>
                      <Badge color={p.is_active ? 'green' : 'gray'} variant="light">{p.is_active ? 'Active' : 'Inactive'}</Badge>
                    </Table.Td>
                    <Table.Td>
                      <Group gap="xs">
                        <ActionIcon variant="light" onClick={() => openEdit(p)}><IconEdit size={16} /></ActionIcon>
                        <ActionIcon variant="light" color="red" onClick={() => handleDelete(p)}><IconTrash size={16} /></ActionIcon>
                      </Group>
                    </Table.Td>
                  </Table.Tr>
                ))}
              </Table.Tbody>
            </Table>
          </Table.ScrollContainer>
        </Paper>
      )}

      <Modal opened={formOpen} onClose={closeForm} title={editing ? 'Edit Package' : 'New Package'} size="md">
        <form onSubmit={form.onSubmit(() => (editing ? updateMutation : createMutation).mutate())}>
          <Stack>
            <Select label="Router" required data={routerOptions} {...form.getInputProps('mikrotik_router_id')} />
            <TextInput label="Name" required placeholder="e.g. 1 Day Unlimited" {...form.getInputProps('name')} />
            <Switch label="Time-limited" {...form.getInputProps('time_limited', { type: 'checkbox' })} />
            {form.values.time_limited && (
              <Group grow>
                <NumberInput label="Duration" min={1} {...form.getInputProps('duration_value')} />
                <Select label="Unit" data={UNIT_OPTIONS} {...form.getInputProps('duration_unit')} />
              </Group>
            )}
            <NumberInput label="Data cap (MB, optional)" min={1} {...form.getInputProps('data_cap_mb')} />
            <NumberInput label="Speed limit (Mbps, optional)" min={0.1} step={0.1} {...form.getInputProps('speed_limit_mbps')} />
            <NumberInput label="Price (TZS)" required min={0} {...form.getInputProps('price')} />
            <TextInput label="Hotspot profile (optional)" {...form.getInputProps('hotspot_profile')} />
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
    </Stack>
  );
}

function VouchersTab() {
  const { data: summaryData } = useQuery({ queryKey: ['portal-wifi-earnings'], queryFn: getPortalWifiEarningsSummary });
  const summary = summaryData?.data?.data;
  const { data, isLoading } = useQuery({ queryKey: ['portal-wifi-vouchers'], queryFn: () => getPortalWifiVouchers() });
  const vouchers = data?.data?.data ?? [];

  return (
    <Stack gap="md">
      {summary && (summary.unsettled_count > 0 || summary.total_settled > 0) && (
        <SimpleGrid cols={{ base: 1, sm: 3 }}>
          <Paper withBorder p="md">
            <Text size="xs" c="dimmed">Owed to you (unsettled)</Text>
            <Text fw={700} size="lg">{formatCurrency(summary.owed)}</Text>
          </Paper>
          <Paper withBorder p="md">
            <Text size="xs" c="dimmed">Unsettled sales</Text>
            <Text fw={700} size="lg">{summary.unsettled_count}</Text>
          </Paper>
          <Paper withBorder p="md">
            <Text size="xs" c="dimmed">Already settled (all time)</Text>
            <Text fw={700} size="lg">{formatCurrency(summary.total_settled)}</Text>
          </Paper>
        </SimpleGrid>
      )}

      {isLoading ? (
        <Center py="xl"><Loader /></Center>
      ) : vouchers.length === 0 ? (
        <Text c="dimmed" ta="center" py="xl">No voucher sales yet.</Text>
      ) : (
        <Paper withBorder p="md">
          <Table.ScrollContainer minWidth={700}>
            <Table striped highlightOnHover>
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>Date</Table.Th>
                  <Table.Th>Router</Table.Th>
                  <Table.Th>Package</Table.Th>
                  <Table.Th>Customer</Table.Th>
                  <Table.Th>Amount</Table.Th>
                  <Table.Th>Status</Table.Th>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {vouchers.map((v) => (
                  <Table.Tr key={v.id}>
                    <Table.Td>{dayjs(v.completed_at).format('D MMM YYYY HH:mm')}</Table.Td>
                    <Table.Td>{v.router?.name ?? '—'}</Table.Td>
                    <Table.Td>{v.plan?.name ?? '—'}</Table.Td>
                    <Table.Td>{v.customer_phone}</Table.Td>
                    <Table.Td>{formatCurrency(v.amount)}</Table.Td>
                    <Table.Td>
                      {v.net_amount !== null ? (
                        <Tooltip label={`Commission: ${formatCurrency(v.commission_amount ?? 0)} · Net: ${formatCurrency(v.net_amount)}`}>
                          <Badge size="sm" variant="light" color={v.settled_at ? 'green' : 'orange'}>
                            {v.settled_at ? 'Settled' : 'Owed to you'}
                          </Badge>
                        </Tooltip>
                      ) : (
                        <Text size="xs" c="dimmed">Direct to you</Text>
                      )}
                    </Table.Td>
                  </Table.Tr>
                ))}
              </Table.Tbody>
            </Table>
          </Table.ScrollContainer>
        </Paper>
      )}
    </Stack>
  );
}

export default function PortalWifi() {
  return (
    <Stack gap="md">
      <Group gap="xs">
        <IconWifi size={22} />
        <Title order={3}>WiFi Hotspot</Title>
      </Group>

      <Tabs defaultValue="routers">
        <Tabs.List>
          <Tabs.Tab value="routers" leftSection={<IconWifi size={14} />}>Routers</Tabs.Tab>
          <Tabs.Tab value="plans" leftSection={<IconTicket size={14} />}>Packages</Tabs.Tab>
          <Tabs.Tab value="vouchers" leftSection={<IconCoin size={14} />}>Sales</Tabs.Tab>
        </Tabs.List>
        <Tabs.Panel value="routers" pt="md"><RoutersTab /></Tabs.Panel>
        <Tabs.Panel value="plans" pt="md"><PlansTab /></Tabs.Panel>
        <Tabs.Panel value="vouchers" pt="md"><VouchersTab /></Tabs.Panel>
      </Tabs>
    </Stack>
  );
}
