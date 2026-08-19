import { useState } from 'react';
import { Title, Group, Button, TextInput, Modal, Pagination, Select, NumberInput, Stack, Text, Alert } from '@mantine/core';
import { useDebouncedValue } from '@mantine/hooks';
import { notifications } from '@mantine/notifications';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { IconPlus, IconSearch, IconArrowUpRight, IconCircleCheck } from '@tabler/icons-react';
import { useNavigate } from 'react-router-dom';
import { getTenants, createTenant, updateTenant, toggleTenantActive, impersonateTenant, extendTenantSubscription, getAdminSubscriptionPlans, promoteClientToTenant, Tenant, TenantFormData, CreateTenantData, PromoteClientData } from '../../api/admin';
import { useAuth } from '../../context/AuthContext';
import TenantTable from '../../components/Admin/TenantTable';
import TenantForm from '../../components/Admin/TenantForm';
import PromoteClientForm from '../../components/Admin/PromoteClientForm';

export default function Tenants() {
  const queryClient = useQueryClient();
  const navigate = useNavigate();
  const { impersonate } = useAuth();
  const [search, setSearch] = useState('');
  const [debouncedSearch] = useDebouncedValue(search, 300);
  const [page, setPage] = useState(1);
  const [modalOpen, setModalOpen] = useState(false);
  const [editing, setEditing] = useState<Tenant | null>(null);
  const [extendTarget, setExtendTarget] = useState<Tenant | null>(null);
  const [extendPlanId, setExtendPlanId] = useState<string | null>(null);
  const [extendDays, setExtendDays] = useState<number | string>(30);
  const [promoteModalOpen, setPromoteModalOpen] = useState(false);
  const [promotedTenant, setPromotedTenant] = useState<Tenant | null>(null);

  const { data } = useQuery({
    queryKey: ['admin-tenants', debouncedSearch, page],
    queryFn: () => getTenants({ search: debouncedSearch || undefined, page }),
  });

  const tenants = data?.data?.data || [];
  const meta = data?.data?.meta;

  const { data: plansData } = useQuery({
    queryKey: ['admin-subscription-plans'],
    queryFn: getAdminSubscriptionPlans,
    enabled: !!extendTarget,
  });
  const plans = (plansData?.data?.data || []).filter((p) => p.is_active);

  const createMutation = useMutation({
    mutationFn: (values: CreateTenantData) => createTenant(values),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['admin-tenants'] });
      setModalOpen(false);
      notifications.show({ title: 'Success', message: 'Tenant created', color: 'green' });
    },
    onError: (err: any) => notifications.show({
      title: 'Error',
      message: err.response?.data?.message || 'Failed to create tenant',
      color: 'red',
    }),
  });

  const updateMutation = useMutation({
    mutationFn: (values: TenantFormData) => updateTenant(editing!.id, values),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['admin-tenants'] });
      setModalOpen(false);
      setEditing(null);
      notifications.show({ title: 'Success', message: 'Tenant updated', color: 'green' });
    },
    onError: () => notifications.show({ title: 'Error', message: 'Failed to update tenant', color: 'red' }),
  });

  const toggleMutation = useMutation({
    mutationFn: (id: string) => toggleTenantActive(id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['admin-tenants'] });
      notifications.show({ title: 'Success', message: 'Tenant status updated', color: 'green' });
    },
  });

  const impersonateMutation = useMutation({
    mutationFn: (tenantId: string) => impersonateTenant(tenantId),
    onSuccess: (res) => {
      impersonate(res.data.user, res.data.token, res.data.subscription_status, res.data.days_remaining);
      navigate('/dashboard');
    },
    onError: (err: any) => notifications.show({
      title: 'Error',
      message: err.response?.data?.message || 'Failed to switch to tenant',
      color: 'red',
    }),
  });

  const extendMutation = useMutation({
    mutationFn: ({ tenantId, plan_id, days }: { tenantId: string; plan_id: string; days: number }) =>
      extendTenantSubscription(tenantId, { plan_id, days }),
    onSuccess: (res) => {
      queryClient.invalidateQueries({ queryKey: ['admin-tenants'] });
      setExtendTarget(null);
      setExtendPlanId(null);
      setExtendDays(30);
      notifications.show({ title: 'Success', message: res.data?.message || 'Subscription extended', color: 'green' });
    },
    onError: (err: any) => notifications.show({
      title: 'Error',
      message: err.response?.data?.message || 'Failed to extend subscription',
      color: 'red',
    }),
  });

  const promoteMutation = useMutation({
    mutationFn: (values: PromoteClientData) => promoteClientToTenant(values),
    onSuccess: (res) => {
      queryClient.invalidateQueries({ queryKey: ['admin-tenants'] });
      setPromoteModalOpen(false);
      setPromotedTenant(res.data.data);
      notifications.show({ title: 'Success', message: `Tenant "${res.data.data.name}" created`, color: 'green' });
    },
    onError: (err: any) => notifications.show({
      title: 'Error',
      message: err.response?.data?.message || 'Failed to promote client',
      color: 'red',
    }),
  });

  const handleExtend = (tenant: Tenant) => {
    setExtendTarget(tenant);
    setExtendPlanId(null);
    setExtendDays(30);
  };

  const handleExtendSubmit = () => {
    if (!extendTarget || !extendPlanId || !extendDays) return;
    extendMutation.mutate({ tenantId: extendTarget.id, plan_id: extendPlanId, days: Number(extendDays) });
  };

  const handleEdit = (tenant: Tenant) => {
    setEditing(tenant);
    setModalOpen(true);
  };

  const handleToggleActive = (tenant: Tenant) => {
    toggleMutation.mutate(tenant.id);
  };

  const handleImpersonate = (tenant: Tenant) => {
    impersonateMutation.mutate(tenant.id);
  };

  const handleSubmit = (values: TenantFormData | CreateTenantData) => {
    if (editing) {
      updateMutation.mutate(values as TenantFormData);
    } else {
      createMutation.mutate(values as CreateTenantData);
    }
  };

  return (
    <>
      <Group justify="space-between" mb="md" wrap="wrap">
        <Title order={2}>Tenants</Title>
        <Group gap="xs">
          <Button variant="outline" leftSection={<IconArrowUpRight size={16} />} onClick={() => setPromoteModalOpen(true)}>
            Promote from Client
          </Button>
          <Button leftSection={<IconPlus size={16} />} onClick={() => { setEditing(null); setModalOpen(true); }}>
            Add Tenant
          </Button>
        </Group>
      </Group>

      {promotedTenant && (
        <Alert color="green" icon={<IconCircleCheck size={18} />} mb="md" withCloseButton
          onClose={() => setPromotedTenant(null)} title={`Tenant "${promotedTenant.name}" created`}>
          <Group justify="space-between" align="center" wrap="wrap">
            <Text size="sm">Log in as this tenant now to finish branding and product setup?</Text>
            <Button size="xs" loading={impersonateMutation.isPending}
              onClick={() => impersonateMutation.mutate(promotedTenant.id)}>
              Log in as {promotedTenant.name}
            </Button>
          </Group>
        </Alert>
      )}

      <TextInput
        placeholder="Search tenants..."
        leftSection={<IconSearch size={16} />}
        value={search}
        onChange={(e) => { setSearch(e.currentTarget.value); setPage(1); }}
        mb="md"
        maw={300}
      />

      <TenantTable
        tenants={tenants}
        onEdit={handleEdit}
        onToggleActive={handleToggleActive}
        onImpersonate={handleImpersonate}
        onExtend={handleExtend}
      />

      {meta && meta.last_page > 1 && (
        <Group justify="center" mt="md">
          <Pagination total={meta.last_page} value={page} onChange={setPage} />
        </Group>
      )}

      <Modal
        opened={modalOpen}
        onClose={() => { setModalOpen(false); setEditing(null); }}
        title={editing ? 'Edit Tenant' : 'New Tenant'}
        size="md"
      >
        <TenantForm
          isEdit={!!editing}
          initialValues={editing ? {
            name: editing.name,
            email: editing.email,
            phone: editing.phone || '',
            address: editing.address || '',
            tax_id: editing.tax_id || '',
            currency: editing.currency,
          } : undefined}
          onSubmit={handleSubmit}
          loading={createMutation.isPending || updateMutation.isPending}
        />
      </Modal>

      <Modal
        opened={promoteModalOpen}
        onClose={() => setPromoteModalOpen(false)}
        title="Promote Client to White-Label Tenant"
        size="md"
      >
        <PromoteClientForm
          onSubmit={(values) => promoteMutation.mutate(values)}
          loading={promoteMutation.isPending}
        />
      </Modal>

      <Modal
        opened={!!extendTarget}
        onClose={() => setExtendTarget(null)}
        title={`Extend Subscription — ${extendTarget?.name || ''}`}
        size="sm"
      >
        <Stack>
          <Text size="sm" c="dimmed">
            Grant a free subscription extension. No payment required.
          </Text>
          <Select
            label="Subscription Plan"
            placeholder="Select a plan"
            data={plans.map((p) => ({ value: p.id, label: `${p.name} (${p.billing_cycle_days} days)` }))}
            value={extendPlanId}
            onChange={setExtendPlanId}
          />
          <NumberInput
            label="Days"
            min={1}
            max={365}
            value={extendDays}
            onChange={setExtendDays}
          />
          <Button
            onClick={handleExtendSubmit}
            loading={extendMutation.isPending}
            disabled={!extendPlanId || !extendDays}
          >
            Extend Subscription
          </Button>
        </Stack>
      </Modal>
    </>
  );
}
