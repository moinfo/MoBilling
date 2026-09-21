import { useMemo, useState } from 'react';
import {
  Stack, Paper, Title, Text, Group, Table, Select, Center, Loader, Alert,
  Button, Modal, TextInput, NumberInput, PasswordInput, ActionIcon, Checkbox, Badge,
} from '@mantine/core';
import { useForm } from '@mantine/form';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { modals } from '@mantine/modals';
import { notifications } from '@mantine/notifications';
import { IconServer2, IconAlertTriangle, IconPlus, IconKey, IconTrash } from '@tabler/icons-react';
import {
  discoverHostingAccounts, getFtpAccounts, addFtpAccount, updateFtpAccountPassword, deleteFtpAccount,
  DiscoveredAccount, FtpAccountRow,
} from '../api/hosting';
import { usePermissions } from '../hooks/usePermissions';

interface AddFormValues {
  user: string;
  password: string;
  homedir: string;
  quota_mb: number;
}

export default function FtpAccounts() {
  const { can } = usePermissions();
  const canManage = can('hosting.change_package');
  const canDelete = can('hosting.terminate');
  const qc = useQueryClient();
  const [selected, setSelected] = useState<string | null>(null);
  const [addOpen, setAddOpen] = useState(false);
  const [pwFor, setPwFor] = useState<FtpAccountRow | null>(null);
  const [newPassword, setNewPassword] = useState('');

  const { data: accountsData, isLoading: accountsLoading } = useQuery({
    queryKey: ['discover-hosting', undefined, 'all'],
    queryFn: () => discoverHostingAccounts({}),
    staleTime: 60_000,
  });
  const accounts: DiscoveredAccount[] = accountsData?.data?.data ?? [];

  const options = useMemo(() => accounts
    .slice()
    .sort((a, b) => (a.domain ?? '').localeCompare(b.domain ?? ''))
    .map((a) => ({
      value: `${a.server_id}|${a.cpanel_username}`,
      label: `${a.domain ?? a.cpanel_username}${a.client ? ` — ${a.client.name}` : ''}`,
    })), [accounts]);

  const [serverId, cpanelUsername] = selected ? selected.split('|') : [null, null];

  const { data: ftpData, isLoading: ftpLoading, isError } = useQuery({
    queryKey: ['ftp-accounts', serverId, cpanelUsername],
    queryFn: () => getFtpAccounts({ server_id: serverId!, cpanel_username: cpanelUsername! }),
    enabled: !!serverId && !!cpanelUsername,
  });
  const rows = ftpData?.data?.data ?? [];

  const form = useForm<AddFormValues>({
    initialValues: { user: '', password: '', homedir: 'public_html', quota_mb: 100 },
    validate: {
      user: (v) => (/^[a-zA-Z0-9_.-]+$/.test(v.trim()) ? null : 'Letters, numbers, . _ - only'),
      password: (v) => (v.length >= 8 ? null : 'At least 8 characters'),
      homedir: (v) => (v.trim() ? null : 'Required'),
    },
  });

  const openAdd = () => { form.reset(); form.setFieldValue('homedir', 'public_html'); setAddOpen(true); };

  const addMutation = useMutation({
    mutationFn: (v: AddFormValues) => addFtpAccount({
      server_id: serverId!, cpanel_username: cpanelUsername!,
      user: v.user.trim(), password: v.password, homedir: v.homedir.trim(), quota_mb: v.quota_mb,
    }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['ftp-accounts', serverId, cpanelUsername] });
      notifications.show({ title: 'Created', message: 'FTP account created.', color: 'green' });
      setAddOpen(false);
    },
    onError: (e: any) => notifications.show({ title: 'Error', message: e?.response?.data?.message ?? 'Failed to create the FTP account.', color: 'red' }),
  });

  const pwMutation = useMutation({
    mutationFn: () => updateFtpAccountPassword({ server_id: serverId!, cpanel_username: cpanelUsername!, user: pwFor!.user, password: newPassword }),
    onSuccess: () => {
      notifications.show({ title: 'Updated', message: `Password changed for ${pwFor?.user}.`, color: 'green' });
      setPwFor(null);
      setNewPassword('');
    },
    onError: (e: any) => notifications.show({ title: 'Error', message: e?.response?.data?.message ?? 'Failed to change the password.', color: 'red' }),
  });

  const deleteMutation = useMutation({
    mutationFn: ({ user, destroyFiles }: { user: string; destroyFiles: boolean }) =>
      deleteFtpAccount({ server_id: serverId!, cpanel_username: cpanelUsername!, user, destroy_files: destroyFiles }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['ftp-accounts', serverId, cpanelUsername] });
      notifications.show({ title: 'Deleted', message: 'FTP account removed.', color: 'green' });
    },
    onError: (e: any) => notifications.show({ title: 'Error', message: e?.response?.data?.message ?? 'Failed to delete the FTP account.', color: 'red' }),
  });

  const confirmDelete = (row: FtpAccountRow) => {
    let destroyFiles = false;
    modals.openConfirmModal({
      title: 'Delete FTP account',
      children: (
        <Stack gap="xs">
          <Text size="sm">Remove FTP access for <Text span fw={600}>{row.user}</Text>?</Text>
          <Checkbox label="Also delete its files" color="red"
            onChange={(e) => { destroyFiles = e.currentTarget.checked; }} />
        </Stack>
      ),
      labels: { confirm: 'Delete', cancel: 'Cancel' },
      confirmProps: { color: 'red' },
      onConfirm: () => deleteMutation.mutate({ user: row.user, destroyFiles }),
    });
  };

  return (
    <Stack gap="md">
      <Group justify="space-between">
        <Title order={3}>
          <Group gap="xs"><IconServer2 size={22} /> FTP Accounts</Group>
        </Title>
        {canManage && (
          <Button leftSection={<IconPlus size={16} />} onClick={openAdd} disabled={!cpanelUsername}>
            Add FTP Account
          </Button>
        )}
      </Group>

      <Text size="sm" c="dimmed">
        Pick a hosting account to see and manage its FTP accounts directly, without needing to log into cPanel.
      </Text>

      <Paper withBorder p="sm" radius="sm">
        <Select
          label="Hosting account" placeholder="Search domain or client…" searchable clearable
          data={options} value={selected} onChange={setSelected}
          disabled={accountsLoading}
          rightSection={accountsLoading ? <Loader size="xs" /> : undefined}
          maw={500}
        />
      </Paper>

      {selected && (
        <Paper withBorder radius="sm">
          {ftpLoading ? (
            <Center py="xl"><Loader /></Center>
          ) : isError ? (
            <Alert color="red" variant="light" icon={<IconAlertTriangle size={16} />} m="sm">
              Could not load FTP accounts for {cpanelUsername}.
            </Alert>
          ) : rows.length === 0 ? (
            <Center py="xl"><Text c="dimmed">No FTP accounts for {cpanelUsername}.</Text></Center>
          ) : (
            <Table.ScrollContainer minWidth={600}>
              <Table striped highlightOnHover verticalSpacing="xs">
                <Table.Thead>
                  <Table.Tr>
                    <Table.Th>User</Table.Th>
                    <Table.Th>Directory</Table.Th>
                    {(canManage || canDelete) && <Table.Th w={110}></Table.Th>}
                  </Table.Tr>
                </Table.Thead>
                <Table.Tbody>
                  {rows.map((r) => (
                    <Table.Tr key={r.user}>
                      <Table.Td fz="sm">
                        {r.user}
                        {r.type === 'main' && <Badge ml={6} size="xs" variant="light" color="blue">Main</Badge>}
                      </Table.Td>
                      <Table.Td fz="sm" c="dimmed" style={{ fontFamily: 'monospace' }}>{r.homedir}</Table.Td>
                      {(canManage || canDelete) && (
                        <Table.Td>
                          <Group gap={4}>
                            {canManage && (
                              <ActionIcon variant="subtle" onClick={() => { setPwFor(r); setNewPassword(''); }}>
                                <IconKey size={16} />
                              </ActionIcon>
                            )}
                            {canDelete && r.type !== 'main' && (
                              <ActionIcon variant="subtle" color="red" onClick={() => confirmDelete(r)}>
                                <IconTrash size={16} />
                              </ActionIcon>
                            )}
                          </Group>
                        </Table.Td>
                      )}
                    </Table.Tr>
                  ))}
                </Table.Tbody>
              </Table>
            </Table.ScrollContainer>
          )}
        </Paper>
      )}

      <Modal opened={addOpen} onClose={() => setAddOpen(false)} title={`Add FTP Account — ${cpanelUsername ?? ''}`} size="md">
        <form onSubmit={form.onSubmit((v) => addMutation.mutate(v))}>
          <Stack>
            <TextInput label="Username" required placeholder="uploads" {...form.getInputProps('user')} />
            <PasswordInput label="Password" required description="cPanel requires a strong password"
              {...form.getInputProps('password')} />
            <TextInput label="Directory" required description="Relative to the account's home directory"
              placeholder="public_html/uploads" {...form.getInputProps('homedir')} />
            <NumberInput label="Quota (MB)" description="0 = unlimited" min={0} {...form.getInputProps('quota_mb')} />
            <Group justify="flex-end">
              <Button variant="default" onClick={() => setAddOpen(false)}>Cancel</Button>
              <Button type="submit" loading={addMutation.isPending}>Add FTP Account</Button>
            </Group>
          </Stack>
        </form>
      </Modal>

      <Modal opened={!!pwFor} onClose={() => setPwFor(null)} title={`Change Password — ${pwFor?.user ?? ''}`} size="sm">
        <Stack>
          <PasswordInput label="New password" description="cPanel requires a strong password"
            value={newPassword} onChange={(e) => setNewPassword(e.currentTarget.value)} />
          <Group justify="flex-end">
            <Button variant="default" onClick={() => setPwFor(null)}>Cancel</Button>
            <Button disabled={newPassword.length < 8} loading={pwMutation.isPending} onClick={() => pwMutation.mutate()}>
              Change Password
            </Button>
          </Group>
        </Stack>
      </Modal>
    </Stack>
  );
}
