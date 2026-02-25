import { useState } from 'react';
import { Title, Group, Button, TextInput, Modal, Pagination, Anchor, Text } from '@mantine/core';
import { useDebouncedValue } from '@mantine/hooks';
import { notifications } from '@mantine/notifications';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { IconPlus, IconSearch, IconArrowLeft } from '@tabler/icons-react';
import { useParams, Link } from 'react-router-dom';
import {
  getTenantUsers, createTenantUser, updateTenantUser, toggleTenantUserActive,
  getTenants,
} from '../../api/admin';
import { TenantUser, UserFormData } from '../../api/users';
import UserTable from '../../components/Settings/UserTable';
import UserForm from '../../components/Settings/UserForm';

export default function TenantUsers() {
  const { tenantId } = useParams<{ tenantId: string }>();
  const queryClient = useQueryClient();
  const [search, setSearch] = useState('');
  const [debouncedSearch] = useDebouncedValue(search, 300);
  const [page, setPage] = useState(1);
  const [modalOpen, setModalOpen] = useState(false);
  const [editing, setEditing] = useState<TenantUser | null>(null);

  const { data: tenantData } = useQuery({
    queryKey: ['admin-tenants'],
    queryFn: () => getTenants(),
  });
  const tenantName = tenantData?.data?.data?.find((t: { id: string }) => t.id === tenantId)?.name;

  const { data } = useQuery({
    queryKey: ['admin-tenant-users', tenantId, debouncedSearch, page],
    queryFn: () => getTenantUsers(tenantId!, { search: debouncedSearch || undefined, page }),
    enabled: !!tenantId,
  });

  const users: TenantUser[] = data?.data?.data || [];
  const meta = data?.data?.meta;

  const createMutation = useMutation({
    mutationFn: (values: UserFormData) => createTenantUser(tenantId!, values),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['admin-tenant-users', tenantId] });
      queryClient.invalidateQueries({ queryKey: ['admin-tenants'] });
      setModalOpen(false);
      notifications.show({ title: 'Success', message: 'User created', color: 'green' });
    },
    onError: (err: any) => notifications.show({
      title: 'Error',
      message: err.response?.data?.message || 'Failed to create user',
      color: 'red',
    }),
  });

  const updateMutation = useMutation({
    mutationFn: (values: UserFormData) => updateTenantUser(tenantId!, editing!.id, values),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['admin-tenant-users', tenantId] });
      setModalOpen(false);
      setEditing(null);
      notifications.show({ title: 'Success', message: 'User updated', color: 'green' });
    },
    onError: () => notifications.show({ title: 'Error', message: 'Failed to update user', color: 'red' }),
  });

  const toggleMutation = useMutation({
    mutationFn: (userId: string) => toggleTenantUserActive(tenantId!, userId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['admin-tenant-users', tenantId] });
    },
  });

  const handleEdit = (user: TenantUser) => {
    setEditing(user);
    setModalOpen(true);
  };

  const handleToggleActive = (user: TenantUser) => {
    toggleMutation.mutate(user.id);
  };

  const handleSubmit = (values: UserFormData) => {
    if (editing) {
      updateMutation.mutate(values);
    } else {
      createMutation.mutate(values);
    }
  };

  return (
    <>
      <Anchor component={Link} to="/admin/tenants" size="sm" mb="xs" style={{ display: 'inline-flex', alignItems: 'center', gap: 4 }}>
        <IconArrowLeft size={14} /> Back to Tenants
      </Anchor>

      <Group justify="space-between" mb="md" wrap="wrap">
        <Group gap="xs" wrap="wrap">
          <Title order={2}>Users</Title>
          {tenantName && <Text c="dimmed" size="lg">— {tenantName}</Text>}
        </Group>
        <Button leftSection={<IconPlus size={16} />} onClick={() => { setEditing(null); setModalOpen(true); }}>
          Add User
        </Button>
      </Group>

      <TextInput
        placeholder="Search users..."
        leftSection={<IconSearch size={16} />}
        value={search}
        onChange={(e) => { setSearch(e.currentTarget.value); setPage(1); }}
        mb="md"
        maw={300}
      />

      <UserTable
        users={users}
        isAdmin={true}
        currentUserId=""
        onEdit={handleEdit}
        onToggleActive={handleToggleActive}
      />

      {meta && meta.last_page > 1 && (
        <Group justify="center" mt="md">
          <Pagination total={meta.last_page} value={page} onChange={setPage} />
        </Group>
      )}

      <Modal
        opened={modalOpen}
        onClose={() => { setModalOpen(false); setEditing(null); }}
        title={editing ? 'Edit User' : 'New User'}
        size="md"
      >
        <UserForm
          initialValues={editing ? {
            name: editing.name,
            email: editing.email,
            password: '',
            phone: editing.phone || '',
            role: editing.role,
          } : undefined}
          onSubmit={handleSubmit}
          loading={createMutation.isPending || updateMutation.isPending}
        />
      </Modal>
    </>
  );
}
