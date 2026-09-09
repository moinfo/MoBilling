import { useState } from 'react';
import { Title, Table, Text, Group, Pagination, Badge, ActionIcon, Modal, Button, TextInput, NumberInput, Select, Switch, Stack, Tooltip } from '@mantine/core';
import { useForm } from '@mantine/form';
import { useDebouncedValue } from '@mantine/hooks';
import { modals } from '@mantine/modals';
import { notifications } from '@mantine/notifications';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { IconPlus, IconEdit, IconTrash, IconSearch, IconPlugConnected, IconBook2 } from '@tabler/icons-react';
import {
  getMikrotikRouters, createMikrotikRouter, updateMikrotikRouter, deleteMikrotikRouter, testMikrotikRouter,
  MikrotikRouter,
} from '../api/mikrotikRouters';
import { usePermissions } from '../hooks/usePermissions';
import WifiRouterSetupGuide from '../components/WifiRouterSetupGuide';

const PAYMENT_MODE_OPTIONS = [
  { value: 'self_managed', label: 'Self-managed (your own Pesapal collects it)' },
  { value: 'platform_collected', label: 'Platform-collected (MoBilling settles with you)' },
];

export default function WifiRouters() {
  const queryClient = useQueryClient();
  const { can } = usePermissions();
  const canCreate = can('wifi_routers.create');
  const canUpdate = can('wifi_routers.update');
  const canDelete = can('wifi_routers.delete');

  const [page, setPage] = useState(1);
  const [search, setSearch] = useState('');
  const [debouncedSearch] = useDebouncedValue(search, 300);
  const [formOpen, setFormOpen] = useState(false);
  const [editing, setEditing] = useState<MikrotikRouter | null>(null);
  const [testingId, setTestingId] = useState<string | null>(null);
  const [guideOpen, setGuideOpen] = useState(false);

  const { data } = useQuery({
    queryKey: ['mikrotik-routers', page, debouncedSearch],
    queryFn: () => getMikrotikRouters({ page, search: debouncedSearch || undefined }),
  });

  const items: MikrotikRouter[] = data?.data?.data || [];
  const meta = data?.data?.meta;

  const form = useForm({
    initialValues: {
      name: '', host: '', local_login_host: '', api_port: 8728, username: '', password: '', use_tls: false,
      payment_mode: 'self_managed', is_active: true,
    },
    validate: {
      name: (v) => (v.trim().length > 0 ? null : 'Required'),
      host: (v) => (v.trim().length > 0 ? null : 'Required'),
      username: (v) => (v.trim().length > 0 ? null : 'Required'),
      password: (v) => (editing || v.trim().length > 0 ? null : 'Required'),
    },
  });

  const closeForm = () => { setFormOpen(false); setEditing(null); form.reset(); };
  const openCreate = () => {
    setEditing(null);
    form.setValues({ name: '', host: '', local_login_host: '', api_port: 8728, username: '', password: '', use_tls: false, payment_mode: 'self_managed', is_active: true });
    setFormOpen(true);
  };
  const openEdit = (r: MikrotikRouter) => {
    setEditing(r);
    form.setValues({ name: r.name, host: r.host, local_login_host: r.local_login_host ?? '', api_port: r.api_port, username: r.username, password: '', use_tls: r.use_tls, payment_mode: r.payment_mode, is_active: r.is_active });
    setFormOpen(true);
  };

  const createMutation = useMutation({
    mutationFn: createMikrotikRouter,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['mikrotik-routers'] });
      notifications.show({ title: 'Created', message: 'Router added', color: 'green' });
      closeForm();
    },
    onError: (err: any) => notifications.show({ title: 'Error', message: err.response?.data?.message || 'Failed to create', color: 'red' }),
  });

  const updateMutation = useMutation({
    mutationFn: (values: any) => updateMikrotikRouter(editing!.id, values),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['mikrotik-routers'] });
      notifications.show({ title: 'Updated', message: 'Router updated', color: 'green' });
      closeForm();
    },
    onError: (err: any) => notifications.show({ title: 'Error', message: err.response?.data?.message || 'Failed to update', color: 'red' }),
  });

  const deleteMutation = useMutation({
    mutationFn: deleteMikrotikRouter,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['mikrotik-routers'] });
      notifications.show({ title: 'Deleted', message: 'Router deleted', color: 'green' });
    },
    onError: (err: any) => notifications.show({ title: 'Error', message: err.response?.data?.message || 'Failed to delete', color: 'red' }),
  });

  const handleDelete = (r: MikrotikRouter) => modals.openConfirmModal({
    title: 'Delete Router',
    children: `Delete "${r.name}" (${r.host})? Any WiFi plans on this router will also stop working.`,
    labels: { confirm: 'Delete', cancel: 'Cancel' },
    confirmProps: { color: 'red' },
    onConfirm: () => deleteMutation.mutate(r.id),
  });

  const handleTest = async (r: MikrotikRouter) => {
    setTestingId(r.id);
    try {
      const res = await testMikrotikRouter(r.id);
      notifications.show({ title: 'Connected', message: res.data.data.message, color: 'green' });
    } catch (e: any) {
      notifications.show({ title: 'Connection failed', message: e?.response?.data?.data?.message ?? 'Could not reach the router.', color: 'red' });
    } finally {
      setTestingId(null);
      queryClient.invalidateQueries({ queryKey: ['mikrotik-routers'] });
    }
  };

  return (
    <>
      <Group justify="space-between" mb="md">
        <Title order={2}>WiFi Routers</Title>
        <Group>
          <TextInput placeholder="Search..." leftSection={<IconSearch size={16} />}
            value={search} onChange={(e) => { setSearch(e.currentTarget.value); setPage(1); }} maw={250} />
          <Button variant="default" leftSection={<IconBook2 size={16} />} onClick={() => setGuideOpen(true)}>Setup Guide</Button>
          {canCreate && (
            <Button leftSection={<IconPlus size={16} />} onClick={openCreate}>Add Router</Button>
          )}
        </Group>
      </Group>

      {items.length === 0 ? (
        <Text c="dimmed" ta="center" py="xl">No routers yet — add your MikroTik to start selling WiFi vouchers.</Text>
      ) : (
        <Table striped highlightOnHover>
          <Table.Thead>
            <Table.Tr>
              <Table.Th>Name</Table.Th>
              <Table.Th>Host</Table.Th>
              <Table.Th>Payment</Table.Th>
              <Table.Th>Last Test</Table.Th>
              <Table.Th>Status</Table.Th>
              <Table.Th w={140}>Actions</Table.Th>
            </Table.Tr>
          </Table.Thead>
          <Table.Tbody>
            {items.map((r) => (
              <Table.Tr key={r.id}>
                <Table.Td fw={500}>{r.name}</Table.Td>
                <Table.Td>{r.host}:{r.api_port}</Table.Td>
                <Table.Td>
                  <Badge size="sm" variant="light" color={r.payment_mode === 'platform_collected' ? 'violet' : 'gray'}>
                    {r.payment_mode === 'platform_collected' ? 'Platform-collected' : 'Self-managed'}
                  </Badge>
                </Table.Td>
                <Table.Td>
                  {r.last_test_status ? (
                    <Tooltip label={r.last_test_message ?? ''}>
                      <Badge size="sm" variant="light" color={r.last_test_status === 'success' ? 'green' : 'red'}>
                        {r.last_test_status === 'success' ? 'Connected' : 'Failed'}
                      </Badge>
                    </Tooltip>
                  ) : (
                    <Text size="xs" c="dimmed">Never tested</Text>
                  )}
                </Table.Td>
                <Table.Td>
                  <Badge color={r.is_active ? 'green' : 'gray'} variant="light">
                    {r.is_active ? 'Active' : 'Inactive'}
                  </Badge>
                </Table.Td>
                <Table.Td>
                  <Group gap="xs">
                    <Tooltip label="Test connection">
                      <ActionIcon variant="light" color="blue" loading={testingId === r.id} onClick={() => handleTest(r)}>
                        <IconPlugConnected size={16} />
                      </ActionIcon>
                    </Tooltip>
                    {canUpdate && <ActionIcon variant="light" onClick={() => openEdit(r)}><IconEdit size={16} /></ActionIcon>}
                    {canDelete && <ActionIcon variant="light" color="red" onClick={() => handleDelete(r)}><IconTrash size={16} /></ActionIcon>}
                  </Group>
                </Table.Td>
              </Table.Tr>
            ))}
          </Table.Tbody>
        </Table>
      )}

      {meta && meta.last_page > 1 && (
        <Group justify="center" mt="md">
          <Pagination total={meta.last_page} value={page} onChange={setPage} />
        </Group>
      )}

      <Modal opened={formOpen} onClose={closeForm} title={editing ? 'Edit Router' : 'New Router'} size="md">
        <form onSubmit={form.onSubmit((v) => (editing ? updateMutation : createMutation).mutate(v))}>
          <Stack>
            <TextInput label="Name" required placeholder="e.g. Home WiFi" {...form.getInputProps('name')} />
            <TextInput label="Host / IP Address" required placeholder="e.g. 41.xxx.xxx.xxx" {...form.getInputProps('host')} />
            <TextInput label="Local Hotspot IP (optional)" placeholder="e.g. 192.168.88.1"
              description="The address customer devices see on the WiFi itself — lets us auto-connect them after payment instead of making them type the voucher code."
              {...form.getInputProps('local_login_host')} />
            <NumberInput label="API Port" min={1} max={65535} {...form.getInputProps('api_port')} />
            <TextInput label="Username" required {...form.getInputProps('username')} />
            <TextInput label="Password" type="password" required={!editing}
              placeholder={editing ? 'Leave blank to keep current password' : undefined}
              {...form.getInputProps('password')} />
            <Switch label="Use TLS (API-SSL, port 8729)" {...form.getInputProps('use_tls', { type: 'checkbox' })} />
            <Select label="Payment Mode" data={PAYMENT_MODE_OPTIONS} {...form.getInputProps('payment_mode')} />
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

      <WifiRouterSetupGuide opened={guideOpen} onClose={() => setGuideOpen(false)} />
    </>
  );
}
