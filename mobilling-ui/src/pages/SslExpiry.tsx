import { useState } from 'react';
import {
  Stack, Paper, Title, Text, Group, Badge, Table, TextInput,
  ActionIcon, Center, Loader, SimpleGrid, Switch,
} from '@mantine/core';
import { useDebouncedValue } from '@mantine/hooks';
import { useQuery } from '@tanstack/react-query';
import { useNavigate } from 'react-router-dom';
import { IconLock, IconSearch, IconExternalLink, IconAlertOctagon, IconAlertTriangle } from '@tabler/icons-react';
import dayjs from 'dayjs';
import { getSslExpiry } from '../api/domains';
import StatCard from '../components/Reports/StatCard';

const statusFor = (r: { ssl_valid: boolean; days_left: number | null }) => {
  if (!r.ssl_valid || (r.days_left ?? 0) < 0) return { label: 'Expired', color: 'red' };
  if ((r.days_left ?? 999) <= 14) return { label: `${r.days_left}d left`, color: 'red' };
  if ((r.days_left ?? 999) <= 30) return { label: `${r.days_left}d left`, color: 'orange' };
  if ((r.days_left ?? 999) <= 90) return { label: `${r.days_left}d left`, color: 'yellow' };
  return { label: `${r.days_left}d left`, color: 'teal' };
};

/**
 * Every domain's SSL certificate, soonest-expiring first — reads straight
 * from SyncDomains' nightly SslProbe cache (domains.meta), no live probing
 * on page load.
 */
export default function SslExpiry() {
  const navigate = useNavigate();
  const [search, setSearch] = useState('');
  const [debouncedSearch] = useDebouncedValue(search, 300);
  const [invalidOnly, setInvalidOnly] = useState(false);

  const { data, isLoading, isFetching } = useQuery({
    queryKey: ['ssl-expiry', debouncedSearch, invalidOnly],
    queryFn: () => getSslExpiry({ search: debouncedSearch || undefined, invalid_only: invalidOnly ? 1 : undefined }),
    staleTime: 60_000,
  });
  const rows = data?.data?.data ?? [];
  const expired = rows.filter((r) => !r.ssl_valid || (r.days_left ?? 0) < 0).length;
  const soon = rows.filter((r) => r.ssl_valid && (r.days_left ?? 999) >= 0 && (r.days_left ?? 999) <= 30).length;

  return (
    <Stack gap="md">
      <Title order={3}>
        <Group gap="xs"><IconLock size={22} /> SSL Certificates Expiry</Group>
      </Title>

      <Text size="sm" c="dimmed">
        Every domain's SSL certificate, soonest-expiring first — from the nightly sync, not a live
        check on every page load. Only domains that have ever had a check run are listed here.
      </Text>

      <SimpleGrid cols={{ base: 2, sm: 3 }}>
        <StatCard label="Total Checked" value={isLoading ? '—' : rows.length}
          icon={<IconLock size={20} />} color="blue" />
        <StatCard label="Expiring ≤30 Days" value={isLoading ? '—' : soon}
          icon={<IconAlertTriangle size={20} />} color="orange" />
        <StatCard label="Expired / Invalid" value={isLoading ? '—' : expired}
          icon={<IconAlertOctagon size={20} />} color="red" />
      </SimpleGrid>

      <Paper withBorder p="sm" radius="sm">
        <Group gap="sm" wrap="wrap">
          <TextInput
            placeholder="Search domain or client…" leftSection={<IconSearch size={14} />}
            value={search} onChange={(e) => setSearch(e.currentTarget.value)}
            style={{ flex: 1, minWidth: 280 }}
          />
          <Switch label="Expired/invalid only" checked={invalidOnly} onChange={(e) => setInvalidOnly(e.currentTarget.checked)} />
        </Group>
      </Paper>

      <Paper withBorder radius="sm">
        {isLoading ? (
          <Center py="xl"><Loader /></Center>
        ) : rows.length === 0 ? (
          <Center py="xl"><Text c="dimmed">{isFetching ? 'Refreshing…' : 'No domains found.'}</Text></Center>
        ) : (
          <Table.ScrollContainer minWidth={800}>
            <Table striped highlightOnHover verticalSpacing="xs">
              <Table.Thead>
                <Table.Tr>
                  <Table.Th w={48}>#</Table.Th>
                  <Table.Th>Domain</Table.Th>
                  <Table.Th>Issuer</Table.Th>
                  <Table.Th>Expires</Table.Th>
                  <Table.Th>Status</Table.Th>
                  <Table.Th>Client</Table.Th>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {rows.map((r, i) => {
                  const s = statusFor(r);
                  return (
                    <Table.Tr key={r.id}>
                      <Table.Td c="dimmed">{i + 1}</Table.Td>
                      <Table.Td fw={500}>{r.name}</Table.Td>
                      <Table.Td fz="sm" c="dimmed">{r.ssl_issuer ?? '—'}</Table.Td>
                      <Table.Td fz="sm" c="dimmed">{r.ssl_expires_at ? dayjs(r.ssl_expires_at).format('D MMM YYYY') : '—'}</Table.Td>
                      <Table.Td>
                        <Badge size="sm" variant="light" color={s.color}>{s.label}</Badge>
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
                  );
                })}
              </Table.Tbody>
            </Table>
          </Table.ScrollContainer>
        )}
      </Paper>
    </Stack>
  );
}
