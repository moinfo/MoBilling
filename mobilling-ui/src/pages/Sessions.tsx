import { useState } from 'react';
import {
  Stack, Paper, Title, Text, Group, Badge, Table, TextInput, Select,
  ActionIcon, Center, Loader, Tooltip, Button, SimpleGrid, ThemeIcon,
} from '@mantine/core';
import { useDebouncedValue } from '@mantine/hooks';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { notifications } from '@mantine/notifications';
import { modals } from '@mantine/modals';
import {
  IconShieldLock, IconSearch, IconLogout2, IconClockOff, IconUserOff, IconListNumbers,
} from '@tabler/icons-react';
import { getSessions, revokeSession, revokeInactiveSessions, SessionRow } from '../api/sessions';
import { formatDate } from '../utils/formatDate';

/**
 * Every active session (Sanctum token), staff and client-portal alike — the
 * only place to see this, since tokens never expire on their own
 * (config/sanctum.php) and deactivating an account only blocks future logins,
 * not sessions already issued.
 */
export default function Sessions() {
  const qc = useQueryClient();
  const [search, setSearch] = useState('');
  const [debouncedSearch] = useDebouncedValue(search, 300);
  const [type, setType] = useState<string | null>(null);
  const [status, setStatus] = useState<string | null>(null);

  const { data, isLoading } = useQuery({
    queryKey: ['sessions', debouncedSearch, type, status],
    queryFn: () => getSessions({
      search: debouncedSearch || undefined,
      type: (type as 'staff' | 'client') || undefined,
      status: status === '' ? undefined : status === '1' ? 1 : status === '0' ? 0 : undefined,
    }),
  });

  const rows = data?.data?.data ?? [];
  const summary = data?.data?.summary;
  const invalidate = () => qc.invalidateQueries({ queryKey: ['sessions'] });

  const revokeMut = useMutation({
    mutationFn: (id: number) => revokeSession(id),
    onSuccess: () => { notifications.show({ message: 'Session revoked.', color: 'green' }); invalidate(); },
    onError: (e: any) => notifications.show({ message: e?.response?.data?.message ?? 'Could not revoke.', color: 'red' }),
  });

  const bulkMut = useMutation({
    mutationFn: (includeNeverUsed: boolean) => revokeInactiveSessions(includeNeverUsed),
    onSuccess: (res) => { notifications.show({ title: 'Cleaned up', message: res.data.message, color: 'green', autoClose: 8000 }); invalidate(); },
    onError: (e: any) => notifications.show({ message: e?.response?.data?.message ?? 'Could not clean up.', color: 'red' }),
  });

  const confirmRevoke = (r: SessionRow) => {
    modals.openConfirmModal({
      title: 'Revoke Session',
      children: <Text size="sm">Force {r.owner_name} to log in again on this device? They'll be signed out immediately.</Text>,
      labels: { confirm: 'Revoke', cancel: 'Cancel' },
      confirmProps: { color: 'red' },
      onConfirm: () => revokeMut.mutate(r.id),
    });
  };

  const confirmBulk = () => {
    modals.openConfirmModal({
      title: 'Revoke Sessions on Deactivated Accounts',
      children: (
        <Stack gap="xs">
          <Text size="sm">
            This signs out every session belonging to a deactivated staff account or an inactive client
            — {summary?.on_inactive ?? 0} session(s) right now. Sessions on active accounts are never touched.
          </Text>
        </Stack>
      ),
      labels: { confirm: 'Revoke deactivated only', cancel: 'Cancel' },
      confirmProps: { color: 'orange' },
      onConfirm: () => bulkMut.mutate(false),
    });
  };

  return (
    <Stack gap="md">
      <Group justify="space-between">
        <Title order={3}>
          <Group gap="xs"><IconShieldLock size={22} /> Active Sessions</Group>
        </Title>
        <Button variant="light" color="orange" leftSection={<IconUserOff size={15} />}
          disabled={!summary?.on_inactive} loading={bulkMut.isPending} onClick={confirmBulk}>
          Revoke sessions on deactivated accounts
        </Button>
      </Group>

      {summary && (
        <SimpleGrid cols={{ base: 1, sm: 3 }}>
          <Paper withBorder p="sm" radius="sm">
            <Group gap="xs">
              <ThemeIcon variant="light" color="blue" size={32}><IconListNumbers size={16} /></ThemeIcon>
              <div><Text size="xs" c="dimmed">Total sessions</Text><Text fw={700}>{summary.total}</Text></div>
            </Group>
          </Paper>
          <Paper withBorder p="sm" radius="sm">
            <Group gap="xs">
              <ThemeIcon variant="light" color="orange" size={32}><IconUserOff size={16} /></ThemeIcon>
              <div><Text size="xs" c="dimmed">On deactivated accounts</Text><Text fw={700} c={summary.on_inactive > 0 ? 'orange' : undefined}>{summary.on_inactive}</Text></div>
            </Group>
          </Paper>
          <Paper withBorder p="sm" radius="sm">
            <Group gap="xs">
              <ThemeIcon variant="light" color="gray" size={32}><IconClockOff size={16} /></ThemeIcon>
              <div><Text size="xs" c="dimmed">Never used</Text><Text fw={700}>{summary.never_used}</Text></div>
            </Group>
          </Paper>
        </SimpleGrid>
      )}

      <Paper withBorder p="sm" radius="sm">
        <Group gap="sm" wrap="wrap">
          <TextInput
            placeholder="Search name, email, or client…" leftSection={<IconSearch size={14} />}
            value={search} onChange={(e) => setSearch(e.currentTarget.value)}
            style={{ flex: 1, minWidth: 240 }}
          />
          <Select placeholder="Type" clearable w={140} value={type} onChange={setType}
            data={[{ value: 'staff', label: 'Staff' }, { value: 'client', label: 'Client portal' }]} />
          <Select placeholder="Account status" clearable w={170} value={status} onChange={setStatus}
            data={[{ value: '1', label: 'Active' }, { value: '0', label: 'Deactivated' }]} />
        </Group>
      </Paper>

      <Paper withBorder radius="sm">
        {isLoading ? (
          <Center py="xl"><Loader /></Center>
        ) : rows.length === 0 ? (
          <Center py="xl"><Text c="dimmed">No sessions found.</Text></Center>
        ) : (
          <Table.ScrollContainer minWidth={800}>
            <Table striped highlightOnHover verticalSpacing="xs">
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>Owner</Table.Th>
                  <Table.Th>Type</Table.Th>
                  <Table.Th>Client</Table.Th>
                  <Table.Th>Status</Table.Th>
                  <Table.Th>Last used</Table.Th>
                  <Table.Th>Created</Table.Th>
                  <Table.Th>Action</Table.Th>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {rows.map((r) => (
                  <Table.Tr key={r.id}>
                    <Table.Td>
                      <Text fw={500} size="sm">{r.owner_name}</Text>
                      <Text size="xs" c="dimmed">{r.owner_email}</Text>
                    </Table.Td>
                    <Table.Td>
                      <Badge size="sm" variant="light" color={r.owner_type === 'staff' ? 'blue' : 'grape'}>
                        {r.owner_type === 'staff' ? 'Staff' : 'Client portal'}
                      </Badge>
                    </Table.Td>
                    <Table.Td fz="sm">{r.client_name ?? '—'}</Table.Td>
                    <Table.Td>
                      <Badge size="sm" variant="light" color={r.effectively_active ? 'teal' : 'red'}>
                        {r.effectively_active ? 'Active' : 'Deactivated'}
                      </Badge>
                    </Table.Td>
                    <Table.Td fz="sm" c={r.never_used ? 'orange' : 'dimmed'}>
                      {r.last_used_at ? formatDate(r.last_used_at) : 'Never used'}
                    </Table.Td>
                    <Table.Td fz="sm" c="dimmed">{formatDate(r.created_at)}</Table.Td>
                    <Table.Td>
                      <Tooltip label="Revoke — force sign-out">
                        <ActionIcon variant="subtle" color="red" size="sm" onClick={() => confirmRevoke(r)}>
                          <IconLogout2 size={14} />
                        </ActionIcon>
                      </Tooltip>
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
