import { useState } from 'react';
import {
  Stack, Paper, Title, Table, Badge, Button, Group, Modal, TextInput,
  PasswordInput, Select, Switch, LoadingOverlay, ActionIcon, Text,
} from '@mantine/core';
import { useForm } from '@mantine/form';
import { notifications } from '@mantine/notifications';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { IconPlus, IconEdit, IconTrash } from '@tabler/icons-react';
import { getPortalUsers, createPortalUser, updatePortalUser, deletePortalUser, PortalUser } from '../../api/portal';
import { modals } from '@mantine/modals';

export default function PortalUsers() {
  const queryClient = useQueryClient();
  const [modalOpen, setModalOpen] = useState(false);
  const [editing, setEditing] = useState<PortalUser | null>(null);

  const { data, isLoading } = useQuery({
    queryKey: ['portal-users'],
    queryFn: () => getPortalUsers(),
  });

  const users = data?.data?.data || [];

  const form = useForm({
    initialValues: { name: '', email: '', password: '', phone: '', role: 'viewer' },
    validate: {
      name: (v) => (v.length > 0 ? null : 'Required'),
      email: (v) => (/^\S+@\S+$/.test(v) ? null : 'Invalid email'),
      password: (v) => {
        if (editing) return null; // Password optional when editing
        return v.length >= 8 ? null : 'Minimum 8 characters';
      },
    },
  });

  const createMutation = useMutation({
    mutationFn: createPortalUser,
    onSuccess: () => {
      notifications.show({ title: 'Success', message: 'User created', color: 'green' });
      queryClient.invalidateQueries({ queryKey: ['portal-users'] });
      closeModal();
    },
    onError: (err: any) => {
      notifications.show({ title: 'Error', message: err.response?.data?.message || 'Failed', color: 'red' });
    },
  });

  const updateMutation = useMutation({
    mutationFn: ({ id, data }: { id: string; data: any }) => updatePortalUser(id, data),
    onSuccess: () => {
      notifications.show({ title: 'Success', message: 'User updated', color: 'green' });
      queryClient.invalidateQueries({ queryKey: ['portal-users'] });
      closeModal();
    },
  });

  const deleteMutation = useMutation({
    mutationFn: deletePortalUser,
    onSuccess: () => {
      notifications.show({ title: 'Success', message: 'User deleted', color: 'green' });
      queryClient.invalidateQueries({ queryKey: ['portal-users'] });
    },
    onError: (err: any) => {
      notifications.show({ title: 'Error', message: err.response?.data?.message || 'Failed', color: 'red' });
    },
  });

  const openCreate = () => {
    setEditing(null);
    form.reset();
    setModalOpen(true);
  };

  const openEdit = (user: PortalUser) => {
    setEditing(user);
    form.setValues({ name: user.name, email: user.email, password: '', phone: user.phone || '', role: user.role });
    setModalOpen(true);
  };

  const closeModal = () => {
    setModalOpen(false);
    setEditing(null);
    form.reset();
  };

  const handleSubmit = (values: typeof form.values) => {
    if (editing) {
      updateMutation.mutate({ id: editing.id, data: { name: values.name, phone: values.phone, role: values.role } });
    } else {
      createMutation.mutate(values);
    }
  };

  const confirmDelete = (user: PortalUser) => {
    modals.openConfirmModal({
      title: 'Delete User',
      children: <Text size="sm">Are you sure you want to delete {user.name}?</Text>,
      labels: { confirm: 'Delete', cancel: 'Cancel' },
      confirmProps: { color: 'red' },
      onConfirm: () => deleteMutation.mutate(user.id),
    });
  };

  const toggleActive = (user: PortalUser) => {
    updateMutation.mutate({ id: user.id, data: { is_active: !user.is_active } });
  };

  return (
    <Stack gap="lg" pos="relative">
      <LoadingOverlay visible={isLoading} />
      <Group justify="space-between">
        <Title order={3}>Portal Users</Title>
        <Button leftSection={<IconPlus size={16} />} onClick={openCreate}>Add User</Button>
      </Group>

      <Paper withBorder p="md">
        <Table striped highlightOnHover>
          <Table.Thead>
            <Table.Tr>
              <Table.Th>Name</Table.Th>
              <Table.Th>Email</Table.Th>
              <Table.Th>Role</Table.Th>
              <Table.Th>Status</Table.Th>
              <Table.Th>Last Login</Table.Th>
              <Table.Th>Actions</Table.Th>
            </Table.Tr>
          </Table.Thead>
          <Table.Tbody>
            {users.map((u: PortalUser) => (
              <Table.Tr key={u.id}>
                <Table.Td fw={500}>{u.name}</Table.Td>
                <Table.Td>{u.email}</Table.Td>
                <Table.Td>
                  <Badge color={u.role === 'admin' ? 'blue' : 'gray'} variant="light" size="sm">
                    {u.role}
                  </Badge>
                </Table.Td>
                <Table.Td>
                  <Switch
                    checked={u.is_active}
                    onChange={() => toggleActive(u)}
                    size="xs"
                    label={u.is_active ? 'Active' : 'Inactive'}
                  />
                </Table.Td>
                <Table.Td>{u.last_login_at || 'Never'}</Table.Td>
                <Table.Td>
                  <Group gap="xs">
                    <ActionIcon variant="subtle" onClick={() => openEdit(u)}><IconEdit size={16} /></ActionIcon>
                    <ActionIcon variant="subtle" color="red" onClick={() => confirmDelete(u)}><IconTrash size={16} /></ActionIcon>
                  </Group>
                </Table.Td>
              </Table.Tr>
            ))}
            {users.length === 0 && (
              <Table.Tr>
                <Table.Td colSpan={6} ta="center" c="dimmed">No users found</Table.Td>
              </Table.Tr>
            )}
          </Table.Tbody>
        </Table>
      </Paper>

      <Modal opened={modalOpen} onClose={closeModal} title={editing ? 'Edit User' : 'Add User'}>
        <form onSubmit={form.onSubmit(handleSubmit)}>
          <Stack gap="sm">
            <TextInput label="Name" required {...form.getInputProps('name')} />
            <TextInput label="Email" required disabled={!!editing} {...form.getInputProps('email')} />
            {!editing && (
              <PasswordInput label="Password" required {...form.getInputProps('password')} />
            )}
            <TextInput label="Phone" {...form.getInputProps('phone')} />
            <Select
              label="Role"
              data={[
                { value: 'admin', label: 'Admin (can manage users)' },
                { value: 'viewer', label: 'Viewer (view only)' },
              ]}
              {...form.getInputProps('role')}
            />
            <Button type="submit" loading={createMutation.isPending || updateMutation.isPending}>
              {editing ? 'Update' : 'Create'}
            </Button>
          </Stack>
        </form>
      </Modal>
    </Stack>
  );
}
