import { useState } from 'react';
import { Title, Group, Button, TextInput, Modal, Pagination, Anchor, Text, Stack, Alert, CopyButton, ActionIcon, Tooltip } from '@mantine/core';
import { useDebouncedValue } from '@mantine/hooks';
import { notifications } from '@mantine/notifications';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { IconPlus, IconSearch, IconArrowLeft, IconCopy, IconCheck, IconAlertTriangle } from '@tabler/icons-react';
import { useParams, Link, useNavigate } from 'react-router-dom';
import {
  getTenantUsers, createTenantUser, updateTenantUser, toggleTenantUserActive,
  resetTenantUserPassword, impersonateUser, getTenants,
} from '../../api/admin';
import { TenantUser, UserFormData } from '../../api/users';
import UserTable from '../../components/Settings/UserTable';
import UserForm from '../../components/Settings/UserForm';
import { useAuth } from '../../context/AuthContext';

export default function TenantUsers() {
  const { tenantId } = useParams<{ tenantId: string }>();
  const navigate = useNavigate();
  const { impersonate } = useAuth();
  const queryClient = useQueryClient();
  const [search, setSearch] = useState('');
  const [debouncedSearch] = useDebouncedValue(search, 300);
  const [page, setPage] = useState(1);
  const [modalOpen, setModalOpen] = useState(false);
  const [editing, setEditing] = useState<TenantUser | null>(null);
  const [revealed, setRevealed] = useState<{ user: TenantUser; password: string; emailSent: boolean } | null>(null);

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

  const resetPasswordMutation = useMutation({
    mutationFn: (user: TenantUser) => resetTenantUserPassword(tenantId!, user.id).then((res) => ({ user, res })),
    onSuccess: ({ user, res }) => {
      setRevealed({ user, password: res.data.password, emailSent: res.data.email_sent });
    },
    onError: (err: any) => notifications.show({
      title: 'Error',
      message: err.response?.data?.message || 'Failed to reset password',
      color: 'red',
    }),
  });

  const loginAsMutation = useMutation({
    mutationFn: async (user: TenantUser) => {
      const res = await impersonateUser(tenantId!, user.id);
      const { user: impUser, token, subscription_status, days_remaining } = res.data;
      await impersonate(impUser, token, subscription_status, days_remaining);
      return impUser;
    },
    onSuccess: (impUser) => {
      navigate('/dashboard');
      notifications.show({ title: 'Impersonating', message: `Logged in as ${impUser.name}`, color: 'violet' });
    },
    onError: (err: any) => notifications.show({
      title: 'Error',
      message: err.response?.data?.message || 'Failed to login as user',
      color: 'red',
    }),
  });

  const handleEdit = (user: TenantUser) => {
    setEditing(user);
    setModalOpen(true);
  };

  const handleToggleActive = (user: TenantUser) => {
    toggleMutation.mutate(user.id);
  };

  const handleResetPassword = (user: TenantUser) => {
    if (window.confirm(`Reset ${user.name}'s password? You'll get the new password to copy, and we'll also try emailing it to them.`)) {
      resetPasswordMutation.mutate(user);
    }
  };

  const handleLoginAs = (user: TenantUser) => {
    loginAsMutation.mutate(user);
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
        onResetPassword={handleResetPassword}
        resetPasswordLoadingId={resetPasswordMutation.isPending ? resetPasswordMutation.variables?.id : undefined}
        showLoginAs
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
            password: '',
            phone: editing.phone || '',
            role_id: editing.role_id || '',
          } : undefined}
          onSubmit={handleSubmit}
          loading={createMutation.isPending || updateMutation.isPending}
        />
      </Modal>

      <Modal opened={!!revealed} onClose={() => setRevealed(null)} title="New password" size="sm">
        {revealed && (
          <Stack gap="sm">
            <Text size="sm">
              New password for <b>{revealed.user.name}</b> ({revealed.user.email}):
            </Text>
            <TextInput
              value={revealed.password}
              readOnly
              styles={{ input: { fontFamily: 'monospace', fontWeight: 600 } }}
              rightSection={
                <CopyButton value={revealed.password} timeout={1500}>
                  {({ copied, copy }) => (
                    <Tooltip label={copied ? 'Copied' : 'Copy'}>
                      <ActionIcon color={copied ? 'teal' : 'gray'} variant="subtle" onClick={copy}>
                        {copied ? <IconCheck size={16} /> : <IconCopy size={16} />}
                      </ActionIcon>
                    </Tooltip>
                  )}
                </CopyButton>
              }
            />
            {revealed.emailSent ? (
              <Text size="xs" c="dimmed">Also emailed to {revealed.user.email} — in case it doesn't arrive, copy it above and send it manually.</Text>
            ) : (
              <Alert color="orange" variant="light" icon={<IconAlertTriangle size={16} />} p="xs">
                {revealed.user.email
                  ? "Couldn't send the email — copy the password above and send it manually."
                  : 'This user has no email on file — copy the password above and send it manually.'}
              </Alert>
            )}
          </Stack>
        )}
      </Modal>
    </>
  );
}
