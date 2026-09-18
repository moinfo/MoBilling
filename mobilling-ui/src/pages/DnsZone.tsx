import { useMemo, useState } from 'react';
import {
  Stack, Paper, Title, Text, Group, Badge, Table, Select, Center, Loader, Alert,
} from '@mantine/core';
import { useQuery } from '@tanstack/react-query';
import { IconWorldWww, IconAlertTriangle } from '@tabler/icons-react';
import { discoverHostingAccounts, getDnsZone, DiscoveredAccount } from '../api/hosting';

const typeColors: Record<string, string> = {
  A: 'blue', AAAA: 'blue', CNAME: 'grape', MX: 'orange', TXT: 'teal',
  NS: 'gray', SOA: 'gray', SRV: 'violet',
};

/**
 * A domain's DNS zone, read-only for now — view only, no editing yet
 * (mass_edit_dns_zone/editzonerecord exist and would add that later).
 * WHM's parse_dns_zone is per-domain, so this picks a domain the same
 * search-first way Email Accounts/MySQL Databases pick a cPanel account.
 */
export default function DnsZone() {
  const [selected, setSelected] = useState<string | null>(null);

  const { data: accountsData, isLoading: accountsLoading } = useQuery({
    queryKey: ['discover-hosting', undefined, 'all'],
    queryFn: () => discoverHostingAccounts({}),
    staleTime: 60_000,
  });
  const accounts: DiscoveredAccount[] = accountsData?.data?.data ?? [];

  const options = useMemo(() => accounts
    .filter((a) => a.domain)
    .slice()
    .sort((a, b) => (a.domain ?? '').localeCompare(b.domain ?? ''))
    .map((a) => ({
      value: `${a.server_id}|${a.domain}`,
      label: `${a.domain}${a.client ? ` — ${a.client.name}` : ''}`,
    })), [accounts]);

  const [serverId, domain] = selected ? selected.split('|') : [null, null];

  const { data: zoneData, isLoading: zoneLoading, isError } = useQuery({
    queryKey: ['dns-zone', serverId, domain],
    queryFn: () => getDnsZone({ server_id: serverId!, domain: domain! }),
    enabled: !!serverId && !!domain,
  });
  const records = zoneData?.data?.data ?? [];

  return (
    <Stack gap="md">
      <Title order={3}>
        <Group gap="xs"><IconWorldWww size={22} /> DNS Zone</Group>
      </Title>

      <Text size="sm" c="dimmed">
        Pick a domain to see its DNS zone straight from WHM — view only for now, no editing here yet.
      </Text>

      <Paper withBorder p="sm" radius="sm">
        <Select
          label="Domain" placeholder="Search domain or client…" searchable clearable
          data={options} value={selected} onChange={setSelected}
          disabled={accountsLoading}
          rightSection={accountsLoading ? <Loader size="xs" /> : undefined}
          maw={500}
        />
      </Paper>

      {selected && (
        <Paper withBorder radius="sm">
          {zoneLoading ? (
            <Center py="xl"><Loader /></Center>
          ) : isError ? (
            <Alert color="red" variant="light" icon={<IconAlertTriangle size={16} />} m="sm">
              Could not load the DNS zone for {domain}.
            </Alert>
          ) : records.length === 0 ? (
            <Center py="xl"><Text c="dimmed">No records found for {domain}.</Text></Center>
          ) : (
            <Table.ScrollContainer minWidth={800}>
              <Table striped highlightOnHover verticalSpacing="xs">
                <Table.Thead>
                  <Table.Tr>
                    <Table.Th w={48}>#</Table.Th>
                    <Table.Th>Type</Table.Th>
                    <Table.Th>Name</Table.Th>
                    <Table.Th>TTL</Table.Th>
                    <Table.Th>Value</Table.Th>
                  </Table.Tr>
                </Table.Thead>
                <Table.Tbody>
                  {records.map((r, i) => (
                    <Table.Tr key={i}>
                      <Table.Td c="dimmed">{i + 1}</Table.Td>
                      <Table.Td>
                        <Badge size="sm" variant="light" color={typeColors[r.type] ?? 'dark'}>{r.type}</Badge>
                      </Table.Td>
                      <Table.Td fw={500} fz="sm">{r.name}</Table.Td>
                      <Table.Td fz="sm" c="dimmed">{r.ttl}</Table.Td>
                      <Table.Td fz="sm" style={{ wordBreak: 'break-all' }}>{r.data.join('  ·  ')}</Table.Td>
                    </Table.Tr>
                  ))}
                </Table.Tbody>
              </Table>
            </Table.ScrollContainer>
          )}
        </Paper>
      )}
    </Stack>
  );
}
