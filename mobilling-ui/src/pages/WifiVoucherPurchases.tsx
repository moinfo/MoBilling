import { useState } from 'react';
import { Title, Table, Text, Group, Pagination, Badge, TextInput, Select, Code, Button, Modal, Stack, Alert, ActionIcon, Tooltip, Progress, Loader } from '@mantine/core';
import { useForm } from '@mantine/form';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useDebouncedValue } from '@mantine/hooks';
import { notifications } from '@mantine/notifications';
import { modals } from '@mantine/modals';
import { IconSearch, IconPlus, IconCheck, IconGauge, IconBan, IconLockOpen } from '@tabler/icons-react';
import {
  getWifiVoucherPurchases, createManualWifiVoucherSale, getWifiVoucherPurchaseUsage,
  blockWifiVoucherPurchase, unblockWifiVoucherPurchase, WifiVoucherPurchase,
} from '../api/wifiVoucherPurchases';
import { getMikrotikRouters, MikrotikRouter } from '../api/mikrotikRouters';
import { getWifiPlans, WifiPlan } from '../api/wifiPlans';
import { formatCurrency } from '../utils/formatCurrency';
import { formatDate } from '../utils/formatDate';
import { usePermissions } from '../hooks/usePermissions';

const PAYMENT_METHOD_OPTIONS = [
  { value: 'cash', label: 'Cash' },
  { value: 'mpesa', label: 'M-Pesa / Mobile Money' },
  { value: 'bank', label: 'Bank Transfer' },
  { value: 'other', label: 'Other' },
];

const STATUS_COLOR: Record<string, string> = { pending: 'blue', completed: 'green', failed: 'red' };

const STATUS_OPTIONS = [
  { value: 'pending', label: 'Pending' },
  { value: 'completed', label: 'Completed' },
  { value: 'failed', label: 'Failed' },
];

export default function WifiVoucherPurchases() {
  const queryClient = useQueryClient();
  const { can } = usePermissions();
  const canSell = can('wifi_purchases.create');
  const canBlock = can('wifi_purchases.update');

  const [page, setPage] = useState(1);
  const [search, setSearch] = useState('');
  const [debouncedSearch] = useDebouncedValue(search, 300);
  const [filterRouter, setFilterRouter] = useState<string | null>(null);
  const [filterStatus, setFilterStatus] = useState<string | null>(null);
  const [sellOpen, setSellOpen] = useState(false);
  const [usageFor, setUsageFor] = useState<WifiVoucherPurchase | null>(null);

  const { data: routersData } = useQuery({
    queryKey: ['mikrotik-routers-all'],
    queryFn: () => getMikrotikRouters({ per_page: 200 }),
  });
  const routers: MikrotikRouter[] = routersData?.data?.data || [];
  const routerOptions = routers.map((r) => ({ value: r.id, label: r.name }));

  const { data } = useQuery({
    queryKey: ['wifi-voucher-purchases', page, debouncedSearch, filterRouter, filterStatus],
    queryFn: () => getWifiVoucherPurchases({
      page,
      search: debouncedSearch || undefined,
      mikrotik_router_id: filterRouter || undefined,
      status: filterStatus || undefined,
    }),
  });
  const items: WifiVoucherPurchase[] = data?.data?.data || [];
  const meta = data?.data?.meta;

  const blockMutation = useMutation({
    mutationFn: ({ id, reason }: { id: string; reason?: string }) => blockWifiVoucherPurchase(id, reason),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['wifi-voucher-purchases'] });
      notifications.show({ title: 'Blocked', message: 'Voucher access has been revoked.', color: 'orange' });
    },
    onError: (err: any) => notifications.show({ title: 'Error', message: err.response?.data?.message || 'Failed to block voucher', color: 'red' }),
  });

  const unblockMutation = useMutation({
    mutationFn: (id: string) => unblockWifiVoucherPurchase(id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['wifi-voucher-purchases'] });
      notifications.show({ title: 'Unblocked', message: 'Voucher access restored.', color: 'green' });
    },
    onError: (err: any) => notifications.show({ title: 'Error', message: err.response?.data?.message || 'Failed to unblock voucher', color: 'red' }),
  });

  const handleBlock = (p: WifiVoucherPurchase) => {
    let reason = '';
    modals.open({
      title: `Block ${p.hotspot_username}?`,
      children: (
        <Stack>
          <Text size="sm">This immediately disconnects and locks out this customer. They'll no longer be able to use this voucher.</Text>
          <TextInput label="Reason (optional)" placeholder="e.g. abusing bandwidth, sharing outside premises"
            onChange={(e) => { reason = e.currentTarget.value; }} />
          <Group justify="flex-end">
            <Button variant="default" onClick={() => modals.closeAll()}>Cancel</Button>
            <Button color="red" onClick={() => { blockMutation.mutate({ id: p.id, reason: reason || undefined }); modals.closeAll(); }}>
              Block
            </Button>
          </Group>
        </Stack>
      ),
    });
  };

  return (
    <>
      <Group justify="space-between" mb="md" wrap="wrap">
        <Title order={2}>WiFi Voucher Sales</Title>
        <Group wrap="wrap">
          <TextInput placeholder="Search by phone..." leftSection={<IconSearch size={16} />}
            value={search} onChange={(e) => { setSearch(e.currentTarget.value); setPage(1); }} maw={220} />
          <Select placeholder="All routers" data={routerOptions} clearable searchable
            value={filterRouter} onChange={(v) => { setFilterRouter(v); setPage(1); }} maw={200} />
          <Select placeholder="All statuses" data={STATUS_OPTIONS} clearable
            value={filterStatus} onChange={(v) => { setFilterStatus(v); setPage(1); }} maw={160} />
          {canSell && (
            <Button leftSection={<IconPlus size={16} />} onClick={() => setSellOpen(true)}>Sell Voucher (Cash)</Button>
          )}
        </Group>
      </Group>

      {items.length === 0 ? (
        <Text c="dimmed" ta="center" py="xl">No voucher sales yet</Text>
      ) : (
        <Table.ScrollContainer minWidth={800}>
          <Table striped highlightOnHover>
            <Table.Thead>
              <Table.Tr>
                <Table.Th>Date</Table.Th>
                <Table.Th>Phone</Table.Th>
                <Table.Th>Router</Table.Th>
                <Table.Th>Plan</Table.Th>
                <Table.Th style={{ textAlign: 'right' }}>Amount</Table.Th>
                <Table.Th>Voucher Code</Table.Th>
                <Table.Th>Expires</Table.Th>
                <Table.Th>Method</Table.Th>
                <Table.Th>Status</Table.Th>
                <Table.Th w={90} />
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {items.map((p) => (
                <Table.Tr key={p.id}>
                  <Table.Td>{formatDate(p.created_at)}</Table.Td>
                  <Table.Td>{p.customer_phone}</Table.Td>
                  <Table.Td>{p.router?.name || '—'}</Table.Td>
                  <Table.Td>{p.plan?.name || '—'}</Table.Td>
                  <Table.Td style={{ textAlign: 'right' }}>{formatCurrency(p.amount)}</Table.Td>
                  <Table.Td>{p.hotspot_username ? <Code fz="sm">{p.hotspot_username}</Code> : '—'}</Table.Td>
                  <Table.Td>{p.voucher_expires_at ? formatDate(p.voucher_expires_at) : '—'}</Table.Td>
                  <Table.Td>
                    {p.payment_method_used ? (
                      <Badge size="sm" variant="outline" tt="capitalize">{p.payment_method_used}</Badge>
                    ) : (
                      <Text size="sm" c="dimmed">Online</Text>
                    )}
                  </Table.Td>
                  <Table.Td>
                    <Group gap={4}>
                      <Badge size="sm" variant="light" color={STATUS_COLOR[p.status] ?? 'gray'} tt="capitalize">
                        {p.status}
                      </Badge>
                      {p.blocked_at && (
                        <Tooltip label={p.blocked_reason || 'Blocked'}>
                          <Badge size="sm" variant="filled" color="red">Blocked</Badge>
                        </Tooltip>
                      )}
                    </Group>
                  </Table.Td>
                  <Table.Td>
                    <Group gap="xs">
                      {p.hotspot_username && (
                        <Tooltip label="View data/time usage">
                          <ActionIcon variant="light" onClick={() => setUsageFor(p)}>
                            <IconGauge size={16} />
                          </ActionIcon>
                        </Tooltip>
                      )}
                      {canBlock && p.hotspot_username && (
                        p.blocked_at ? (
                          <Tooltip label="Unblock">
                            <ActionIcon variant="light" color="green" loading={unblockMutation.isPending}
                              onClick={() => unblockMutation.mutate(p.id)}>
                              <IconLockOpen size={16} />
                            </ActionIcon>
                          </Tooltip>
                        ) : (
                          <Tooltip label="Block this voucher">
                            <ActionIcon variant="light" color="red" onClick={() => handleBlock(p)}>
                              <IconBan size={16} />
                            </ActionIcon>
                          </Tooltip>
                        )
                      )}
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

      <Modal opened={sellOpen} onClose={() => setSellOpen(false)} title="Sell Voucher (Cash)" size="md">
        <SellVoucherForm
          routerOptions={routerOptions}
          onDone={() => {
            setSellOpen(false);
            queryClient.invalidateQueries({ queryKey: ['wifi-voucher-purchases'] });
          }}
        />
      </Modal>

      <Modal opened={!!usageFor} onClose={() => setUsageFor(null)} title={`Usage — ${usageFor?.hotspot_username ?? ''}`} size="sm">
        {usageFor && <UsageDetails purchaseId={usageFor.id} />}
      </Modal>
    </>
  );
}

const formatSeconds = (seconds: number) => {
  const d = Math.floor(seconds / 86400);
  const h = Math.floor((seconds % 86400) / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const parts = [];
  if (d) parts.push(`${d}d`);
  if (h) parts.push(`${h}h`);
  if (m || parts.length === 0) parts.push(`${m}m`);
  return parts.join(' ');
};

function UsageDetails({ purchaseId }: { purchaseId: string }) {
  const { data, isLoading } = useQuery({
    queryKey: ['wifi-voucher-usage', purchaseId],
    queryFn: () => getWifiVoucherPurchaseUsage(purchaseId),
  });
  const usage = data?.data?.data;

  if (isLoading) {
    return <Group justify="center" py="lg"><Loader size="sm" /></Group>;
  }
  if (!usage) {
    return <Text c="dimmed" size="sm">Could not load usage.</Text>;
  }

  const dataPercent = usage.data_cap_mb && usage.data_used_mb != null
    ? Math.min(100, (usage.data_used_mb / usage.data_cap_mb) * 100) : null;
  const timePercent = usage.duration_seconds && usage.time_used_seconds != null
    ? Math.min(100, (usage.time_used_seconds / usage.duration_seconds) * 100) : null;

  return (
    <Stack gap="sm">
      {!usage.router_reachable && (
        <Alert color="yellow" variant="light">Router is not reachable right now — figures may be stale.</Alert>
      )}

      {usage.data_cap_mb ? (
        <div>
          <Group justify="space-between" mb={4}>
            <Text size="sm" c="dimmed">Data</Text>
            <Text size="sm" fw={600}>
              {usage.data_used_mb != null ? `${(usage.data_used_mb / 1024).toFixed(2)}GB used / ${(usage.data_cap_mb / 1024).toFixed(2)}GB` : 'Unknown'}
            </Text>
          </Group>
          {dataPercent != null && <Progress value={dataPercent} color={dataPercent > 90 ? 'red' : 'blue'} />}
        </div>
      ) : (
        <Group justify="space-between">
          <Text size="sm" c="dimmed">Data</Text>
          <Text size="sm">Unlimited</Text>
        </Group>
      )}

      {usage.duration_seconds ? (
        <div>
          <Group justify="space-between" mb={4}>
            <Text size="sm" c="dimmed">Time</Text>
            <Text size="sm" fw={600}>
              {usage.time_used_seconds
                ? `${formatSeconds(usage.time_used_seconds)} used / ${formatSeconds(usage.duration_seconds)}`
                : 'Not started yet'}
            </Text>
          </Group>
          {timePercent != null && usage.time_used_seconds ? <Progress value={timePercent} color={timePercent > 90 ? 'red' : 'blue'} /> : null}
        </div>
      ) : (
        <Group justify="space-between">
          <Text size="sm" c="dimmed">Time</Text>
          <Text size="sm">Unlimited</Text>
        </Group>
      )}
    </Stack>
  );
}

function SellVoucherForm({ routerOptions, onDone }: { routerOptions: { value: string; label: string }[]; onDone: () => void }) {
  const form = useForm({
    initialValues: {
      mikrotik_router_id: '', wifi_plan_id: '', customer_phone: '', customer_name: '', payment_method: 'cash',
    },
    validate: {
      mikrotik_router_id: (v) => (v ? null : 'Required'),
      wifi_plan_id: (v) => (v ? null : 'Required'),
      customer_phone: (v) => (v.trim().length > 0 ? null : 'Required'),
    },
  });

  const { data: plansData } = useQuery({
    queryKey: ['wifi-plans-for-sale', form.values.mikrotik_router_id],
    queryFn: () => getWifiPlans({ mikrotik_router_id: form.values.mikrotik_router_id, per_page: 100 }),
    enabled: !!form.values.mikrotik_router_id,
  });
  const plans: WifiPlan[] = ((plansData?.data?.data || []) as WifiPlan[]).filter((p) => p.is_active);
  const planOptions = plans.map((p) => ({ value: p.id, label: `${p.name} — ${formatCurrency(p.price)}` }));

  const mutation = useMutation({
    mutationFn: () => createManualWifiVoucherSale({
      mikrotik_router_id: form.values.mikrotik_router_id,
      wifi_plan_id: form.values.wifi_plan_id,
      customer_phone: form.values.customer_phone.trim(),
      customer_name: form.values.customer_name.trim() || undefined,
      payment_method: form.values.payment_method as 'cash' | 'mpesa' | 'bank' | 'other',
    }),
    onSuccess: (res) => {
      const code = res.data.data.hotspot_username;
      notifications.show({
        title: 'Voucher sent',
        message: code ? `Code ${code} created and sent to the customer's phone.` : 'Voucher created.',
        color: 'green', icon: <IconCheck size={16} />,
      });
      onDone();
    },
    onError: (err: any) => notifications.show({ title: 'Error', message: err.response?.data?.message || 'Failed to sell voucher', color: 'red' }),
  });

  return (
    <form onSubmit={form.onSubmit(() => mutation.mutate())}>
      <Stack>
        <Alert color="blue" variant="light">
          For customers paying with physical cash instead of the online checkout. The voucher is
          created immediately and its code is texted/WhatsApp'd to their phone.
        </Alert>
        <Select label="Router" required placeholder="Select router" data={routerOptions} searchable
          {...form.getInputProps('mikrotik_router_id')}
          onChange={(v) => { form.setFieldValue('mikrotik_router_id', v || ''); form.setFieldValue('wifi_plan_id', ''); }} />
        <Select label="Plan" required placeholder={form.values.mikrotik_router_id ? 'Select plan' : 'Select a router first'}
          data={planOptions} disabled={!form.values.mikrotik_router_id}
          {...form.getInputProps('wifi_plan_id')} />
        <TextInput label="Customer Phone" required placeholder="e.g. 0712345678" {...form.getInputProps('customer_phone')} />
        <TextInput label="Customer Name (optional)" {...form.getInputProps('customer_name')} />
        <Select label="Payment Method" required data={PAYMENT_METHOD_OPTIONS} {...form.getInputProps('payment_method')} />
        <Group justify="flex-end">
          <Button type="submit" loading={mutation.isPending}>Create & Send Voucher</Button>
        </Group>
      </Stack>
    </form>
  );
}
