import { useState } from 'react';
import {
  Title, Paper, Group, Text, Badge, Stack, Table, Button, NumberInput, Select,
  Loader, Center, Tabs, Pagination, Card, SimpleGrid, Anchor, TextInput, Tooltip,
} from '@mantine/core';
import { notifications } from '@mantine/notifications';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useParams, useNavigate } from 'react-router-dom';
import {
  IconArrowLeft, IconCalendar, IconMessage, IconCreditCard,
  IconCheck, IconPhoto, IconShieldLock,
} from '@tabler/icons-react';
import {
  getTenant, getTenantSubscriptions, getAdminSmsPurchases, extendTenantSubscription,
  getAdminSubscriptionPlans, confirmSubscriptionPayment,
  Tenant, TenantSubscription, SmsPurchase, SubscriptionPlanAdmin,
} from '../../api/admin';
import {
  getAllPermissions, getTenantPermissions, updateTenantPermissions,
} from '../../api/permissions';
import type { GroupedPermissions, Permission } from '../../api/roles';

const subscriptionStatusColors: Record<string, string> = {
  trial: 'blue',
  subscribed: 'green',
  expired: 'red',
  deactivated: 'gray',
};

export default function TenantProfile() {
  const { tenantId } = useParams<{ tenantId: string }>();
  const navigate = useNavigate();
  const queryClient = useQueryClient();

  const { data: tenantData, isLoading: tenantLoading } = useQuery({
    queryKey: ['admin-tenant', tenantId],
    queryFn: () => getTenant(tenantId!),
    enabled: !!tenantId,
  });

  const tenant: Tenant | undefined = tenantData?.data?.data;

  if (tenantLoading) {
    return <Center py="xl"><Loader /></Center>;
  }

  if (!tenant) {
    return <Text c="dimmed" ta="center" py="xl">Tenant not found</Text>;
  }

  return (
    <>
      <Group mb="md">
        <Anchor c="dimmed" onClick={() => navigate('/admin/tenants')} style={{ cursor: 'pointer' }}>
          <Group gap={4}>
            <IconArrowLeft size={16} />
            <Text size="sm">Back to Tenants</Text>
          </Group>
        </Anchor>
      </Group>

      <Title order={2} mb="lg">{tenant.name}</Title>

      <SimpleGrid cols={{ base: 1, md: 2 }} mb="lg">
        <TenantInfoCard tenant={tenant} />
        <SubscriptionCard tenant={tenant} queryClient={queryClient} />
      </SimpleGrid>

      <Tabs defaultValue="subscriptions">
        <Tabs.List mb="md">
          <Tabs.Tab value="subscriptions" leftSection={<IconCreditCard size={16} />}>
            Subscription History
          </Tabs.Tab>
          <Tabs.Tab value="sms" leftSection={<IconMessage size={16} />}>
            SMS Purchase History
          </Tabs.Tab>
          <Tabs.Tab value="permissions" leftSection={<IconShieldLock size={16} />}>
            Permissions
          </Tabs.Tab>
        </Tabs.List>

        <Tabs.Panel value="subscriptions">
          <SubscriptionHistoryTab tenantId={tenant.id} />
        </Tabs.Panel>
        <Tabs.Panel value="sms">
          <SmsPurchaseHistoryTab tenantId={tenant.id} />
        </Tabs.Panel>
        <Tabs.Panel value="permissions">
          <TenantPermissionsTab tenantId={tenant.id} />
        </Tabs.Panel>
      </Tabs>
    </>
  );
}

function TenantInfoCard({ tenant }: { tenant: Tenant }) {
  return (
    <Card withBorder p="lg">
      <Text fw={600} size="lg" mb="sm">Company Details</Text>
      <Stack gap="xs">
        <Group justify="space-between">
          <Text c="dimmed" size="sm">Email</Text>
          <Text size="sm">{tenant.email}</Text>
        </Group>
        <Group justify="space-between">
          <Text c="dimmed" size="sm">Phone</Text>
          <Text size="sm">{tenant.phone || '—'}</Text>
        </Group>
        <Group justify="space-between">
          <Text c="dimmed" size="sm">Currency</Text>
          <Text size="sm">{tenant.currency}</Text>
        </Group>
        <Group justify="space-between">
          <Text c="dimmed" size="sm">Tax ID</Text>
          <Text size="sm">{tenant.tax_id || '—'}</Text>
        </Group>
        <Group justify="space-between">
          <Text c="dimmed" size="sm">Users</Text>
          <Text size="sm">{tenant.users_count}</Text>
        </Group>
        <Group justify="space-between">
          <Text c="dimmed" size="sm">Status</Text>
          <Badge color={tenant.is_active ? 'green' : 'red'} variant="light">
            {tenant.is_active ? 'Active' : 'Inactive'}
          </Badge>
        </Group>
        <Group justify="space-between">
          <Text c="dimmed" size="sm">Created</Text>
          <Text size="sm">{new Date(tenant.created_at).toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric' })}</Text>
        </Group>
      </Stack>
    </Card>
  );
}

function SubscriptionCard({ tenant, queryClient }: { tenant: Tenant; queryClient: ReturnType<typeof useQueryClient> }) {
  const [days, setDays] = useState<number | string>(30);
  const [planId, setPlanId] = useState<string | null>(null);

  const { data: plansData } = useQuery({
    queryKey: ['admin-subscription-plans'],
    queryFn: getAdminSubscriptionPlans,
  });

  const plans: SubscriptionPlanAdmin[] = plansData?.data?.data || [];
  const planOptions = plans.filter(p => p.is_active).map(p => ({ value: p.id, label: `${p.name} (${p.price} / ${p.billing_cycle_days}d)` }));

  const extendMutation = useMutation({
    mutationFn: () => extendTenantSubscription(tenant.id, { plan_id: planId!, days: Number(days) }),
    onSuccess: (res) => {
      queryClient.invalidateQueries({ queryKey: ['admin-tenant', tenant.id] });
      queryClient.invalidateQueries({ queryKey: ['admin-tenant-subscriptions', tenant.id] });
      notifications.show({ title: 'Success', message: res.data.message, color: 'green' });
    },
    onError: (err: any) => {
      notifications.show({
        title: 'Error',
        message: err.response?.data?.message || 'Failed to extend subscription',
        color: 'red',
      });
    },
  });

  const expiresDate = tenant.expires_at
    ? new Date(tenant.expires_at).toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric' })
    : '—';

  const daysRemaining = tenant.days_remaining ?? 0;
  const daysColor = daysRemaining <= 0 ? 'red' : daysRemaining <= 7 ? 'orange' : 'green';

  return (
    <Card withBorder p="lg">
      <Text fw={600} size="lg" mb="sm">Subscription</Text>
      <Stack gap="xs">
        <Group justify="space-between">
          <Text c="dimmed" size="sm">Status</Text>
          <Badge color={subscriptionStatusColors[tenant.subscription_status || 'expired']} variant="light" size="lg">
            {tenant.subscription_status === 'trial' ? 'Trial' :
             tenant.subscription_status === 'subscribed' ? 'Subscribed' :
             tenant.subscription_status === 'expired' ? 'Expired' : 'Deactivated'}
          </Badge>
        </Group>
        <Group justify="space-between">
          <Text c="dimmed" size="sm">Expires</Text>
          <Text size="sm" fw={500}>{expiresDate}</Text>
        </Group>
        <Group justify="space-between">
          <Text c="dimmed" size="sm">Days Remaining</Text>
          <Badge color={daysColor} variant="light" size="lg">{daysRemaining} days</Badge>
        </Group>

        <Text fw={500} size="sm" mt="md" mb={4}>Extend Subscription</Text>
        <Select
          placeholder="Select plan"
          data={planOptions}
          value={planId}
          onChange={setPlanId}
          size="sm"
        />
        <Group>
          <NumberInput
            placeholder="Days"
            min={1}
            max={365}
            value={days}
            onChange={setDays}
            size="sm"
            style={{ flex: 1 }}
            leftSection={<IconCalendar size={14} />}
          />
          <Button
            size="sm"
            disabled={!planId || !days}
            loading={extendMutation.isPending}
            onClick={() => extendMutation.mutate()}
          >
            Extend
          </Button>
        </Group>
      </Stack>
    </Card>
  );
}

function SubscriptionHistoryTab({ tenantId }: { tenantId: string }) {
  const [page, setPage] = useState(1);
  const [confirmingId, setConfirmingId] = useState<string | null>(null);
  const [paymentRef, setPaymentRef] = useState('');
  const queryClient = useQueryClient();

  const { data, isLoading } = useQuery({
    queryKey: ['admin-tenant-subscriptions', tenantId, page],
    queryFn: () => getTenantSubscriptions(tenantId, { page }),
  });

  const confirmMutation = useMutation({
    mutationFn: (subId: string) => confirmSubscriptionPayment(subId, paymentRef || undefined),
    onSuccess: (res) => {
      queryClient.invalidateQueries({ queryKey: ['admin-tenant-subscriptions', tenantId] });
      queryClient.invalidateQueries({ queryKey: ['admin-tenant', tenantId] });
      notifications.show({ title: 'Success', message: res.data.message, color: 'green' });
      setConfirmingId(null);
      setPaymentRef('');
    },
    onError: (err: any) => {
      notifications.show({
        title: 'Error',
        message: err.response?.data?.message || 'Failed to confirm payment',
        color: 'red',
      });
    },
  });

  const subscriptions: TenantSubscription[] = data?.data?.data || [];
  const meta = data?.data?.meta;

  if (isLoading) return <Center py="xl"><Loader /></Center>;

  if (subscriptions.length === 0) {
    return <Text c="dimmed" ta="center" py="xl">No subscription history</Text>;
  }

  return (
    <Paper withBorder>
      <Table.ScrollContainer minWidth={900}>
        <Table striped highlightOnHover>
          <Table.Thead>
            <Table.Tr>
              <Table.Th>Plan</Table.Th>
              <Table.Th>Invoice</Table.Th>
              <Table.Th>Status</Table.Th>
              <Table.Th>Method</Table.Th>
              <Table.Th>Starts</Table.Th>
              <Table.Th>Ends</Table.Th>
              <Table.Th>Amount</Table.Th>
              <Table.Th>By</Table.Th>
              <Table.Th>Actions</Table.Th>
            </Table.Tr>
          </Table.Thead>
        <Table.Tbody>
          {subscriptions.map((sub) => {
            const isPendingBankTransfer = sub.status === 'pending' && sub.payment_method === 'bank_transfer';
            const isConfirming = confirmingId === sub.id;

            return (
              <Table.Tr key={sub.id}>
                <Table.Td>{sub.plan?.name || '—'}</Table.Td>
                <Table.Td>
                  <Text size="xs" ff="monospace">{sub.invoice_number || '—'}</Text>
                </Table.Td>
                <Table.Td>
                  <Badge
                    color={
                      sub.status === 'active' && new Date(sub.ends_at) > new Date() ? 'green' :
                      sub.status === 'active' ? 'orange' :
                      sub.status === 'pending' ? 'yellow' : 'gray'
                    }
                    variant="light"
                    size="sm"
                  >
                    {sub.status === 'active' && new Date(sub.ends_at) > new Date() ? 'Active' :
                     sub.status === 'active' ? 'Ended' :
                     sub.status === 'pending' ? 'Pending' : sub.status}
                  </Badge>
                </Table.Td>
                <Table.Td>
                  <Text size="xs">
                    {sub.payment_method === 'bank_transfer' ? 'Bank Transfer' :
                     sub.payment_method === 'pesapal' ? 'Pesapal' :
                     sub.payment_method_used || '—'}
                  </Text>
                </Table.Td>
                <Table.Td>
                  {sub.starts_at
                    ? new Date(sub.starts_at).toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric' })
                    : '—'}
                </Table.Td>
                <Table.Td>
                  {sub.ends_at
                    ? new Date(sub.ends_at).toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric' })
                    : '—'}
                </Table.Td>
                <Table.Td>{Number(sub.amount_paid) > 0 ? `TZS ${Number(sub.amount_paid).toLocaleString()}` : 'Free'}</Table.Td>
                <Table.Td>
                  <Text size="xs">{sub.user?.name || '—'}</Text>
                </Table.Td>
                <Table.Td>
                  {isPendingBankTransfer && !isConfirming && (
                    <Group gap="xs">
                      <Button
                        size="compact-xs"
                        color="green"
                        leftSection={<IconCheck size={14} />}
                        onClick={() => setConfirmingId(sub.id)}
                      >
                        Confirm
                      </Button>
                      {sub.payment_proof_path && (
                        <Tooltip label="Has payment proof">
                          <IconPhoto size={16} color="var(--mantine-color-blue-6)" />
                        </Tooltip>
                      )}
                    </Group>
                  )}
                  {isConfirming && (
                    <Group gap="xs">
                      <TextInput
                        size="xs"
                        placeholder="Bank ref (optional)"
                        value={paymentRef}
                        onChange={(e) => setPaymentRef(e.currentTarget.value)}
                        style={{ width: 140 }}
                      />
                      <Button
                        size="compact-xs"
                        color="green"
                        loading={confirmMutation.isPending}
                        onClick={() => confirmMutation.mutate(sub.id)}
                      >
                        Activate
                      </Button>
                      <Button
                        size="compact-xs"
                        variant="subtle"
                        color="gray"
                        onClick={() => { setConfirmingId(null); setPaymentRef(''); }}
                      >
                        Cancel
                      </Button>
                    </Group>
                  )}
                  {sub.invoice_number && !isPendingBankTransfer && !isConfirming && (
                    <Text size="xs" ff="monospace" c="dimmed">
                      {sub.payment_confirmed_at ? 'Confirmed' : ''}
                    </Text>
                  )}
                </Table.Td>
              </Table.Tr>
            );
          })}
        </Table.Tbody>
        </Table>
      </Table.ScrollContainer>
      {meta && meta.last_page > 1 && (
        <Group justify="center" p="md">
          <Pagination total={meta.last_page} value={page} onChange={setPage} />
        </Group>
      )}
    </Paper>
  );
}

function SmsPurchaseHistoryTab({ tenantId }: { tenantId: string }) {
  const [page, setPage] = useState(1);

  const { data, isLoading } = useQuery({
    queryKey: ['admin-tenant-sms-purchases', tenantId, page],
    queryFn: () => getAdminSmsPurchases({ tenant_id: tenantId, page }),
  });

  const purchases: SmsPurchase[] = data?.data?.data || [];
  const meta = data?.data?.meta;

  const statusColors: Record<string, string> = {
    pending: 'yellow',
    completed: 'green',
    failed: 'red',
  };

  if (isLoading) return <Center py="xl"><Loader /></Center>;

  if (purchases.length === 0) {
    return <Text c="dimmed" ta="center" py="xl">No SMS purchase history</Text>;
  }

  return (
    <Paper withBorder>
      <Table.ScrollContainer minWidth={700}>
        <Table striped highlightOnHover>
          <Table.Thead>
            <Table.Tr>
              <Table.Th>Package</Table.Th>
              <Table.Th>Quantity</Table.Th>
              <Table.Th>Amount</Table.Th>
              <Table.Th>Status</Table.Th>
              <Table.Th>Payment Method</Table.Th>
              <Table.Th>By</Table.Th>
              <Table.Th>Date</Table.Th>
            </Table.Tr>
          </Table.Thead>
          <Table.Tbody>
            {purchases.map((purchase) => (
              <Table.Tr key={purchase.id}>
                <Table.Td>{purchase.package_name}</Table.Td>
                <Table.Td>{purchase.sms_quantity.toLocaleString()}</Table.Td>
                <Table.Td>TZS {Number(purchase.total_amount).toLocaleString()}</Table.Td>
                <Table.Td>
                  <Badge color={statusColors[purchase.status] || 'gray'} variant="light" size="sm">
                    {purchase.status}
                  </Badge>
                </Table.Td>
                <Table.Td>{purchase.payment_method_used || '—'}</Table.Td>
                <Table.Td>
                  <Text size="xs">{purchase.user?.name || '—'}</Text>
                </Table.Td>
                <Table.Td>{new Date(purchase.created_at).toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric' })}</Table.Td>
              </Table.Tr>
            ))}
          </Table.Tbody>
        </Table>
      </Table.ScrollContainer>
      {meta && meta.last_page > 1 && (
        <Group justify="center" p="md">
          <Pagination total={meta.last_page} value={page} onChange={setPage} />
        </Group>
      )}
    </Paper>
  );
}

function TenantPermissionsTab({ tenantId }: { tenantId: string }) {
  const queryClient = useQueryClient();
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [initialized, setInitialized] = useState(false);

  const { data: allPermsData, isLoading: permsLoading } = useQuery({
    queryKey: ['admin-all-permissions'],
    queryFn: () => getAllPermissions(),
  });

  const { data: tenantPermsData, isLoading: tenantPermsLoading } = useQuery({
    queryKey: ['admin-tenant-permissions', tenantId],
    queryFn: () => getTenantPermissions(tenantId),
  });

  const groupedPermissions: GroupedPermissions = allPermsData?.data?.data || {};
  const enabledIds: string[] = tenantPermsData?.data?.data || [];

  if (enabledIds.length > 0 && !initialized) {
    setSelected(new Set(enabledIds));
    setInitialized(true);
  }

  const saveMutation = useMutation({
    mutationFn: () => updateTenantPermissions(tenantId, Array.from(selected)),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['admin-tenant-permissions', tenantId] });
      notifications.show({ title: 'Success', message: 'Tenant permissions updated', color: 'green' });
    },
    onError: (err: any) => {
      notifications.show({
        title: 'Error',
        message: err?.response?.data?.message || 'Failed to update permissions',
        color: 'red',
      });
    },
  });

  const togglePerm = (id: string) => {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  };

  const toggleAll = (perms: Permission[]) => {
    const ids = perms.map((p) => p.id);
    const allOn = ids.every((id) => selected.has(id));
    setSelected((prev) => {
      const next = new Set(prev);
      ids.forEach((id) => allOn ? next.delete(id) : next.add(id));
      return next;
    });
  };

  const selectAll = () => {
    const all = Object.values(groupedPermissions).flatMap((groups) =>
      Object.values(groups).flat()
    );
    setSelected(new Set(all.map((p: Permission) => p.id)));
  };

  const deselectAll = () => setSelected(new Set());

  if (permsLoading || tenantPermsLoading) return <Center py="xl"><Loader /></Center>;

  const totalPerms = Object.values(groupedPermissions).flatMap((g) => Object.values(g).flat()).length;

  const categoryLabels: Record<string, string> = {
    menu: 'Menu Access',
    crud: 'Data Operations',
    settings: 'Settings',
    reports: 'Reports',
  };

  return (
    <Paper p="lg" withBorder>
      <Group justify="space-between" mb="md">
        <Text fw={600}>
          Enabled: {selected.size} / {totalPerms}
        </Text>
        <Group gap="xs">
          <Button variant="subtle" size="xs" onClick={selectAll}>Select All</Button>
          <Button variant="subtle" size="xs" color="gray" onClick={deselectAll}>Deselect All</Button>
          <Button size="sm" loading={saveMutation.isPending} onClick={() => saveMutation.mutate()}>
            Save Permissions
          </Button>
        </Group>
      </Group>

      {Object.entries(groupedPermissions).map(([category, groups]) => (
        <div key={category} style={{ marginBottom: 16 }}>
          <Text fw={600} size="sm" mb="xs" tt="uppercase" c="dimmed">
            {categoryLabels[category] || category}
          </Text>
          {Object.entries(groups).map(([groupName, perms]: [string, Permission[]]) => {
            const ids = perms.map((p) => p.id);
            const allOn = ids.every((id) => selected.has(id));
            const someOn = ids.some((id) => selected.has(id));

            return (
              <Paper key={groupName} withBorder p="xs" mb="xs">
                <Group gap="xs" mb="xs">
                  <input
                    type="checkbox"
                    checked={allOn}
                    ref={(el) => { if (el) el.indeterminate = someOn && !allOn; }}
                    onChange={() => toggleAll(perms)}
                  />
                  <Text fw={500} size="sm">{groupName}</Text>
                  <Badge size="xs" variant="light">{ids.filter((id) => selected.has(id)).length}/{ids.length}</Badge>
                </Group>
                <Group gap="xs" ml="lg">
                  {perms.map((perm) => (
                    <Badge
                      key={perm.id}
                      variant={selected.has(perm.id) ? 'filled' : 'outline'}
                      color={selected.has(perm.id) ? 'blue' : 'gray'}
                      style={{ cursor: 'pointer' }}
                      onClick={() => togglePerm(perm.id)}
                      size="sm"
                    >
                      {perm.label}
                    </Badge>
                  ))}
                </Group>
              </Paper>
            );
          })}
        </div>
      ))}
    </Paper>
  );
}
