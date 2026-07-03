import { useState } from 'react';
import {
  Stack, Group, Button, Table, Badge, ActionIcon, Tooltip, Modal, TextInput,
  NumberInput, PasswordInput, Switch, Text, Paper, Loader, Center, Alert, Code,
} from '@mantine/core';
import { useForm } from '@mantine/form';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { notifications } from '@mantine/notifications';
import { IconPlus, IconEdit, IconTrash, IconPlugConnected, IconServer, IconAlertCircle } from '@tabler/icons-react';
import {
  getServers, createServer, updateServer, deleteServer, testServer,
  Server, ServerFormData,
} from '../../api/hosting';

export default function ServersTab() {
  const qc = useQueryClient();
  const [modalOpen, setModalOpen] = useState(false);
  const [editing, setEditing] = useState<Server | null>(null);
  const [testResult, setTestResult] = useState<{ id: string; packages: string[] } | null>(null);
  const [testingId, setTestingId] = useState<string | null>(null);

  const { data, isLoading } = useQuery({ queryKey: ['servers'], queryFn: getServers });
  const servers: Server[] = data?.data?.data ?? [];

  const saveMutation = useMutation({
    mutationFn: (v: ServerFormData) =>
      editing ? updateServer(editing.id, v) : createServer(v),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['servers'] });
      notifications.show({ message: editing ? 'Server updated.' : 'Server added.', color: 'green' });
      setModalOpen(false);
      setEditing(null);
    },
    onError: (e: any) => notifications.show({
      message: e?.response?.data?.message ?? 'Failed to save server.', color: 'red',
    }),
  });

  const deleteMutation = useMutation({
    mutationFn: deleteServer,
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['servers'] });
      notifications.show({ message: 'Server deleted.', color: 'gray' });
    },
    onError: (e: any) => notifications.show({
      message: e?.response?.data?.message ?? 'Cannot delete this server.', color: 'red',
    }),
  });

  const handleTest = async (server: Server) => {
    setTestingId(server.id);
    setTestResult(null);
    try {
      const res = await testServer(server.id);
      setTestResult({ id: server.id, packages: res.data.packages });
      notifications.show({ message: `Connected — ${res.data.packages.length} packages found.`, color: 'green' });
    } catch (e: any) {
      notifications.show({
        title: 'Connection failed',
        message: e?.response?.data?.message ?? 'Could not reach the WHM server.',
        color: 'red',
      });
    } finally {
      setTestingId(null);
    }
  };

  return (
    <Stack>
      <Group justify="space-between">
        <Group gap="xs">
          <IconServer size={20} />
          <Text fw={600}>WHM / cPanel Servers</Text>
        </Group>
        <Button size="xs" leftSection={<IconPlus size={14} />}
          onClick={() => { setEditing(null); setModalOpen(true); }}>
          Add Server
        </Button>
      </Group>

      <Alert icon={<IconAlertCircle size={16} />} color="blue" variant="light">
        Create the API token in WHM under <b>Development » Manage API Tokens</b>. Hosting
        products are provisioned on these servers when their subscription is activated.
      </Alert>

      {isLoading ? (
        <Center py="lg"><Loader /></Center>
      ) : servers.length === 0 ? (
        <Text c="dimmed" size="sm">No servers configured yet.</Text>
      ) : (
        <Paper withBorder radius="md">
          <Table highlightOnHover>
            <Table.Thead>
              <Table.Tr>
                <Table.Th>Name</Table.Th>
                <Table.Th>Hostname</Table.Th>
                <Table.Th>User</Table.Th>
                <Table.Th>Accounts</Table.Th>
                <Table.Th>Status</Table.Th>
                <Table.Th></Table.Th>
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {servers.map((s) => (
                <Table.Tr key={s.id}>
                  <Table.Td fw={500}>{s.name}</Table.Td>
                  <Table.Td><Code>{s.hostname}:{s.port}</Code></Table.Td>
                  <Table.Td>{s.username}</Table.Td>
                  <Table.Td>{s.hosting_accounts_count ?? 0}</Table.Td>
                  <Table.Td>
                    <Badge size="sm" color={s.is_active ? 'green' : 'gray'} variant="light">
                      {s.is_active ? 'Active' : 'Inactive'}
                    </Badge>
                  </Table.Td>
                  <Table.Td>
                    <Group gap={4} justify="flex-end">
                      <Tooltip label="Test connection">
                        <ActionIcon variant="light" color="teal" loading={testingId === s.id}
                          onClick={() => handleTest(s)}>
                          <IconPlugConnected size={15} />
                        </ActionIcon>
                      </Tooltip>
                      <ActionIcon variant="light" onClick={() => { setEditing(s); setModalOpen(true); }}>
                        <IconEdit size={15} />
                      </ActionIcon>
                      <ActionIcon variant="light" color="red" onClick={() => deleteMutation.mutate(s.id)}>
                        <IconTrash size={15} />
                      </ActionIcon>
                    </Group>
                  </Table.Td>
                </Table.Tr>
              ))}
            </Table.Tbody>
          </Table>
        </Paper>
      )}

      {testResult && (
        <Paper withBorder p="sm" radius="md">
          <Text size="sm" fw={600} mb={4}>
            Packages on {servers.find(s => s.id === testResult.id)?.name}:
          </Text>
          <Group gap={6}>
            {testResult.packages.map(p => <Badge key={p} variant="outline" size="sm">{p}</Badge>)}
            {testResult.packages.length === 0 && <Text size="sm" c="dimmed">none</Text>}
          </Group>
        </Paper>
      )}

      <ServerFormModal
        opened={modalOpen}
        editing={editing}
        loading={saveMutation.isPending}
        onClose={() => { setModalOpen(false); setEditing(null); }}
        onSubmit={(v) => saveMutation.mutate(v)}
      />
    </Stack>
  );
}

function ServerFormModal({ opened, editing, loading, onClose, onSubmit }: {
  opened: boolean; editing: Server | null; loading: boolean;
  onClose: () => void; onSubmit: (v: ServerFormData) => void;
}) {
  const form = useForm<ServerFormData>({
    initialValues: {
      name: '', hostname: '', port: 2087, username: 'root',
      api_token: '', is_active: true, verify_ssl: true,
    },
  });

  // Reset when target changes
  const [last, setLast] = useState<string | null>('init');
  const key = editing?.id ?? 'new';
  if (opened && last !== key) {
    setLast(key);
    form.setValues(editing ? {
      name: editing.name, hostname: editing.hostname, port: editing.port,
      username: editing.username, api_token: '', is_active: editing.is_active,
      verify_ssl: editing.verify_ssl,
    } : {
      name: '', hostname: '', port: 2087, username: 'root',
      api_token: '', is_active: true, verify_ssl: true,
    });
  }
  if (!opened && last !== 'init') setLast('init');

  return (
    <Modal opened={opened} onClose={onClose} title={editing ? 'Edit Server' : 'Add WHM Server'} centered>
      <form onSubmit={form.onSubmit(onSubmit)}>
        <Stack gap="sm">
          <TextInput label="Name" placeholder="cPanel-01" required {...form.getInputProps('name')} />
          <Group grow>
            <TextInput label="Hostname" placeholder="server.example.com" required {...form.getInputProps('hostname')} />
            <NumberInput label="Port" min={1} max={65535} {...form.getInputProps('port')} />
          </Group>
          <TextInput label="WHM username" placeholder="root or reseller" required {...form.getInputProps('username')} />
          <PasswordInput
            label="API token"
            placeholder={editing ? 'Leave blank to keep the current token' : 'WHM API token'}
            required={!editing}
            {...form.getInputProps('api_token')}
          />
          <Group>
            <Switch label="Active" {...form.getInputProps('is_active', { type: 'checkbox' })} />
            <Switch label="Verify SSL certificate" {...form.getInputProps('verify_ssl', { type: 'checkbox' })} />
          </Group>
          <Group justify="flex-end">
            <Button variant="default" onClick={onClose}>Cancel</Button>
            <Button type="submit" loading={loading}>Save</Button>
          </Group>
        </Stack>
      </form>
    </Modal>
  );
}
