import { useState } from 'react';
import { Title, Group, Button, TextInput, Modal, Pagination } from '@mantine/core';
import { useDebouncedValue } from '@mantine/hooks';
import { notifications } from '@mantine/notifications';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { IconPlus, IconSearch } from '@tabler/icons-react';
import { useNavigate } from 'react-router-dom';
import { getTenants, createTenant, updateTenant, toggleTenantActive, impersonateTenant, Tenant, TenantFormData, CreateTenantData } from '../../api/admin';
import { useAuth } from '../../context/AuthContext';
import TenantTable from '../../components/Admin/TenantTable';
import TenantForm from '../../components/Admin/TenantForm';

export default function Tenants() {
  const queryClient = useQueryClient();
  const navigate = useNavigate();
  const { impersonate } = useAuth();
  const [search, setSearch] = useState('');
  const [debouncedSearch] = useDebouncedValue(search, 300);
  const [page, setPage] = useState(1);
  const [modalOpen, setModalOpen] = useState(false);
  const [editing, setEditing] = useState<Tenant | null>(null);

  const { data } = useQuery({
    queryKey: ['admin-tenants', debouncedSearch, page],
    queryFn: () => getTenants({ search: debouncedSearch || undefined, page }),
  });

  const tenants = data?.data?.data || [];
  const meta = data?.data?.meta;

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
      impersonate(res.data.user, res.data.token);
      navigate('/dashboard');
    },
    onError: (err: any) => notifications.show({
      title: 'Error',
      message: err.response?.data?.message || 'Failed to switch to tenant',
      color: 'red',
    }),
  });

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
      <Group justify="space-between" mb="md">
        <Title order={2}>Tenants</Title>
        <Button leftSection={<IconPlus size={16} />} onClick={() => { setEditing(null); setModalOpen(true); }}>
          Add Tenant
        </Button>
      </Group>

      <TextInput
        placeholder="Search tenants..."
        leftSection={<IconSearch size={16} />}
        value={search}
        onChange={(e) => { setSearch(e.currentTarget.value); setPage(1); }}
        mb="md"
        w={300}
      />

      <TenantTable
        tenants={tenants}
        onEdit={handleEdit}
        onToggleActive={handleToggleActive}
        onImpersonate={handleImpersonate}
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
    </>
  );
}
