import { useMemo, useState } from 'react';
import {
  Stack, Paper, Title, Text, Group, Badge, Table, Select, Center, Loader, Alert,
} from '@mantine/core';
import { useQuery } from '@tanstack/react-query';
import { IconMailbox, IconAlertTriangle } from '@tabler/icons-react';
import { discoverHostingAccounts, getEmailAccounts, DiscoveredAccount } from '../api/hosting';

/**
 * Email accounts for one cPanel account, picked by domain/username first —
 * WHM has no bulk call for this (unlike Bandwidth/Disk/Backup, which are
 * one call for the whole server), so it deliberately doesn't try to load
 * every account's mailboxes at once.
 */
export default function EmailAccounts() {
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

  const { data: emailsData, isLoading: emailsLoading, isError } = useQuery({
    queryKey: ['email-accounts', serverId, cpanelUsername],
    queryFn: () => getEmailAccounts({ server_id: serverId!, cpanel_username: cpanelUsername! }),
    enabled: !!serverId && !!cpanelUsername,
  });
  const emails = emailsData?.data?.data ?? [];

  return (
    <Stack gap="md">
      <Title order={3}>
        <Group gap="xs"><IconMailbox size={22} /> Email Accounts</Group>
      </Title>

      <Text size="sm" c="dimmed">
        Pick a hosting account to see its mailboxes — WHM only exposes this one account at a time,
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
          {emailsLoading ? (
            <Center py="xl"><Loader /></Center>
          ) : isError ? (
            <Alert color="red" variant="light" icon={<IconAlertTriangle size={16} />} m="sm">
              Could not load email accounts for {selectedAccount?.domain ?? cpanelUsername}.
            </Alert>
          ) : emails.length === 0 ? (
            <Center py="xl"><Text c="dimmed">No email accounts found for {selectedAccount?.domain ?? cpanelUsername}.</Text></Center>
          ) : (
            <Table striped highlightOnHover verticalSpacing="xs">
              <Table.Thead>
                <Table.Tr>
                  <Table.Th w={48}>#</Table.Th>
                  <Table.Th>Email</Table.Th>
                  <Table.Th>Status</Table.Th>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {emails.map((e, i) => {
                  const suspended = e.suspended_incoming || e.suspended_login;
                  return (
                    <Table.Tr key={e.email}>
                      <Table.Td c="dimmed">{i + 1}</Table.Td>
                      <Table.Td fw={500}>{e.email}</Table.Td>
                      <Table.Td>
                        {suspended ? (
                          <Badge size="sm" variant="light" color="orange">
                            {e.suspended_login ? 'Login suspended' : 'Incoming suspended'}
                          </Badge>
                        ) : (
                          <Badge size="sm" variant="light" color="teal">Active</Badge>
                        )}
                      </Table.Td>
                    </Table.Tr>
                  );
                })}
              </Table.Tbody>
            </Table>
          )}
        </Paper>
      )}
    </Stack>
  );
}
