import { useState } from 'react';
import { Title, Group, Button, TextInput, Modal, Pagination } from '@mantine/core';
import { useDebouncedValue } from '@mantine/hooks';
import { notifications } from '@mantine/notifications';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { IconPlus, IconSearch } from '@tabler/icons-react';
import { getUsers, createUser, updateUser, toggleUserActive, TenantUser, UserFormData } from '../api/users';
import { impersonateUser } from '../api/admin';
import UserTable from '../components/Settings/UserTable';
import UserForm from '../components/Settings/UserForm';
import { usePermissions } from '../hooks/usePermissions';
import { useAuth } from '../context/AuthContext';
import { useNavigate } from 'react-router-dom';

export default function Users() {
  const queryClient = useQueryClient();
  const { user: currentUser, isImpersonating, impersonate } = useAuth();
  const navigate = useNavigate();
  const { can } = usePermissions();
  const canManageUsers = can('settings.users');
  const [search, setSearch] = useState('');
  const [debouncedSearch] = useDebouncedValue(search, 300);
  const [page, setPage] = useState(1);
  const [modalOpen, setModalOpen] = useState(false);
  const [editing, setEditing] = useState<TenantUser | null>(null);

  const { data } = useQuery({
    queryKey: ['users', debouncedSearch, page],
    queryFn: () => getUsers({ search: debouncedSearch || undefined, page }),
  });

  const users = data?.data?.data || [];
  const meta = data?.data?.meta;

  const createMutation = useMutation({
    mutationFn: (values: UserFormData) => createUser(values),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['users'] });
      setModalOpen(false);
      notifications.show({ title: 'Success', message: 'User created', color: 'green' });
    },
    onError: () => notifications.show({ title: 'Error', message: 'Failed to create user', color: 'red' }),
  });

  const updateMutation = useMutation({
    mutationFn: (values: UserFormData) => updateUser(editing!.id, values),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['users'] });
      setModalOpen(false);
      setEditing(null);
      notifications.show({ title: 'Success', message: 'User updated', color: 'green' });
    },
    onError: () => notifications.show({ title: 'Error', message: 'Failed to update user', color: 'red' }),
  });

  const toggleMutation = useMutation({
    mutationFn: (id: string) => toggleUserActive(id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['users'] });
      notifications.show({ title: 'Success', message: 'User status updated', color: 'green' });
    },
  });

  const loginAsMutation = useMutation({
    mutationFn: (user: TenantUser) => impersonateUser(currentUser!.tenant!.id, user.id),
    onSuccess: (res) => {
      const { user: impUser, token, subscription_status, days_remaining } = res.data;
      impersonate(impUser, token, subscription_status, days_remaining);
      navigate('/');
      notifications.show({ title: 'Impersonating', message: `Logged in as ${impUser.name}`, color: 'violet' });
    },
    onError: () => notifications.show({ title: 'Error', message: 'Failed to login as user', color: 'red' }),
  });

  const handleLoginAs = (user: TenantUser) => {
    loginAsMutation.mutate(user);
  };

  const handleEdit = (user: TenantUser) => {
    setEditing(user);
    setModalOpen(true);
  };

  const handleToggleActive = (user: TenantUser) => {
    toggleMutation.mutate(user.id);
  };

  const handleSubmit = (values: UserFormData) => {
    // Strip empty password on edit so backend ignores it
    if (editing && !values.password) {
      const { password, ...rest } = values;
      updateMutation.mutate(rest as UserFormData);
    } else if (editing) {
      updateMutation.mutate(values);
    } else {
      createMutation.mutate(values);
    }
  };

  return (
    <>
      <Group justify="space-between" mb="md" wrap="wrap">
        <Title order={2}>Team</Title>
        {canManageUsers && (
          <Button leftSection={<IconPlus size={16} />} onClick={() => { setEditing(null); setModalOpen(true); }}>
            Add User
          </Button>
        )}
      </Group>

      <TextInput
        placeholder="Search team members..."
        leftSection={<IconSearch size={16} />}
        value={search}
        onChange={(e) => { setSearch(e.currentTarget.value); setPage(1); }}
        mb="md"
        maw={300}
      />

      <UserTable
        users={users}
        isAdmin={canManageUsers}
        currentUserId={currentUser?.id || ''}
        onEdit={handleEdit}
        onToggleActive={handleToggleActive}
        showLoginAs={isImpersonating}
        onLoginAs={handleLoginAs}
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
            phone: editing.phone || '',
            role_id: editing.role_id || '',
          } : undefined}
          onSubmit={handleSubmit}
          loading={createMutation.isPending || updateMutation.isPending}
        />
      </Modal>
    </>
  );
}
