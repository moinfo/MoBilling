import { useState } from 'react';
import {
  Stack, Paper, Title, Text, Group, Badge, Table, TextInput, Select,
  ActionIcon, Center, Loader, Alert, SimpleGrid, Progress,
} from '@mantine/core';
import { useDebouncedValue } from '@mantine/hooks';
import { useQuery } from '@tanstack/react-query';
import { useNavigate } from 'react-router-dom';
import { IconGauge, IconSearch, IconExternalLink, IconAlertTriangle, IconAlertOctagon } from '@tabler/icons-react';
import { getBandwidthUsage, getServers } from '../api/hosting';
import StatCard from '../components/Reports/StatCard';

const fmtBytes = (bytes: number) => {
  if (bytes <= 0) return '0 MB';
  const gb = bytes / 1_073_741_824;
  return gb >= 1 ? `${gb.toFixed(2)} GB` : `${(bytes / 1_048_576).toFixed(0)} MB`;
};

const usageColor = (pct: number | null) => {
  if (pct === null) return 'gray';
  if (pct >= 100) return 'red';
  if (pct >= 90) return 'orange';
  if (pct >= 75) return 'yellow';
  return 'teal';
};

/**
 * This month's bandwidth usage per account, worst-first — the proactive
 * counterpart to "Fix Bandwidth Suspension" on Service Management: see who's
 * approaching their limit before WHM's own cron suspends them for it.
 */
export default function BandwidthUsage() {
  const navigate = useNavigate();
  const [search, setSearch] = useState('');
  const [debouncedSearch] = useDebouncedValue(search, 300);
  const [serverId, setServerId] = useState<string | null>(null);

  const { data: serversData } = useQuery({ queryKey: ['servers-for-discover'], queryFn: getServers });
  const servers = serversData?.data?.data ?? [];

  const { data, isLoading, isFetching } = useQuery({
    queryKey: ['bandwidth-usage', serverId, debouncedSearch],
    queryFn: () => getBandwidthUsage({ server_id: serverId || undefined, search: debouncedSearch || undefined }),
    staleTime: 60_000,
  });
  const rows = data?.data?.data ?? [];
  const errors = data?.data?.errors ?? [];
  const overLimit = rows.filter((r) => (r.percent_used ?? 0) >= 100).length;
  const near = rows.filter((r) => (r.percent_used ?? 0) >= 75 && (r.percent_used ?? 0) < 100).length;

  return (
    <Stack gap="md">
      <Title order={3}>
        <Group gap="xs"><IconGauge size={22} /> Bandwidth Usage</Group>
      </Title>

      <Text size="sm" c="dimmed">
        This month's bandwidth per account, straight from WHM — sorted worst-first so an account about
        to hit its limit (and risk an auto-suspension) shows up before it happens.
      </Text>

      <SimpleGrid cols={{ base: 2, sm: 3 }}>
        <StatCard label="Total Accounts" value={isLoading ? '—' : rows.length}
          icon={<IconGauge size={20} />} color="blue" />
        <StatCard label="Near Limit (75–99%)" value={isLoading ? '—' : near}
          icon={<IconAlertTriangle size={20} />} color="yellow" />
        <StatCard label="Over Limit" value={isLoading ? '—' : overLimit}
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
          <Table.ScrollContainer minWidth={900}>
            <Table striped highlightOnHover verticalSpacing="xs">
              <Table.Thead>
                <Table.Tr>
                  <Table.Th w={48}>#</Table.Th>
                  <Table.Th>Domain</Table.Th>
                  <Table.Th>cPanel User</Table.Th>
                  <Table.Th>Used</Table.Th>
                  <Table.Th>Limit</Table.Th>
                  <Table.Th w={180}>Usage</Table.Th>
                  <Table.Th>Client</Table.Th>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {rows.map((r, i) => (
                  <Table.Tr key={`${r.server_id}-${r.cpanel_username}`}>
                    <Table.Td c="dimmed">{i + 1}</Table.Td>
                    <Table.Td fw={500}>{r.domain ?? '—'}</Table.Td>
                    <Table.Td>{r.cpanel_username}</Table.Td>
                    <Table.Td fz="sm" c="dimmed">{fmtBytes(r.used_bytes)}</Table.Td>
                    <Table.Td fz="sm" c="dimmed">{r.limit_bytes ? fmtBytes(r.limit_bytes) : 'Unlimited'}</Table.Td>
                    <Table.Td>
                      {r.percent_used === null ? (
                        <Text size="xs" c="dimmed">—</Text>
                      ) : (
                        <Group gap={6} wrap="nowrap">
                          <Progress value={Math.min(r.percent_used, 100)} color={usageColor(r.percent_used)}
                            size="sm" style={{ flex: 1 }} />
                          <Badge size="sm" variant="light" color={usageColor(r.percent_used)}>
                            {r.percent_used}%
                          </Badge>
                        </Group>
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
