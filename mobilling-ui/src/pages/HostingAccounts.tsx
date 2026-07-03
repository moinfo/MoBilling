import { useState } from 'react';
import {
  Title, Stack, Group, Table, Badge, ActionIcon, Tooltip, Text, Paper,
  Select, TextInput, Loader, Center, Drawer, Modal, Button, Pagination, Code,
} from '@mantine/core';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { notifications } from '@mantine/notifications';
import {
  IconSearch, IconExternalLink, IconPlayerPause, IconPlayerPlay,
  IconTrash, IconPackage, IconHistory, IconWorld,
} from '@tabler/icons-react';
import {
  getHostingAccounts, getHostingLogs, suspendHosting, unsuspendHosting,
  terminateHosting, changeHostingPackage, getHostingSso,
  HostingAccount, ProvisioningLog, HOSTING_STATUS_COLORS,
} from '../api/hosting';
import { usePermissions } from '../hooks/usePermissions';
import dayjs from 'dayjs';

export default function HostingAccounts() {
  const qc = useQueryClient();
  const { can } = usePermissions();
  const [statusFilter, setStatusFilter] = useState<string>('');
  const [search, setSearch] = useState('');
  const [page, setPage] = useState(1);
  const [logsFor, setLogsFor] = useState<HostingAccount | null>(null);
  const [pkgFor, setPkgFor] = useState<HostingAccount | null>(null);
  const [pkgName, setPkgName] = useState('');
  const [terminateFor, setTerminateFor] = useState<HostingAccount | null>(null);

  const params: Record<string, string> = { page: String(page) };
  if (statusFilter) params.status = statusFilter;
  if (search) params.search = search;

  const { data, isLoading } = useQuery({
    queryKey: ['hosting-accounts', params],
    queryFn: () => getHostingAccounts(params),
  });
  const accounts: HostingAccount[] = data?.data?.data?.data ?? [];
  const lastPage: number = data?.data?.data?.last_page ?? 1;

  const invalidate = () => qc.invalidateQueries({ queryKey: ['hosting-accounts'] });

  const actionMutation = useMutation({
    mutationFn: ({ fn, id }: { fn: (id: string) => Promise<any>; id: string }) => fn(id),
    onSuccess: (res: any) => {
      invalidate();
      notifications.show({ message: res?.data?.message ?? 'Action started.', color: 'green' });
    },
    onError: (e: any) => notifications.show({
      message: e?.response?.data?.message ?? 'Action failed.', color: 'red',
    }),
  });

  const pkgMutation = useMutation({
    mutationFn: ({ id, pkg }: { id: string; pkg: string }) => changeHostingPackage(id, pkg),
    onSuccess: () => {
      invalidate();
      notifications.show({ message: 'Package change started.', color: 'green' });
      setPkgFor(null);
      setPkgName('');
    },
    onError: () => notifications.show({ message: 'Package change failed.', color: 'red' }),
  });

  const openCpanel = async (account: HostingAccount) => {
    try {
      const res = await getHostingSso(account.id);
      window.open(res.data.url, '_blank', 'noopener');
    } catch (e: any) {
      notifications.show({
        title: 'cPanel login failed',
        message: e?.response?.data?.message ?? 'Could not create the session.',
        color: 'red',
      });
    }
  };

  return (
    <Stack>
      <Group justify="space-between">
        <Group gap="xs">
          <IconWorld size={22} />
          <Title order={2}>Hosting Accounts</Title>
        </Group>
      </Group>

      <Group gap="xs">
        <TextInput
          size="xs" placeholder="Search domain or username…" leftSection={<IconSearch size={13} />}
          value={search} onChange={(e) => { setSearch(e.currentTarget.value); setPage(1); }}
          w={240}
        />
        <Select
          size="xs" placeholder="All statuses" clearable w={150}
          value={statusFilter} onChange={(v) => { setStatusFilter(v ?? ''); setPage(1); }}
          data={[
            { value: 'pending', label: 'Pending' },
            { value: 'active', label: 'Active' },
            { value: 'suspended', label: 'Suspended' },
            { value: 'failed', label: 'Failed' },
            { value: 'terminated', label: 'Terminated' },
          ]}
        />
      </Group>

      {isLoading ? (
        <Center py="xl"><Loader /></Center>
      ) : accounts.length === 0 ? (
        <Center py="xl"><Text c="dimmed">No hosting accounts found.</Text></Center>
      ) : (
        <Paper withBorder radius="md">
          <Table.ScrollContainer minWidth={800}>
            <Table highlightOnHover>
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>Domain</Table.Th>
                  <Table.Th>Client</Table.Th>
                  <Table.Th>Username</Table.Th>
                  <Table.Th>Server</Table.Th>
                  <Table.Th>Package</Table.Th>
                  <Table.Th>Disk</Table.Th>
                  <Table.Th>Status</Table.Th>
                  <Table.Th></Table.Th>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {accounts.map((a) => (
                  <Table.Tr key={a.id}>
                    <Table.Td fw={500}>{a.domain}</Table.Td>
                    <Table.Td>
                      <Text size="sm">{a.subscription?.client?.name ?? '—'}</Text>
                    </Table.Td>
                    <Table.Td><Code>{a.cpanel_username}</Code></Table.Td>
                    <Table.Td><Text size="sm" c="dimmed">{a.server?.name ?? '—'}</Text></Table.Td>
                    <Table.Td><Text size="sm">{a.meta?.plan ?? a.package ?? '—'}</Text></Table.Td>
                    <Table.Td>
                      <Text size="xs" c="dimmed">
                        {a.meta?.disk_used ? `${a.meta.disk_used} / ${a.meta.disk_limit ?? '∞'}` : '—'}
                      </Text>
                    </Table.Td>
                    <Table.Td>
                      <Badge size="sm" color={HOSTING_STATUS_COLORS[a.status]} variant="light">
                        {a.status}
                      </Badge>
                    </Table.Td>
                    <Table.Td>
                      <Group gap={4} justify="flex-end" wrap="nowrap">
                        {can('hosting.sso') && a.status === 'active' && (
                          <Tooltip label="Login to cPanel">
                            <ActionIcon variant="light" color="teal" onClick={() => openCpanel(a)}>
                              <IconExternalLink size={15} />
                            </ActionIcon>
                          </Tooltip>
                        )}
                        {can('hosting.suspend') && a.status === 'active' && (
                          <Tooltip label="Suspend">
                            <ActionIcon variant="light" color="orange"
                              onClick={() => actionMutation.mutate({ fn: suspendHosting, id: a.id })}>
                              <IconPlayerPause size={15} />
                            </ActionIcon>
                          </Tooltip>
                        )}
                        {can('hosting.suspend') && a.status === 'suspended' && (
                          <Tooltip label="Unsuspend">
                            <ActionIcon variant="light" color="green"
                              onClick={() => actionMutation.mutate({ fn: unsuspendHosting, id: a.id })}>
                              <IconPlayerPlay size={15} />
                            </ActionIcon>
                          </Tooltip>
                        )}
                        {can('hosting.change_package') && ['active', 'suspended'].includes(a.status) && (
                          <Tooltip label="Change package">
                            <ActionIcon variant="light" color="grape"
                              onClick={() => { setPkgFor(a); setPkgName(a.package ?? ''); }}>
                              <IconPackage size={15} />
                            </ActionIcon>
                          </Tooltip>
                        )}
                        {can('hosting.read') && (
                          <Tooltip label="Provisioning log">
                            <ActionIcon variant="light" onClick={() => setLogsFor(a)}>
                              <IconHistory size={15} />
                            </ActionIcon>
                          </Tooltip>
                        )}
                        {can('hosting.terminate') && a.status !== 'terminated' && (
                          <Tooltip label="Terminate (deletes the account!)">
                            <ActionIcon variant="light" color="red" onClick={() => setTerminateFor(a)}>
                              <IconTrash size={15} />
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
        </Paper>
      )}

      {lastPage > 1 && (
        <Group justify="center">
          <Pagination value={page} onChange={setPage} total={lastPage} size="sm" />
        </Group>
      )}

      {/* Provisioning logs */}
      <Drawer opened={!!logsFor} onClose={() => setLogsFor(null)}
        title={`Provisioning log — ${logsFor?.domain ?? ''}`} position="right" size="md">
        {logsFor && <LogsList accountId={logsFor.id} />}
      </Drawer>

      {/* Change package */}
      <Modal opened={!!pkgFor} onClose={() => setPkgFor(null)} title={`Change package — ${pkgFor?.domain}`} centered>
        <Stack>
          <TextInput label="WHM package name" value={pkgName} required
            onChange={(e) => setPkgName(e.currentTarget.value)} />
          <Group justify="flex-end">
            <Button variant="default" onClick={() => setPkgFor(null)}>Cancel</Button>
            <Button color="grape" disabled={!pkgName.trim()} loading={pkgMutation.isPending}
              onClick={() => pkgFor && pkgMutation.mutate({ id: pkgFor.id, pkg: pkgName.trim() })}>
              Change Package
            </Button>
          </Group>
        </Stack>
      </Modal>

      {/* Terminate confirmation */}
      <Modal opened={!!terminateFor} onClose={() => setTerminateFor(null)} title="Terminate hosting account" centered>
        <Stack>
          <Text size="sm">
            This <Text span fw={700} c="red">permanently deletes</Text> the cPanel account{' '}
            <Text span fw={600}>{terminateFor?.domain}</Text> and all its files, emails, and databases
            from the server. This cannot be undone.
          </Text>
          <Group justify="flex-end">
            <Button variant="default" onClick={() => setTerminateFor(null)}>Cancel</Button>
            <Button color="red"
              onClick={() => {
                if (terminateFor) actionMutation.mutate({ fn: terminateHosting, id: terminateFor.id });
                setTerminateFor(null);
              }}>
              Terminate Account
            </Button>
          </Group>
        </Stack>
      </Modal>
    </Stack>
  );
}

function LogsList({ accountId }: { accountId: string }) {
  const { data, isLoading } = useQuery({
    queryKey: ['hosting-logs', accountId],
    queryFn: () => getHostingLogs(accountId),
  });
  const logs: ProvisioningLog[] = data?.data?.data ?? [];

  if (isLoading) return <Center py="md"><Loader size="sm" /></Center>;
  if (!logs.length) return <Text c="dimmed" size="sm">No log entries yet.</Text>;

  return (
    <Stack gap="xs">
      {logs.map((l) => (
        <Paper key={l.id} withBorder p="xs" radius="sm">
          <Group justify="space-between" wrap="nowrap">
            <Group gap="xs">
              <Badge size="xs" color={l.status === 'success' ? 'green' : 'red'} variant="light">
                {l.status}
              </Badge>
              <Code>{l.action}</Code>
            </Group>
            <Text size="xs" c="dimmed">{dayjs(l.created_at).format('D MMM YYYY HH:mm')}</Text>
          </Group>
          {l.error && <Text size="xs" c="red" mt={4}>{l.error}</Text>}
        </Paper>
      ))}
    </Stack>
  );
}
