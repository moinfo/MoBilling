import { useState } from 'react';
import {
  Stack, Paper, Title, Text, Group, Badge, Table, TextInput, Select,
  ActionIcon, Center, Loader, Tooltip, Alert, SimpleGrid,
} from '@mantine/core';
import { useDebouncedValue } from '@mantine/hooks';
import { useQuery } from '@tanstack/react-query';
import { useNavigate } from 'react-router-dom';
import { IconSitemap, IconSearch, IconExternalLink, IconAlertTriangle } from '@tabler/icons-react';
import { getSubdomains, getServers } from '../api/hosting';
import StatCard from '../components/Reports/StatCard';

/**
 * Every subdomain WHM actually has (get_domain_info is server-wide, unlike
 * Discover Hosting Accounts' per-account listaccts loop) — so staff can find
 * where a specific subdomain lives, and whose it is, without shelling into
 * cPanel one account at a time.
 */
export default function Subdomains() {
  const navigate = useNavigate();
  const [search, setSearch] = useState('');
  const [debouncedSearch] = useDebouncedValue(search, 300);
  const [serverId, setServerId] = useState<string | null>(null);

  const { data: serversData } = useQuery({ queryKey: ['servers-for-discover'], queryFn: getServers });
  const servers = serversData?.data?.data ?? [];

  const { data, isLoading, isFetching } = useQuery({
    queryKey: ['subdomains', serverId, debouncedSearch],
    queryFn: () => getSubdomains({ server_id: serverId || undefined, search: debouncedSearch || undefined }),
    staleTime: 60_000,
  });
  const rows = data?.data?.data ?? [];
  const errors = data?.data?.errors ?? [];
  const linked = rows.filter((r) => r.client).length;

  return (
    <Stack gap="md">
      <Title order={3}>
        <Group gap="xs"><IconSitemap size={22} /> Subdomains</Group>
      </Title>

      <Text size="sm" c="dimmed">
        Every subdomain that exists across the WHM server(s), pulled straight from the server — not
        limited to accounts already tracked here.
      </Text>

      <SimpleGrid cols={{ base: 2, sm: 2 }}>
        <StatCard label="Total Subdomains" value={isLoading ? '—' : rows.length}
          icon={<IconSitemap size={20} />} color="blue" />
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
          <Center py="xl"><Text c="dimmed">{isFetching ? 'Refreshing…' : 'No subdomains found.'}</Text></Center>
        ) : (
          <Table.ScrollContainer minWidth={900}>
            <Table striped highlightOnHover verticalSpacing="xs">
              <Table.Thead>
                <Table.Tr>
                  <Table.Th w={48}>#</Table.Th>
                  <Table.Th>Subdomain</Table.Th>
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
