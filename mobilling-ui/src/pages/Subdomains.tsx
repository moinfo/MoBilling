import { useState } from 'react';
import {
  Stack, Paper, Title, Text, Group, Badge, Table, TextInput, Select,
  ActionIcon, Center, Loader, Tooltip, Alert, SimpleGrid, SegmentedControl,
} from '@mantine/core';
import { useDebouncedValue } from '@mantine/hooks';
import { useQuery } from '@tanstack/react-query';
import { useNavigate } from 'react-router-dom';
import { IconSitemap, IconSearch, IconExternalLink, IconAlertTriangle, IconPlug } from '@tabler/icons-react';
import { getSubdomains, getServers } from '../api/hosting';
import StatCard from '../components/Reports/StatCard';

/**
 * Every subdomain and addon domain WHM actually has (get_domain_info is
 * server-wide, unlike Discover Hosting Accounts' per-account listaccts
 * loop) — so staff can find where a specific one lives, and whose it is,
 * without shelling into cPanel one account at a time.
 */
export default function Subdomains() {
  const navigate = useNavigate();
  const [search, setSearch] = useState('');
  const [debouncedSearch] = useDebouncedValue(search, 300);
  const [serverId, setServerId] = useState<string | null>(null);
  const [type, setType] = useState<'all' | 'sub' | 'addon'>('all');

  const { data: serversData } = useQuery({ queryKey: ['servers-for-discover'], queryFn: getServers });
  const servers = serversData?.data?.data ?? [];

  const { data, isLoading, isFetching } = useQuery({
    queryKey: ['subdomains', serverId, debouncedSearch],
    queryFn: () => getSubdomains({ server_id: serverId || undefined, search: debouncedSearch || undefined }),
    staleTime: 60_000,
  });
  const allRows = data?.data?.data ?? [];
  const errors = data?.data?.errors ?? [];
  const rows = type === 'all' ? allRows : allRows.filter((r) => r.type === type);
  const linked = allRows.filter((r) => r.client).length;
  const addonCount = allRows.filter((r) => r.type === 'addon').length;

  return (
    <Stack gap="md">
      <Title order={3}>
        <Group gap="xs"><IconSitemap size={22} /> Subdomains &amp; Addon Domains</Group>
      </Title>

      <Text size="sm" c="dimmed">
        Every subdomain and addon domain that exists across the WHM server(s), pulled straight from
        the server — not limited to accounts already tracked here.
      </Text>

      <SimpleGrid cols={{ base: 2, sm: 3 }}>
        <StatCard label="Total" value={isLoading ? '—' : allRows.length}
          icon={<IconSitemap size={20} />} color="blue" />
        <StatCard label="Addon Domains" value={isLoading ? '—' : addonCount}
          icon={<IconPlug size={20} />} color="grape" />
        <StatCard label="Linked to a Client" value={isLoading ? '—' : linked}
          icon={<IconExternalLink size={20} />} color="teal" />
      </SimpleGrid>

      {errors.length > 0 && (
        <Alert color="red" variant="light" icon={<IconAlertTriangle size={16} />}>
          {errors.join(' · ')}
        </Alert>
      )}

      <Paper withBorder p="sm" radius="sm">
        <Group gap="sm" wrap="wrap">
          <TextInput
            placeholder="Search subdomain, parent domain, username, or client…" leftSection={<IconSearch size={14} />}
            value={search} onChange={(e) => setSearch(e.currentTarget.value)}
            style={{ flex: 1, minWidth: 280 }}
          />
          <SegmentedControl value={type} onChange={(v) => setType(v as typeof type)}
            data={[
              { value: 'all', label: 'All' },
              { value: 'sub', label: 'Subdomains' },
              { value: 'addon', label: 'Addon Domains' },
            ]} />
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
          <Center py="xl"><Text c="dimmed">{isFetching ? 'Refreshing…' : 'No domains found.'}</Text></Center>
        ) : (
          <Table.ScrollContainer minWidth={950}>
            <Table striped highlightOnHover verticalSpacing="xs">
              <Table.Thead>
                <Table.Tr>
                  <Table.Th w={48}>#</Table.Th>
                  <Table.Th>Type</Table.Th>
                  <Table.Th>Domain</Table.Th>
                  <Table.Th>Parent Domain</Table.Th>
                  <Table.Th>cPanel User</Table.Th>
                  <Table.Th>PHP Version</Table.Th>
                  <Table.Th>Client</Table.Th>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {rows.map((r, i) => (
                  <Table.Tr key={`${r.server_id}-${r.subdomain}`}>
                    <Table.Td c="dimmed">{i + 1}</Table.Td>
                    <Table.Td>
                      <Badge size="sm" variant="light" color={r.type === 'addon' ? 'grape' : 'blue'}>
                        {r.type === 'addon' ? 'Addon' : 'Sub'}
                      </Badge>
                    </Table.Td>
                    <Table.Td fw={500}>
                      <Tooltip label={r.docroot ?? '—'}>
                        <Text size="sm">{r.subdomain ?? '—'}</Text>
                      </Tooltip>
                    </Table.Td>
                    <Table.Td fz="sm" c="dimmed">{r.parent_domain ?? '—'}</Table.Td>
                    <Table.Td>{r.cpanel_username}</Table.Td>
                    <Table.Td fz="sm" c="dimmed">{r.php_version ?? '—'}</Table.Td>
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
