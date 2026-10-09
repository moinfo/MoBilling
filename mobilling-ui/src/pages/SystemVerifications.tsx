import { useMemo, useState } from 'react';
import {
  Title, Table, Text, Group, Pagination, Badge, ActionIcon, Modal, Button, TextInput, PasswordInput, Stack, Select, Switch, Drawer, Box, ThemeIcon, SimpleGrid, Checkbox,
} from '@mantine/core';
import { TimeInput } from '@mantine/dates';
import { useForm } from '@mantine/form';
import { useDebouncedValue } from '@mantine/hooks';
import { modals } from '@mantine/modals';
import { notifications } from '@mantine/notifications';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { IconPlus, IconEdit, IconTrash, IconSearch, IconCheck, IconAlertTriangle, IconHistory, IconClock, IconHourglass, IconSettings } from '@tabler/icons-react';
import {
  getSystemVerifications, createSystemVerification, updateSystemVerification, deleteSystemVerification,
  getSystemVerificationReports,
  getVerificationFields, createVerificationField, deleteVerificationField,
  SystemVerification, SystemVerificationReport, VerificationFieldDef, VerificationFieldDefinition,
  VERIFICATION_FIELD_DEFS, BUILT_IN_FIELD_KEYS,
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
  const [fieldsOpen, setFieldsOpen] = useState(false);

  const { data } = useQuery({
    queryKey: ['system-verifications', page, debouncedSearch],
    queryFn: () => getSystemVerifications({ page, search: debouncedSearch || undefined }),
  });
  const { data: fieldsData } = useQuery({
    queryKey: ['verification-field-defs'],
    queryFn: getVerificationFields,
  });
  const customFields: VerificationFieldDefinition[] = fieldsData?.data?.data || [];
  // Every place that needs "which fields exist" reads this combined list —
  // the four built-ins plus whatever this tenant's admin has added.
  const allFieldDefs: VerificationFieldDef[] = useMemo(
    () => [...VERIFICATION_FIELD_DEFS, ...customFields.map((f) => ({ key: f.key, label: f.label }))],
    [customFields]
  );
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
    window_from: string;
    window_to: string;
    assigned_user_id: string;
    is_active: boolean;
    required_fields: string[];
  }>({
    initialValues: {
      name: '', domain_name: '', client_id: '', login_username: '', login_password: '',
      window_from: '', window_to: '', assigned_user_id: '', is_active: true,
      required_fields: VERIFICATION_FIELD_DEFS.map((f) => f.key),
    },
    validate: {
      name: (v) => (v.trim() ? null : 'Required'),
      window_to: (v, all) => (all.window_from && !v ? 'Required when "From" is set' : null),
    },
  });

  const closeForm = () => { setFormOpen(false); setEditing(null); form.reset(); };
  const openCreate = () => {
    setEditing(null);
    form.setValues({
      name: '', domain_name: '', client_id: '', login_username: '', login_password: '',
      window_from: '', window_to: '', assigned_user_id: '', is_active: true,
      required_fields: VERIFICATION_FIELD_DEFS.map((f) => f.key),
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
      window_from: s.window_from ? s.window_from.slice(0, 5) : '',
      window_to: s.window_to ? s.window_to.slice(0, 5) : '',
      assigned_user_id: s.assigned_user_id || '',
      is_active: s.is_active,
      required_fields: s.required_fields?.length ? s.required_fields : VERIFICATION_FIELD_DEFS.map((f) => f.key),
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
    window_from: v.window_from || null,
    window_to: v.window_to || null,
    assigned_user_id: v.assigned_user_id || null,
    is_active: v.is_active,
    required_fields: v.required_fields,
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
          {canUpdate && (
            <Button variant="default" leftSection={<IconSettings size={16} />} onClick={() => setFieldsOpen(true)}>
              Manage Fields
            </Button>
          )}
          {canCreate && (
            <Button leftSection={<IconPlus size={16} />} onClick={openCreate}>Register System</Button>
          )}
        </Group>
      </Group>

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
            <Group grow align="flex-start">
              <TimeInput label="Check-in window — from" description="Leave both blank for no fixed window"
                {...form.getInputProps('window_from')} />
              <TimeInput label="Check-in window — to" {...form.getInputProps('window_to')} />
            </Group>
            <Checkbox.Group
              label="Daily figures required from staff"
              description="Untick any this system doesn't need — staff won't be asked for them"
              {...form.getInputProps('required_fields')}
            >
              <Group mt="xs" gap="md">
                {allFieldDefs.map((f) => (
                  <Checkbox key={f.key} value={f.key} label={f.label} />
                ))}
              </Group>
            </Checkbox.Group>
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
        {historyFor && <ReportsHistory verification={historyFor} allFieldDefs={allFieldDefs} />}
      </Drawer>

      <ManageFieldsModal opened={fieldsOpen} onClose={() => setFieldsOpen(false)} customFields={customFields} />
    </>
  );
}

function ManageFieldsModal({ opened, onClose, customFields }: {
  opened: boolean;
  onClose: () => void;
  customFields: VerificationFieldDefinition[];
}) {
  const queryClient = useQueryClient();
  const [label, setLabel] = useState('');

  const invalidate = () => queryClient.invalidateQueries({ queryKey: ['verification-field-defs'] });

  const createMutation = useMutation({
    mutationFn: (l: string) => createVerificationField(l),
    onSuccess: () => { invalidate(); setLabel(''); },
    onError: (err: any) => notifications.show({ title: 'Error', message: err.response?.data?.message || 'Failed to add field', color: 'red' }),
  });

  const deleteMutation = useMutation({
    mutationFn: (id: string) => deleteVerificationField(id),
    onSuccess: () => {
      invalidate();
      notifications.show({ title: 'Removed', message: 'Field removed', color: 'green' });
    },
    onError: (err: any) => notifications.show({
      title: 'Cannot remove',
      message: err.response?.data?.errors?.label?.[0] || err.response?.data?.message || 'Failed to remove field',
      color: 'red',
    }),
  });

  const handleAdd = () => {
    if (label.trim()) createMutation.mutate(label.trim());
  };

  const handleDelete = (f: VerificationFieldDefinition) => modals.openConfirmModal({
    title: 'Remove Field',
    children: `Remove "${f.label}"? Any system still requiring it must be updated first.`,
    labels: { confirm: 'Remove', cancel: 'Cancel' },
    confirmProps: { color: 'red' },
    onConfirm: () => deleteMutation.mutate(f.id),
  });

  return (
    <Modal opened={opened} onClose={onClose} title="Manage Custom Fields" size="sm">
      <Stack>
        <Text size="sm" c="dimmed">
          The four built-in figures (Cash, Sales, Credit, Gain/Loss) are always available.
          Add your own below — they'll show up as a toggle on every system's Edit form.
        </Text>
        {customFields.length === 0 ? (
          <Text size="sm" c="dimmed" ta="center" py="sm">No custom fields yet.</Text>
        ) : (
          <Stack gap="xs">
            {customFields.map((f) => (
              <Group key={f.id} justify="space-between">
                <Text size="sm">{f.label}</Text>
                <ActionIcon variant="light" color="red" onClick={() => handleDelete(f)} title="Remove">
                  <IconTrash size={14} />
                </ActionIcon>
              </Group>
            ))}
          </Stack>
        )}
        <Group align="flex-end">
          <TextInput label="New field" placeholder="e.g. Banking" value={label}
            onChange={(e) => setLabel(e.currentTarget.value)}
            onKeyDown={(e) => { if (e.key === 'Enter') { e.preventDefault(); handleAdd(); } }}
            style={{ flex: 1 }} />
          <Button onClick={handleAdd} loading={createMutation.isPending}>Add</Button>
        </Group>
      </Stack>
    </Modal>
  );
}

function ReportsHistory({ verification, allFieldDefs }: { verification: SystemVerification; allFieldDefs: VerificationFieldDef[] }) {
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
          {(() => {
            const fields = verification.required_fields?.length ? verification.required_fields : VERIFICATION_FIELD_DEFS.map((f) => f.key);
            const defs = allFieldDefs.filter((f) => fields.includes(f.key));
            const valueFor = (key: string) => (BUILT_IN_FIELD_KEYS.includes(key)
              ? (r as unknown as Record<string, string | null>)[key]
              : r.custom_values?.[key] ?? null);
            return (
              <SimpleGrid cols={defs.length} spacing="xs" mt={6}>
                {defs.map((f) => (
                  <Box key={f.key}>
                    <Text size="xs" c="dimmed">{f.label}</Text>
                    <Text size="sm" fw={600} c={f.key === 'gain_loss' && valueFor(f.key) && Number(valueFor(f.key)) < 0 ? 'red' : undefined}>
                      {valueFor(f.key) ?? '—'}
                    </Text>
                  </Box>
                ))}
              </SimpleGrid>
            );
          })()}
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

