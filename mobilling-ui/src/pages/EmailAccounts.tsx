import { useMemo, useState } from 'react';
import {
  Stack, Paper, Title, Text, Group, Badge, Table, Select, Center, Loader, Alert,
  ActionIcon, Tooltip, Modal, PasswordInput, Button,
} from '@mantine/core';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { modals } from '@mantine/modals';
import { notifications } from '@mantine/notifications';
import {
  IconMailbox, IconAlertTriangle, IconKey, IconLock, IconLockOpen, IconTrash,
} from '@tabler/icons-react';
import {
  discoverHostingAccounts, getEmailAccounts, changeEmailAccountPassword,
  toggleEmailAccountSuspension, deleteEmailAccount, DiscoveredAccount, EmailAccountRow,
} from '../api/hosting';
import { usePermissions } from '../hooks/usePermissions';

const fmtBytes = (bytes: number) => {
  if (bytes <= 0) return '0 MB';
  const gb = bytes / 1_073_741_824;
  return gb >= 1 ? `${gb.toFixed(2)} GB` : `${(bytes / 1_048_576).toFixed(0)} MB`;
};

/**
 * Email accounts for one cPanel account, picked by domain/username first —
 * WHM has no bulk call for this (unlike Bandwidth/Disk/Backup, which are
 * one call for the whole server), so it deliberately doesn't try to load
 * every account's mailboxes at once.
 */
export default function EmailAccounts() {
  const { can } = usePermissions();
  const qc = useQueryClient();
  const [selected, setSelected] = useState<string | null>(null);
  const [pwFor, setPwFor] = useState<EmailAccountRow | null>(null);

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

  const invalidate = () => qc.invalidateQueries({ queryKey: ['email-accounts', serverId, cpanelUsername] });

  const suspendMutation = useMutation({
    mutationFn: (vars: { email: string; suspend: boolean }) =>
      toggleEmailAccountSuspension({ server_id: serverId!, cpanel_username: cpanelUsername!, email: vars.email, suspend: vars.suspend }),
    onSuccess: (res) => { notifications.show({ message: res.data.message, color: 'green' }); invalidate(); },
    onError: (e: any) => notifications.show({ message: e?.response?.data?.message ?? 'Action failed.', color: 'red' }),
  });

  const deleteMutation = useMutation({
    mutationFn: (row: EmailAccountRow) =>
      deleteEmailAccount({ server_id: serverId!, cpanel_username: cpanelUsername!, email: row.email!, domain: selectedAccount!.domain! }),
    onSuccess: (res) => { notifications.show({ message: res.data.message, color: 'gray' }); invalidate(); },
    onError: (e: any) => notifications.show({ message: e?.response?.data?.message ?? 'Delete failed.', color: 'red' }),
  });

  const handleDelete = (row: EmailAccountRow) => modals.openConfirmModal({
    title: 'Delete Mailbox',
    children: <Text size="sm">This <Text span fw={700} c="red">permanently deletes</Text> the mailbox{' '}
      <Text span fw={600}>{row.email}</Text> and everything in it. This cannot be undone.</Text>,
    labels: { confirm: 'Delete', cancel: 'Cancel' },
    confirmProps: { color: 'red' },
    onConfirm: () => deleteMutation.mutate(row),
  });

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
            <Table.ScrollContainer minWidth={700}>
              <Table striped highlightOnHover verticalSpacing="xs">
                <Table.Thead>
                  <Table.Tr>
                    <Table.Th w={48}>#</Table.Th>
                    <Table.Th>Email</Table.Th>
                    <Table.Th>Size</Table.Th>
                    <Table.Th>Status</Table.Th>
                    {(can('hosting.change_package') || can('hosting.suspend') || can('hosting.terminate')) && (
                      <Table.Th w={120}>Actions</Table.Th>
                    )}
                  </Table.Tr>
                </Table.Thead>
                <Table.Tbody>
                  {emails.map((e, i) => {
                    const suspended = e.suspended_incoming || e.suspended_login;
                    return (
                      <Table.Tr key={e.email}>
                        <Table.Td c="dimmed">{i + 1}</Table.Td>
                        <Table.Td fw={500}>{e.email}</Table.Td>
                        <Table.Td fz="sm" c="dimmed">
                          {fmtBytes(e.used_bytes)}{e.quota_bytes ? ` / ${fmtBytes(e.quota_bytes)}` : ' / Unlimited'}
                        </Table.Td>
                        <Table.Td>
                          {suspended ? (
                            <Badge size="sm" variant="light" color="orange">
                              {e.suspended_login ? 'Login suspended' : 'Incoming suspended'}
                            </Badge>
                          ) : (
                            <Badge size="sm" variant="light" color="teal">Active</Badge>
                          )}
                        </Table.Td>
                        {(can('hosting.change_package') || can('hosting.suspend') || can('hosting.terminate')) && (
                          <Table.Td>
                            <Group gap={4} wrap="nowrap">
                              {can('hosting.change_package') && (
                                <Tooltip label="Change password">
                                  <ActionIcon variant="light" size="sm" onClick={() => setPwFor(e)}>
                                    <IconKey size={14} />
                                  </ActionIcon>
                                </Tooltip>
                              )}
                              {can('hosting.suspend') && (
                                <Tooltip label={e.suspended_login ? 'Unsuspend login' : 'Suspend login'}>
                                  <ActionIcon
                                    variant="light" size="sm" color={e.suspended_login ? 'green' : 'orange'}
                                    loading={suspendMutation.isPending}
                                    onClick={() => suspendMutation.mutate({ email: e.email!, suspend: !e.suspended_login })}
                                  >
                                    {e.suspended_login ? <IconLockOpen size={14} /> : <IconLock size={14} />}
                                  </ActionIcon>
                                </Tooltip>
                              )}
                              {can('hosting.terminate') && (
                                <Tooltip label="Delete mailbox">
                                  <ActionIcon variant="light" size="sm" color="red" onClick={() => handleDelete(e)}>
                                    <IconTrash size={14} />
                                  </ActionIcon>
                                </Tooltip>
                              )}
                            </Group>
                          </Table.Td>
                        )}
                      </Table.Tr>
                    );
                  })}
                </Table.Tbody>
              </Table>
            </Table.ScrollContainer>
          )}
        </Paper>
      )}

      <ChangeEmailPasswordModal
        row={pwFor} onClose={() => setPwFor(null)}
        serverId={serverId} cpanelUsername={cpanelUsername}
        onChanged={invalidate}
      />
    </Stack>
  );
}

function ChangeEmailPasswordModal({ row, onClose, serverId, cpanelUsername, onChanged }: {
  row: EmailAccountRow | null; onClose: () => void;
  serverId: string | null; cpanelUsername: string | null; onChanged: () => void;
}) {
  const [pw, setPw] = useState('');
  const mutation = useMutation({
    mutationFn: () => changeEmailAccountPassword({ server_id: serverId!, cpanel_username: cpanelUsername!, email: row!.email!, password: pw }),
    onSuccess: (res) => { notifications.show({ message: res.data.message, color: 'green' }); setPw(''); onChanged(); onClose(); },
    onError: (e: any) => notifications.show({ message: e?.response?.data?.message ?? 'Change failed.', color: 'red' }),
  });
  const handleClose = () => { setPw(''); onClose(); };
  return (
    <Modal opened={!!row} onClose={handleClose} title={`Change Password — ${row?.email ?? ''}`} centered size="sm">
      <Stack>
        <PasswordInput label="New Password" value={pw} onChange={(e) => setPw(e.currentTarget.value)}
          description="Pushed to the server immediately — cPanel enforces its own strength check." />
        <Group justify="flex-end">
          <Button variant="default" onClick={handleClose}>Cancel</Button>
          <Button color="orange" disabled={pw.length < 8} loading={mutation.isPending} onClick={() => mutation.mutate()}>
            Change Password
          </Button>
        </Group>
      </Stack>
    </Modal>
  );
}
