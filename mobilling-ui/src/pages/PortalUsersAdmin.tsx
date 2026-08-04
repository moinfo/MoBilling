import { useState } from 'react';
import {
  Stack, Paper, Title, Text, Group, Badge, Table, TextInput, Select,
  Switch, ActionIcon, Center, Loader, Pagination, Tooltip, Modal, Button,
} from '@mantine/core';
import { useDebouncedValue } from '@mantine/hooks';
import { useForm } from '@mantine/form';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { notifications } from '@mantine/notifications';
import { modals } from '@mantine/modals';
import { useNavigate } from 'react-router-dom';
import {
  IconShieldLock, IconSearch, IconTrash, IconLogin, IconKey, IconExternalLink, IconEdit,
} from '@tabler/icons-react';
import {
  getAllPortalUsers, updateClientPortalUser, deleteClientPortalUser,
  portalLoginAsClient, changePortalPassword, PortalUserRow,
} from '../api/clients';
import { formatDate } from '../utils/formatDate';
import { usePermissions } from '../hooks/usePermissions';
import { useAuth } from '../context/AuthContext';

/**
 * Tenant-wide directory of client portal logins — every ClientUser across
 * every client, one searchable table. Per-client CRUD (add/edit a specific
 * client's portal user) still lives on the Client Profile page; this page is
 * for finding and acting on a login when you don't already know which client
 * it belongs to, or auditing who has portal access at all.
 */
export default function PortalUsersAdmin() {
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const { can } = usePermissions();
  const { impersonateClient } = useAuth();

  const [search, setSearch] = useState('');
  const [debouncedSearch] = useDebouncedValue(search, 300);
  const [role, setRole] = useState<string | null>(null);
  const [active, setActive] = useState<string | null>(null);
  const [page, setPage] = useState(1);
  const [perPage, setPerPage] = useState('25');
  const [editing, setEditing] = useState<PortalUserRow | null>(null);

  const { data, isLoading } = useQuery({
    queryKey: ['all-portal-users', debouncedSearch, role, active, page, perPage],
    queryFn: () => getAllPortalUsers({
      search: debouncedSearch || undefined,
      role: role || undefined,
      is_active: active === '' ? undefined : active === '1' ? 1 : active === '0' ? 0 : undefined,
      page,
      per_page: Number(perPage),
    }),
  });

  const result = data?.data?.data;
  const users = result?.data ?? [];

  const invalidate = () => queryClient.invalidateQueries({ queryKey: ['all-portal-users'] });

  const toggleActiveMut = useMutation({
    mutationFn: ({ u }: { u: PortalUserRow }) => updateClientPortalUser(u.client.id, u.id, { is_active: !u.is_active }),
    onSuccess: invalidate,
    onError: (e: any) => notifications.show({ message: e?.response?.data?.message ?? 'Could not update.', color: 'red' }),
  });

  const editForm = useForm({
    initialValues: { name: '', phone: '', role: 'viewer' },
    validate: { name: (v) => (v.trim().length > 0 ? null : 'Required') },
  });

  const openEdit = (u: PortalUserRow) => {
    setEditing(u);
    editForm.setValues({ name: u.name, phone: u.phone ?? '', role: u.role });
  };
  const closeEdit = () => {
    setEditing(null);
    editForm.reset();
  };

  const editMut = useMutation({
    mutationFn: (data: { name: string; phone: string; role: string }) =>
      updateClientPortalUser(editing!.client.id, editing!.id, data as Partial<PortalUserRow>),
    onSuccess: () => {
      notifications.show({ message: 'Portal user updated.', color: 'green' });
      invalidate();
      closeEdit();
    },
    onError: (e: any) => notifications.show({ message: e?.response?.data?.message ?? 'Could not update.', color: 'red' }),
  });

  const deleteMut = useMutation({
    mutationFn: (u: PortalUserRow) => deleteClientPortalUser(u.client.id, u.id),
    onSuccess: () => {
      notifications.show({ message: 'Portal user deleted.', color: 'green' });
      invalidate();
    },
    onError: (e: any) => notifications.show({ message: e?.response?.data?.message ?? 'Could not delete.', color: 'red' }),
  });

  const loginAs = async (u: PortalUserRow) => {
    try {
      const res = await portalLoginAsClient(u.client.id);
      const { token, user, user_type, permissions } = res.data;
      impersonateClient({ ...user, user_type }, token, permissions);
      window.location.href = '/portal/dashboard';
    } catch (e: any) {
      notifications.show({ message: e?.response?.data?.message ?? 'Could not log in as this client.', color: 'red' });
    }
  };

  const resetPassword = (u: PortalUserRow) => {
    modals.openConfirmModal({
      title: 'Reset Password',
      children: <Text size="sm">Set a new password for {u.name} ({u.email})? A new random password will be generated and shown once.</Text>,
      labels: { confirm: 'Reset', cancel: 'Cancel' },
      onConfirm: async () => {
        const newPassword = 'Pw-' + Math.random().toString(36).slice(2, 10);
        try {
          await changePortalPassword(u.client.id, newPassword, u.id);
          modals.open({
            title: 'New Password',
            children: <Stack gap="xs">
              <Text size="sm">Share this with {u.name} — it will not be shown again.</Text>
              <Text ff="monospace" fw={700} size="lg">{newPassword}</Text>
            </Stack>,
          });
        } catch (e: any) {
          notifications.show({ message: e?.response?.data?.message ?? 'Could not reset the password.', color: 'red' });
        }
      },
    });
  };

  const confirmDelete = (u: PortalUserRow) => {
    modals.openConfirmModal({
      title: 'Delete Portal User',
      children: <Text size="sm">Delete {u.name} ({u.email}) — access to {u.client.name}'s portal will be removed?</Text>,
      labels: { confirm: 'Delete', cancel: 'Cancel' },
      confirmProps: { color: 'red' },
      onConfirm: () => deleteMut.mutate(u),
    });
  };

  return (
    <Stack gap="md">
      <Group justify="space-between">
        <Title order={3}>
          <Group gap="xs"><IconShieldLock size={22} /> Portal Users</Group>
        </Title>
        {result && <Text size="sm" c="dimmed">{result.total} portal login{result.total === 1 ? '' : 's'}</Text>}
      </Group>

      <Paper withBorder p="sm" radius="sm">
        <Group gap="sm" wrap="wrap">
          <TextInput
            placeholder="Search by name, email, or client…" leftSection={<IconSearch size={14} />}
            value={search} onChange={(e) => { setSearch(e.currentTarget.value); setPage(1); }}
            style={{ flex: 1, minWidth: 240 }}
          />
          <Select placeholder="Role" clearable w={140} value={role}
            onChange={(v) => { setRole(v); setPage(1); }}
            data={[{ value: 'admin', label: 'Admin' }, { value: 'viewer', label: 'Viewer' }]} />
          <Select placeholder="Status" clearable w={140} value={active}
            onChange={(v) => { setActive(v); setPage(1); }}
            data={[{ value: '1', label: 'Active' }, { value: '0', label: 'Inactive' }]} />
          <Select w={110} value={perPage}
            onChange={(v) => { setPerPage(v ?? '25'); setPage(1); }}
            data={[{ value: '25', label: '25 / page' }, { value: '50', label: '50 / page' }, { value: '100', label: '100 / page' }]} />
        </Group>
      </Paper>

      <Paper withBorder radius="sm">
        {isLoading ? (
          <Center py="xl"><Loader /></Center>
        ) : users.length === 0 ? (
          <Center py="xl"><Text c="dimmed">No portal users found.</Text></Center>
        ) : (
          <Table.ScrollContainer minWidth={780}>
            <Table striped highlightOnHover verticalSpacing="xs">
              <Table.Thead>
                <Table.Tr>
                  <Table.Th w={48}>#</Table.Th>
                  <Table.Th>Name</Table.Th>
                  <Table.Th>Email</Table.Th>
                  <Table.Th>Client</Table.Th>
                  <Table.Th>Role</Table.Th>
                  <Table.Th>Status</Table.Th>
                  <Table.Th>Last Login</Table.Th>
                  <Table.Th>Actions</Table.Th>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {users.map((u, i) => (
                  <Table.Tr key={u.id}>
                    <Table.Td c="dimmed" fz="sm">{(page - 1) * Number(perPage) + i + 1}</Table.Td>
                    <Table.Td fw={500}>{u.name}</Table.Td>
                    <Table.Td>{u.email}</Table.Td>
                    <Table.Td>
                      <Group gap={4} wrap="nowrap">
                        <Text size="sm">{u.client.name}</Text>
                        <ActionIcon variant="subtle" size="xs" onClick={() => navigate(`/clients/${u.client.id}`)}>
                          <IconExternalLink size={12} />
                        </ActionIcon>
                      </Group>
                    </Table.Td>
                    <Table.Td>
                      <Badge color={u.role === 'admin' ? 'blue' : 'gray'} variant="light" size="sm">{u.role}</Badge>
                    </Table.Td>
                    <Table.Td>
                      <Switch checked={u.is_active} size="xs" label={u.is_active ? 'Active' : 'Inactive'}
                        disabled={!can('clients.update')}
                        onChange={() => toggleActiveMut.mutate({ u })} />
                    </Table.Td>
                    <Table.Td c="dimmed" fz="sm">{u.last_login_at ? formatDate(u.last_login_at) : 'Never'}</Table.Td>
                    <Table.Td>
                      <Group gap={4} wrap="nowrap">
                        {can('clients.portal_login') && (
                          <Tooltip label="Login as this client">
                            <ActionIcon variant="subtle" size="sm" onClick={() => loginAs(u)}>
                              <IconLogin size={14} />
                            </ActionIcon>
                          </Tooltip>
                        )}
                        {can('clients.portal_password') && (
                          <Tooltip label="Reset password">
                            <ActionIcon variant="subtle" size="sm" onClick={() => resetPassword(u)}>
                              <IconKey size={14} />
                            </ActionIcon>
                          </Tooltip>
                        )}
                        {can('clients.update') && (
                          <Tooltip label="Edit">
                            <ActionIcon variant="subtle" size="sm" onClick={() => openEdit(u)}>
                              <IconEdit size={14} />
                            </ActionIcon>
                          </Tooltip>
                        )}
                        {can('clients.update') && (
                          <Tooltip label="Delete">
                            <ActionIcon variant="subtle" size="sm" color="red" onClick={() => confirmDelete(u)}>
                              <IconTrash size={14} />
                            </ActionIcon>
                          </Tooltip>
                        )}
                      </Group>
                    </Table.Td>
                  </Table.Tr>
                ))}
              </Table.Tbody>
            </Table>
          </Table.ScrollContainer>
        )}
      </Paper>

      {result && result.total > 0 && (
        <Group justify="space-between">
          <Text size="sm" c="dimmed">
            Showing {(page - 1) * Number(perPage) + 1}–{Math.min(page * Number(perPage), result.total)} of {result.total}
          </Text>
          {result.last_page > 1 && (
            <Pagination value={page} onChange={setPage} total={result.last_page} />
          )}
        </Group>
      )}

      <Modal opened={!!editing} onClose={closeEdit} title={editing ? `Edit — ${editing.name}` : 'Edit'}>
        <form onSubmit={editForm.onSubmit((v) => editMut.mutate(v))}>
          <Stack gap="sm">
            <TextInput label="Email" value={editing?.email ?? ''} disabled />
            <TextInput label="Name" required {...editForm.getInputProps('name')} />
            <TextInput label="Phone" {...editForm.getInputProps('phone')} />
            <Select
              label="Role"
              data={[
                { value: 'admin', label: 'Admin (can manage portal users)' },
                { value: 'viewer', label: 'Viewer (view only)' },
              ]}
              {...editForm.getInputProps('role')}
            />
            <Group justify="flex-end" mt="xs">
              <Button variant="default" onClick={closeEdit}>Cancel</Button>
              <Button type="submit" loading={editMut.isPending}>Save</Button>
            </Group>
          </Stack>
        </form>
      </Modal>
    </Stack>
  );
}
