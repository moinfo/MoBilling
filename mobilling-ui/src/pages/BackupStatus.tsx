import { useState } from 'react';
import {
  Stack, Paper, Title, Text, Group, Badge, Table, TextInput, Select,
  ActionIcon, Center, Loader, Alert, SimpleGrid,
} from '@mantine/core';
import { useDebouncedValue } from '@mantine/hooks';
import { useQuery } from '@tanstack/react-query';
import { useNavigate } from 'react-router-dom';
import { IconDatabaseExport, IconSearch, IconExternalLink, IconAlertTriangle, IconAlertOctagon, IconCircleCheck } from '@tabler/icons-react';
import { getBackupStatus, getServers } from '../api/hosting';
import StatCard from '../components/Reports/StatCard';

/**
 * Backup status per account — WHM's listaccts carries two distinct flags
 * (`backup`, the setting; `has_backup`, an actual file on disk), which were
 * confirmed live to genuinely diverge: some accounts have the setting on
 * with nothing backed up yet. Worst cases (no setting AND no file) sort
 * first from the API.
 */
export default function BackupStatus() {
  const navigate = useNavigate();
  const [search, setSearch] = useState('');
  const [debouncedSearch] = useDebouncedValue(search, 300);
  const [serverId, setServerId] = useState<string | null>(null);

  const { data: serversData } = useQuery({ queryKey: ['servers-for-discover'], queryFn: getServers });
  const servers = serversData?.data?.data ?? [];

  const { data, isLoading, isFetching } = useQuery({
    queryKey: ['backup-status', serverId, debouncedSearch],
    queryFn: () => getBackupStatus({ server_id: serverId || undefined, search: debouncedSearch || undefined }),
    staleTime: 60_000,
  });
  const rows = data?.data?.data ?? [];
  const errors = data?.data?.errors ?? [];
  const noBackup = rows.filter((r) => !r.backup_enabled && !r.backup_exists).length;
  const missing = rows.filter((r) => r.backup_enabled && !r.backup_exists).length;

  return (
    <Stack gap="md">
      <Title order={3}>
        <Group gap="xs"><IconDatabaseExport size={22} /> Backup Status</Group>
      </Title>

      <Text size="sm" c="dimmed">
        Backup setting and actual backup file, per account, straight from WHM — the two can genuinely
        disagree (setting on, nothing backed up yet), which is exactly the risk this surfaces.
      </Text>

      <SimpleGrid cols={{ base: 2, sm: 3 }}>
        <StatCard label="Total Accounts" value={isLoading ? '—' : rows.length}
          icon={<IconDatabaseExport size={20} />} color="blue" />
        <StatCard label="Enabled but Missing" value={isLoading ? '—' : missing}
          icon={<IconAlertTriangle size={20} />} color="yellow" />
        <StatCard label="No Backup At All" value={isLoading ? '—' : noBackup}
          icon={<IconAlertOctagon size={20} />} color="red" />
      </SimpleGrid>

      {errors.length > 0 && (
        <Alert color="red" variant="light" icon={<IconAlertTriangle size={16} />}>
          {errors.join(' · ')}
        </Alert>
      )}

      <Paper withBorder p="sm" radius="sm">
        <Group gap="sm" wrap="wrap">
          <TextInput
            placeholder="Search domain, username, or client…" leftSection={<IconSearch size={14} />}
            value={search} onChange={(e) => setSearch(e.currentTarget.value)}
            style={{ flex: 1, minWidth: 280 }}
          />
          {servers.length > 1 && (
            <Select placeholder="Server" clearable w={200} value={serverId} onChange={setServerId}
              data={servers.map((s) => ({ value: s.id, label: s.name }))} />
          )}
        </Group>
      </Paper>

      <Paper withBorder radius="sm">
        {isLoading ? (
          <Center py="xl"><Loader /></Center>
        ) : rows.length === 0 ? (
          <Center py="xl"><Text c="dimmed">{isFetching ? 'Refreshing…' : 'No accounts found.'}</Text></Center>
        ) : (
          <Table.ScrollContainer minWidth={800}>
            <Table striped highlightOnHover verticalSpacing="xs">
              <Table.Thead>
                <Table.Tr>
                  <Table.Th w={48}>#</Table.Th>
                  <Table.Th>Domain</Table.Th>
                  <Table.Th>cPanel User</Table.Th>
                  <Table.Th>Setting</Table.Th>
                  <Table.Th>Backup File</Table.Th>
                  <Table.Th>Client</Table.Th>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {rows.map((r, i) => (
                  <Table.Tr key={`${r.server_id}-${r.cpanel_username}`}>
                    <Table.Td c="dimmed">{i + 1}</Table.Td>
                    <Table.Td fw={500}>{r.domain ?? '—'}</Table.Td>
                    <Table.Td>{r.cpanel_username}</Table.Td>
                    <Table.Td>
                      <Badge size="sm" variant="light" color={r.backup_enabled ? 'teal' : 'gray'}>
                        {r.backup_enabled ? 'Enabled' : 'Off'}
                      </Badge>
                    </Table.Td>
                    <Table.Td>
                      {r.backup_exists ? (
                        <Badge size="sm" variant="light" color="teal" leftSection={<IconCircleCheck size={12} />}>
                          Present
                        </Badge>
                      ) : (
                        <Badge size="sm" variant="light" color={r.backup_enabled ? 'orange' : 'red'}>
                          Missing
                        </Badge>
                      )}
                    </Table.Td>
                    <Table.Td>
                      {r.client ? (
                        <Group gap={4} wrap="nowrap">
                          <Text size="sm">{r.client.name}</Text>
                          <ActionIcon variant="subtle" size="xs" onClick={() => navigate(`/clients/${r.client!.id}`)}>
                            <IconExternalLink size={12} />
                          </ActionIcon>
                        </Group>
                      ) : (
                        <Badge size="sm" variant="light" color="gray">Not tracked</Badge>
                      )}
                    </Table.Td>
                  </Table.Tr>
                ))}
              </Table.Tbody>
            </Table>
          </Table.ScrollContainer>
        )}
      </Paper>
    </Stack>
  );
}
