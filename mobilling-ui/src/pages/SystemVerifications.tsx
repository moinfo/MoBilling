import { useState } from 'react';
import {
  Title, Table, Text, Group, Pagination, Badge, ActionIcon, Modal, Button, TextInput, PasswordInput, Stack, Select, Switch, Drawer, Box, ThemeIcon, Paper, SimpleGrid,
} from '@mantine/core';
import { TimeInput } from '@mantine/dates';
import { useForm } from '@mantine/form';
import { useDebouncedValue } from '@mantine/hooks';
import { modals } from '@mantine/modals';
import { notifications } from '@mantine/notifications';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { IconPlus, IconEdit, IconTrash, IconSearch, IconCheck, IconAlertTriangle, IconHistory, IconClock, IconHourglass } from '@tabler/icons-react';
import {
  getSystemVerifications, createSystemVerification, updateSystemVerification, deleteSystemVerification,
  getSystemVerificationReports, getVerificationWindow, updateVerificationWindow,
  SystemVerification, SystemVerificationReport,
} from '../api/systemVerifications';
import { getAssignableUsers } from '../api/users';
import { getClients } from '../api/clients';
import { usePermissions } from '../hooks/usePermissions';
import { formatDate } from '../utils/formatDate';
import dayjs from 'dayjs';

interface UserOption { id: string; name: string }
interface ClientOption { id: string; name: string; email?: string | null }

export default function SystemVerifications() {
  const queryClient = useQueryClient();
  const { can } = usePermissions();
  const canCreate = can('system_verifications.create');
  const canUpdate = can('system_verifications.update');
  const canDelete = can('system_verifications.delete');

  const [page, setPage] = useState(1);
  const [search, setSearch] = useState('');
  const [debouncedSearch] = useDebouncedValue(search, 300);
  const [formOpen, setFormOpen] = useState(false);
  const [editing, setEditing] = useState<SystemVerification | null>(null);
  const [historyFor, setHistoryFor] = useState<SystemVerification | null>(null);
  const canUpdateWindow = canUpdate; // window is admin-config, same ceiling as editing systems

  const { data } = useQuery({
    queryKey: ['system-verifications', page, debouncedSearch],
    queryFn: () => getSystemVerifications({ page, search: debouncedSearch || undefined }),
  });
  const { data: usersData } = useQuery({
    queryKey: ['assignable-users'],
    queryFn: getAssignableUsers,
  });
  const { data: clientsData } = useQuery({
    queryKey: ['clients-all-for-sv'],
    queryFn: () => getClients({ per_page: 500 }),
  });
  const items: SystemVerification[] = data?.data?.data || [];
  const meta = data?.data?.meta;
  const users: UserOption[] = usersData?.data?.data || [];
  const clients: ClientOption[] = clientsData?.data?.data || [];
  const userOptions = users.map((u) => ({ value: u.id, label: u.name }));
  const clientOptions = clients.map((c) => ({
    value: c.id,
    label: c.email ? `${c.name} (${c.email})` : c.name,
  }));

  const form = useForm<{
    name: string;
    domain_name: string;
    client_id: string;
    login_username: string;
    login_password: string;
    assigned_user_id: string;
    is_active: boolean;
  }>({
    initialValues: {
      name: '', domain_name: '', client_id: '', login_username: '', login_password: '',
      assigned_user_id: '', is_active: true,
    },
    validate: { name: (v) => (v.trim() ? null : 'Required') },
  });

  const closeForm = () => { setFormOpen(false); setEditing(null); form.reset(); };
  const openCreate = () => {
    setEditing(null);
    form.setValues({
      name: '', domain_name: '', client_id: '', login_username: '', login_password: '',
      assigned_user_id: '', is_active: true,
    });
    setFormOpen(true);
  };
  const openEdit = (s: SystemVerification) => {
    setEditing(s);
    form.setValues({
      name: s.name,
      domain_name: s.domain_name || '',
      client_id: s.client_id || '',
      login_username: s.login_username || '',
      login_password: s.login_password || '',
      assigned_user_id: s.assigned_user_id || '',
      is_active: s.is_active,
    });
    setFormOpen(true);
  };

  const buildPayload = (v: typeof form.values) => ({
    name: v.name,
    domain_name: v.domain_name || null,
    // client_id is now a FK UUID to clients.id, set when picked from the dropdown.
    client_id: v.client_id || null,
    login_username: v.login_username || null,
    login_password: v.login_password || null,
    assigned_user_id: v.assigned_user_id || null,
    is_active: v.is_active,
  });

  const createMutation = useMutation({
    mutationFn: (v: typeof form.values) => createSystemVerification(buildPayload(v)),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['system-verifications'] });
      notifications.show({ title: 'Created', message: 'Verification system registered', color: 'green' });
      closeForm();
    },
    onError: (err: any) => notifications.show({ title: 'Error', message: err.response?.data?.message || 'Failed to create', color: 'red' }),
  });

  const updateMutation = useMutation({
    mutationFn: (v: typeof form.values) => updateSystemVerification(editing!.id, buildPayload(v)),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['system-verifications'] });
      notifications.show({ title: 'Updated', message: 'Verification system updated', color: 'green' });
      closeForm();
    },
    onError: (err: any) => notifications.show({ title: 'Error', message: err.response?.data?.message || 'Failed to update', color: 'red' }),
  });

  const deleteMutation = useMutation({
    mutationFn: deleteSystemVerification,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['system-verifications'] });
      notifications.show({ title: 'Deleted', message: 'Verification system removed', color: 'green' });
    },
    onError: (err: any) => notifications.show({ title: 'Error', message: err.response?.data?.message || 'Failed to delete', color: 'red' }),
  });

  const handleDelete = (s: SystemVerification) => modals.openConfirmModal({
    title: 'Remove Verification System',
    children: `Remove "${s.name}"? Historical reports will be preserved but the system won't be checkable anymore.`,
    labels: { confirm: 'Remove', cancel: 'Cancel' },
    confirmProps: { color: 'red' },
    onConfirm: () => deleteMutation.mutate(s.id),
  });

  const statusBadge = (s: SystemVerification) => {
    if (!s.todays_report) return <Badge color="gray" variant="light" leftSection={<IconClock size={10} />}>Pending</Badge>;
    if (s.todays_report.status === 'ok') return <Badge color="green" variant="light" leftSection={<IconCheck size={10} />}>OK today</Badge>;
    return <Badge color="red" variant="light" leftSection={<IconAlertTriangle size={10} />}>Issue today</Badge>;
  };

  return (
    <>
      <Group justify="space-between" mb="md">
        <Title order={2}>System Verifications</Title>
        <Group>
          <TextInput placeholder="Search..." leftSection={<IconSearch size={16} />}
            value={search} onChange={(e) => { setSearch(e.currentTarget.value); setPage(1); }} maw={250} />
          {canCreate && (
            <Button leftSection={<IconPlus size={16} />} onClick={openCreate}>Register System</Button>
          )}
        </Group>
      </Group>

      <VerificationWindowPanel canEdit={canUpdateWindow} />

      {items.length === 0 ? (
        <Text c="dimmed" ta="center" py="xl">No systems registered for verification yet.</Text>
      ) : (
        <Table.ScrollContainer minWidth={900}>
          <Table striped highlightOnHover>
            <Table.Thead>
              <Table.Tr>
                <Table.Th>Name</Table.Th>
                <Table.Th>Domain</Table.Th>
                <Table.Th>Client</Table.Th>
                <Table.Th>Assigned Staff</Table.Th>
                <Table.Th>Today's Status</Table.Th>
                <Table.Th>Active</Table.Th>
                <Table.Th w={130}>Actions</Table.Th>
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {items.map((s) => (
                <Table.Tr key={s.id}>
                  <Table.Td fw={500}>{s.name}</Table.Td>
                  <Table.Td>
                    {s.domain_name ? (
                      <Text size="sm" ff="monospace">{s.domain_name}</Text>
                    ) : <Text size="xs" c="dimmed">—</Text>}
                  </Table.Td>
                  <Table.Td>
                    {s.client ? (
                      <Box>
                        <Text size="sm" fw={500}>{s.client.name}</Text>
                        {s.client.email && <Text size="xs" c="dimmed">{s.client.email}</Text>}
                      </Box>
                    ) : <Text size="xs" c="dimmed">—</Text>}
                  </Table.Td>
                  <Table.Td>{s.assigned_user?.name || <Text size="xs" c="dimmed">unassigned</Text>}</Table.Td>
                  <Table.Td>{statusBadge(s)}</Table.Td>
                  <Table.Td>
                    {s.is_active
                      ? <Badge color="green" variant="light">Active</Badge>
                      : <Badge color="gray" variant="light">Inactive</Badge>}
                  </Table.Td>
                  <Table.Td>
                    <Group gap="xs">
                      <ActionIcon variant="light" color="violet" onClick={() => setHistoryFor(s)} title="View history">
                        <IconHistory size={16} />
                      </ActionIcon>
                      {canUpdate && (
                        <ActionIcon variant="light" onClick={() => openEdit(s)} title="Edit">
                          <IconEdit size={16} />
                        </ActionIcon>
                      )}
                      {canDelete && (
                        <ActionIcon variant="light" color="red" onClick={() => handleDelete(s)} title="Remove">
                          <IconTrash size={16} />
                        </ActionIcon>
                      )}
                    </Group>
                  </Table.Td>
                </Table.Tr>
              ))}
            </Table.Tbody>
          </Table>
        </Table.ScrollContainer>
      )}

      {meta && meta.last_page > 1 && (
        <Group justify="center" mt="md">
          <Pagination total={meta.last_page} value={page} onChange={setPage} />
        </Group>
      )}

      {/* Register / Edit modal */}
      <Modal opened={formOpen} onClose={closeForm} title={editing ? 'Edit System' : 'Register System'} size="md">
        <form onSubmit={form.onSubmit((v) => (editing ? updateMutation : createMutation).mutate(v))}>
          <Stack>
            <TextInput label="Name" required placeholder="e.g. Sehemu ya hesabu" {...form.getInputProps('name')} />
            <TextInput label="Domain Name" placeholder="e.g. moinfotech.co.tz" {...form.getInputProps('domain_name')} />
            <Select label="Client" data={clientOptions} searchable clearable
              placeholder="Link to an existing client (optional)"
              {...form.getInputProps('client_id')} />
            <Select label="Assigned Staff" data={userOptions} searchable clearable
              placeholder="Pick a staff member to monitor this system"
              {...form.getInputProps('assigned_user_id')} />
            <Group grow>
              <TextInput label="Login Username" placeholder="Username to check this system"
                {...form.getInputProps('login_username')} />
              <PasswordInput label="Login Password" placeholder="Password to check this system"
                {...form.getInputProps('login_password')} />
            </Group>
            <Switch label="Active (staff must report daily)" {...form.getInputProps('is_active', { type: 'checkbox' })} />
            <Group justify="flex-end">
              <Button variant="default" onClick={closeForm}>Cancel</Button>
              <Button type="submit" loading={createMutation.isPending || updateMutation.isPending}>
                {editing ? 'Update' : 'Register'}
              </Button>
            </Group>
          </Stack>
        </form>
      </Modal>

      {/* Report history drawer */}
      <Drawer opened={!!historyFor} onClose={() => setHistoryFor(null)}
        title={historyFor ? `Verification History — ${historyFor.name}` : ''} position="right" size="lg">
        {historyFor && <ReportsHistory verification={historyFor} />}
      </Drawer>
    </>
  );
}

function ReportsHistory({ verification }: { verification: SystemVerification }) {
  const { data, isLoading } = useQuery({
    queryKey: ['verification-reports', verification.id],
    queryFn: () => getSystemVerificationReports(verification.id, { per_page: 60 }),
  });
  const reports: SystemVerificationReport[] = data?.data?.data || [];

  if (isLoading) return <Text c="dimmed" size="sm">Loading…</Text>;
  if (reports.length === 0) {
    return (
      <Box ta="center" py="xl">
        <ThemeIcon size="xl" variant="light" color="gray" radius="xl" mb="sm"><IconHistory size={22} /></ThemeIcon>
        <Text c="dimmed" size="sm">No verification reports yet.</Text>
      </Box>
    );
  }

  return (
    <Stack gap="sm">
      {reports.map((r) => (
        <Box key={r.id} p="sm" style={{ borderLeft: `3px solid ${r.status === 'issue' ? '#e03131' : '#2f9e44'}` }}>
          <Group justify="space-between">
            <Group gap="xs">
              <Badge color={r.status === 'issue' ? 'red' : 'green'} variant="light">
                {r.status === 'issue' ? 'ISSUE' : 'OK'}
              </Badge>
              <Text size="sm" fw={500}>{formatDate(r.report_date)}</Text>
              <Text size="xs" c="dimmed">· by {r.user?.name || 'Unknown'}</Text>
            </Group>
            <Text size="xs" c="dimmed">{dayjs(r.created_at).format('HH:mm')}</Text>
          </Group>
          <SimpleGrid cols={4} spacing="xs" mt={6}>
            <Box><Text size="xs" c="dimmed">Cash</Text><Text size="sm" fw={600}>{r.cash ?? '—'}</Text></Box>
            <Box><Text size="xs" c="dimmed">Sales</Text><Text size="sm" fw={600}>{r.sales ?? '—'}</Text></Box>
            <Box><Text size="xs" c="dimmed">Credit</Text><Text size="sm" fw={600}>{r.credit ?? '—'}</Text></Box>
            <Box><Text size="xs" c="dimmed">Gain/Loss</Text>
              <Text size="sm" fw={600} c={r.gain_loss && Number(r.gain_loss) < 0 ? 'red' : undefined}>{r.gain_loss ?? '—'}</Text>
            </Box>
          </SimpleGrid>
          {r.submitted_on_time === false && (
            <Badge color="orange" variant="light" size="xs" mt={6} leftSection={<IconHourglass size={10} />}>Late</Badge>
          )}
          {r.notes && (
            <Text size="sm" mt={4} c={r.status === 'issue' ? 'red.7' : undefined}>{r.notes}</Text>
          )}
        </Box>
      ))}
    </Stack>
  );
}

/** Admin-set daily window staff are expected to check in within. */
function VerificationWindowPanel({ canEdit }: { canEdit: boolean }) {
  const queryClient = useQueryClient();
  const { data } = useQuery({ queryKey: ['verification-window'], queryFn: getVerificationWindow });
  const window_ = data?.data?.data;
  const [from, setFrom] = useState('');
  const [to, setTo] = useState('');
  const [dirty, setDirty] = useState(false);

  if (window_ && !dirty && (from !== (window_.window_from ?? '') || to !== (window_.window_to ?? ''))) {
    setFrom(window_.window_from ?? '');
    setTo(window_.window_to ?? '');
  }

  const saveMutation = useMutation({
    mutationFn: () => updateVerificationWindow({ window_from: from || null, window_to: to || null }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['verification-window'] });
      setDirty(false);
      notifications.show({ title: 'Saved', message: 'Verification window updated', color: 'green' });
    },
    onError: (err: any) => notifications.show({ title: 'Error', message: err.response?.data?.message || 'Failed to save', color: 'red' }),
  });

  return (
    <Paper withBorder p="sm" mb="md">
      <Group justify="space-between" wrap="wrap">
        <Box>
          <Text size="sm" fw={600}>Daily check-in window</Text>
          <Text size="xs" c="dimmed">The hours staff are expected to submit their verification each day. Leave blank for no fixed window.</Text>
        </Box>
        <Group gap="xs">
          <TimeInput label="From" value={from} disabled={!canEdit}
            onChange={(e) => { setFrom(e.currentTarget.value); setDirty(true); }} w={110} />
          <TimeInput label="To" value={to} disabled={!canEdit}
            onChange={(e) => { setTo(e.currentTarget.value); setDirty(true); }} w={110} />
          {canEdit && (
            <Button size="xs" mt={22} loading={saveMutation.isPending} onClick={() => saveMutation.mutate()}>
              Save
            </Button>
          )}
        </Group>
      </Group>
    </Paper>
  );
}
