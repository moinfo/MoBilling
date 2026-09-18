import { useMemo, useState } from 'react';
import {
  Stack, Paper, Title, Text, Group, Badge, Table, Select, Center, Loader, Alert,
} from '@mantine/core';
import { useQuery } from '@tanstack/react-query';
import { IconDatabase, IconAlertTriangle } from '@tabler/icons-react';
import { discoverHostingAccounts, getMysqlDatabases, DiscoveredAccount } from '../api/hosting';

const fmtBytes = (bytes: number) => {
  if (bytes <= 0) return '0 KB';
  const mb = bytes / 1_048_576;
  return mb >= 1 ? `${mb.toFixed(2)} MB` : `${(bytes / 1024).toFixed(0)} KB`;
};

/**
 * MySQL databases for one cPanel account, picked by domain/username first —
 * same reason as Email Accounts: WHM has no bulk call for this, only a
 * per-account "cpanel" UAPI passthrough (Mysql::list_databases).
 */
export default function MysqlDatabases() {
  const [selected, setSelected] = useState<string | null>(null);

  const { data: accountsData, isLoading: accountsLoading } = useQuery({
    queryKey: ['discover-hosting', undefined, 'all'],
    queryFn: () => discoverHostingAccounts({}),
    staleTime: 60_000,
  });
  const accounts: DiscoveredAccount[] = accountsData?.data?.data ?? [];

  const options = useMemo(() => accounts
    .slice()
    .sort((a, b) => (a.domain ?? a.cpanel_username).localeCompare(b.domain ?? b.cpanel_username))
    .map((a) => ({
      value: `${a.server_id}|${a.cpanel_username}`,
      label: `${a.domain ?? a.cpanel_username}${a.client ? ` — ${a.client.name}` : ''}`,
    })), [accounts]);

  const [serverId, cpanelUsername] = selected ? selected.split('|') : [null, null];
  const selectedAccount = accounts.find((a) => a.server_id === serverId && a.cpanel_username === cpanelUsername);

  const { data: dbsData, isLoading: dbsLoading, isError } = useQuery({
    queryKey: ['mysql-databases', serverId, cpanelUsername],
    queryFn: () => getMysqlDatabases({ server_id: serverId!, cpanel_username: cpanelUsername! }),
    enabled: !!serverId && !!cpanelUsername,
  });
  const dbs = dbsData?.data?.data ?? [];

  return (
    <Stack gap="md">
      <Title order={3}>
        <Group gap="xs"><IconDatabase size={22} /> MySQL Databases</Group>
      </Title>

      <Text size="sm" c="dimmed">
        Pick a hosting account to see its databases — WHM only exposes this one account at a time,
        so there's no "all accounts" view here.
      </Text>

      <Paper withBorder p="sm" radius="sm">
        <Select
          label="Hosting Account" placeholder="Search domain, username, or client…" searchable clearable
          data={options} value={selected} onChange={setSelected}
          disabled={accountsLoading}
          rightSection={accountsLoading ? <Loader size="xs" /> : undefined}
          maw={500}
        />
      </Paper>

      {selected && (
        <Paper withBorder radius="sm">
          {dbsLoading ? (
            <Center py="xl"><Loader /></Center>
          ) : isError ? (
            <Alert color="red" variant="light" icon={<IconAlertTriangle size={16} />} m="sm">
              Could not load databases for {selectedAccount?.domain ?? cpanelUsername}.
            </Alert>
          ) : dbs.length === 0 ? (
            <Center py="xl"><Text c="dimmed">No databases found for {selectedAccount?.domain ?? cpanelUsername}.</Text></Center>
          ) : (
            <Table striped highlightOnHover verticalSpacing="xs">
              <Table.Thead>
                <Table.Tr>
                  <Table.Th w={48}>#</Table.Th>
                  <Table.Th>Database</Table.Th>
                  <Table.Th>Users</Table.Th>
                  <Table.Th>Disk Usage</Table.Th>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {dbs.map((d, i) => (
                  <Table.Tr key={d.database}>
                    <Table.Td c="dimmed">{i + 1}</Table.Td>
                    <Table.Td fw={500}>{d.database}</Table.Td>
                    <Table.Td>
                      <Group gap={4}>
                        {d.users.map((u) => <Badge key={u} size="sm" variant="light" color="grape">{u}</Badge>)}
                      </Group>
                    </Table.Td>
                    <Table.Td fz="sm" c="dimmed">{fmtBytes(d.disk_usage)}</Table.Td>
                  </Table.Tr>
                ))}
              </Table.Tbody>
            </Table>
          )}
        </Paper>
      )}
    </Stack>
  );
}
