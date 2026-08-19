import { useState } from 'react';
import {
  Title, Text, Tabs, Paper, Table, Badge, Button, Group, Stack, SimpleGrid,
  Modal, TextInput, Textarea, Select, NumberInput, ActionIcon, Switch, Center, Loader,
} from '@mantine/core';
import { useForm } from '@mantine/form';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { notifications } from '@mantine/notifications';
import { modals } from '@mantine/modals';
import {
  IconCalendarPlus, IconCheck, IconX, IconTrash, IconEdit, IconPlus,
} from '@tabler/icons-react';
import {
  getLeaveTypes, createLeaveType, updateLeaveType, deleteLeaveType,
  getLeaveRequests, createLeaveRequest, cancelLeaveRequest, reviewLeaveRequest,
  getMyLeaveBalance, getLeaveBalances, setLeaveBalance,
  LeaveType, LeaveRequest,
} from '../api/leave';
import { formatDate } from '../utils/formatDate';
import { usePermissions } from '../hooks/usePermissions';

const statusColors: Record<string, string> = {
  pending: 'yellow', approved: 'green', rejected: 'red', cancelled: 'gray',
};

export default function Leave() {
  const { can } = usePermissions();
  const canReview = can('leave.review') || can('leave.view_all');
  const canManage = can('leave.manage');

  return (
    <Stack gap="lg">
      <Title order={2}>Leave</Title>
      <Tabs defaultValue="dashboard" keepMounted={false}>
        <Tabs.List>
          <Tabs.Tab value="dashboard">Dashboard</Tabs.Tab>
          <Tabs.Tab value="mine">My Requests</Tabs.Tab>
          {canReview && <Tabs.Tab value="team">Team Approvals</Tabs.Tab>}
          {canManage && <Tabs.Tab value="settings">Settings</Tabs.Tab>}
        </Tabs.List>

        <Tabs.Panel value="dashboard" pt="md"><DashboardTab canReview={canReview} /></Tabs.Panel>
        <Tabs.Panel value="mine" pt="md"><MyRequestsTab /></Tabs.Panel>
        {canReview && <Tabs.Panel value="team" pt="md"><TeamApprovalsTab /></Tabs.Panel>}
        {canManage && <Tabs.Panel value="settings" pt="md"><SettingsTab /></Tabs.Panel>}
      </Tabs>
    </Stack>
  );
}

function DashboardTab({ canReview }: { canReview: boolean }) {
  const { data, isLoading } = useQuery({ queryKey: ['my-leave-balance'], queryFn: () => getMyLeaveBalance() });
  const { data: teamData } = useQuery({
    queryKey: ['leave-requests', 'pending-count'],
    queryFn: () => getLeaveRequests({ status: 'pending' }),
    enabled: canReview,
  });

  const balances = data?.data?.data ?? [];
  const pendingCount = teamData?.data?.data?.length ?? 0;

  if (isLoading) return <Center py="xl"><Loader /></Center>;

  return (
    <Stack gap="md">
      {canReview && pendingCount > 0 && (
        <Paper withBorder p="md" radius="md" bg="var(--mantine-color-yellow-light)">
          <Text size="sm" fw={600}>{pendingCount} leave request(s) awaiting your review.</Text>
        </Paper>
      )}
      <SimpleGrid cols={{ base: 1, sm: 2, md: 3 }}>
        {balances.map((b) => (
          <Paper withBorder p="md" radius="md" key={b.leave_type.id}>
            <Text size="sm" c="dimmed">{b.leave_type.name}</Text>
            <Text size="xl" fw={700}>{b.remaining_days} <Text span size="sm" c="dimmed">/ {b.allocated_days} days left</Text></Text>
            <Text size="xs" c="dimmed">{b.used_days} used this year</Text>
          </Paper>
        ))}
        {balances.length === 0 && <Text c="dimmed" size="sm">No leave types configured yet.</Text>}
      </SimpleGrid>
    </Stack>
  );
}

function MyRequestsTab() {
  const queryClient = useQueryClient();
  const [modalOpen, setModalOpen] = useState(false);

  const { data: typesData } = useQuery({ queryKey: ['leave-types'], queryFn: getLeaveTypes });
  const { data, isLoading } = useQuery({ queryKey: ['leave-requests', 'mine'], queryFn: () => getLeaveRequests() });

  const types = typesData?.data?.data ?? [];
  const requests: LeaveRequest[] = data?.data?.data ?? [];

  const form = useForm({
    initialValues: { leave_type_id: '', start_date: '', end_date: '', reason: '' },
    validate: {
      leave_type_id: (v) => (v ? null : 'Required'),
      start_date: (v) => (v ? null : 'Required'),
      end_date: (v, values) => (v && v >= values.start_date ? null : 'End date must be on/after start date'),
    },
  });

  const createMut = useMutation({
    mutationFn: (values: typeof form.values) => createLeaveRequest(values),
    onSuccess: () => {
      notifications.show({ title: 'Success', message: 'Leave request submitted', color: 'green' });
      queryClient.invalidateQueries({ queryKey: ['leave-requests'] });
      queryClient.invalidateQueries({ queryKey: ['my-leave-balance'] });
      setModalOpen(false);
      form.reset();
    },
    onError: (err: any) => notifications.show({
      title: 'Error', message: err.response?.data?.message || 'Failed to submit request', color: 'red',
    }),
  });

  const cancelMut = useMutation({
    mutationFn: (id: string) => cancelLeaveRequest(id),
    onSuccess: () => {
      notifications.show({ title: 'Success', message: 'Request cancelled', color: 'green' });
      queryClient.invalidateQueries({ queryKey: ['leave-requests'] });
    },
  });

  return (
    <Stack gap="md">
      <Group justify="flex-end">
        <Button leftSection={<IconCalendarPlus size={16} />} size="xs" onClick={() => setModalOpen(true)}>
          Request Leave
        </Button>
      </Group>

      {isLoading ? <Center py="md"><Loader size="sm" /></Center> : requests.length === 0 ? (
        <Text c="dimmed" size="sm">No leave requests yet.</Text>
      ) : (
        <Table.ScrollContainer minWidth={600}>
          <Table striped highlightOnHover>
            <Table.Thead>
              <Table.Tr>
                <Table.Th>Type</Table.Th>
                <Table.Th>Dates</Table.Th>
                <Table.Th>Days</Table.Th>
                <Table.Th>Reason</Table.Th>
                <Table.Th>Status</Table.Th>
                <Table.Th />
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {requests.map((r) => (
                <Table.Tr key={r.id}>
                  <Table.Td>{r.leave_type?.name ?? '—'}</Table.Td>
                  <Table.Td>{formatDate(r.start_date)} – {formatDate(r.end_date)}</Table.Td>
                  <Table.Td>{r.days}</Table.Td>
                  <Table.Td><Text size="xs" c="dimmed" truncate maw={200}>{r.reason || '—'}</Text></Table.Td>
                  <Table.Td><Badge size="sm" color={statusColors[r.status]}>{r.status}</Badge></Table.Td>
                  <Table.Td>
                    {r.status === 'pending' && (
                      <ActionIcon variant="subtle" color="red" size="sm" onClick={() => cancelMut.mutate(r.id)}>
                        <IconTrash size={14} />
                      </ActionIcon>
                    )}
                  </Table.Td>
                </Table.Tr>
              ))}
            </Table.Tbody>
          </Table>
        </Table.ScrollContainer>
      )}

      <Modal opened={modalOpen} onClose={() => setModalOpen(false)} title="Request Leave">
        <form onSubmit={form.onSubmit((values) => createMut.mutate(values))}>
          <Stack gap="sm">
            <Select label="Leave Type" required data={types.map((t) => ({ value: t.id, label: t.name }))} {...form.getInputProps('leave_type_id')} />
            <TextInput label="Start Date" type="date" required {...form.getInputProps('start_date')} />
            <TextInput label="End Date" type="date" required {...form.getInputProps('end_date')} />
            <Textarea label="Reason" minRows={2} {...form.getInputProps('reason')} />
            <Group justify="flex-end">
              <Button variant="default" onClick={() => setModalOpen(false)}>Cancel</Button>
              <Button type="submit" loading={createMut.isPending}>Submit</Button>
            </Group>
          </Stack>
        </form>
      </Modal>
    </Stack>
  );
}

function TeamApprovalsTab() {
  const queryClient = useQueryClient();
  const [statusFilter, setStatusFilter] = useState<string | null>('pending');

  const { data, isLoading } = useQuery({
    queryKey: ['leave-requests', 'team', statusFilter],
    queryFn: () => getLeaveRequests({ status: statusFilter || undefined }),
  });

  const requests: LeaveRequest[] = data?.data?.data ?? [];

  const reviewMut = useMutation({
    mutationFn: ({ id, decision, note }: { id: string; decision: 'approved' | 'rejected'; note?: string }) =>
      reviewLeaveRequest(id, decision, note),
    onSuccess: () => {
      notifications.show({ title: 'Success', message: 'Request reviewed', color: 'green' });
      queryClient.invalidateQueries({ queryKey: ['leave-requests'] });
    },
    onError: (err: any) => notifications.show({
      title: 'Error', message: err.response?.data?.message || 'Failed to review request', color: 'red',
    }),
  });

  const confirmReview = (r: LeaveRequest, decision: 'approved' | 'rejected') => {
    modals.openConfirmModal({
      title: decision === 'approved' ? 'Approve Leave' : 'Reject Leave',
      children: <Text size="sm">
        {decision === 'approved' ? 'Approve' : 'Reject'} {r.user?.name}'s {r.leave_type?.name} request
        ({formatDate(r.start_date)} – {formatDate(r.end_date)}, {r.days} day(s))?
      </Text>,
      labels: { confirm: decision === 'approved' ? 'Approve' : 'Reject', cancel: 'Cancel' },
      confirmProps: { color: decision === 'approved' ? 'green' : 'red' },
      onConfirm: () => reviewMut.mutate({ id: r.id, decision }),
    });
  };

  return (
    <Stack gap="md">
      <Select
        label="Status" size="xs" maw={200}
        data={[
          { value: 'pending', label: 'Pending' },
          { value: 'approved', label: 'Approved' },
          { value: 'rejected', label: 'Rejected' },
          { value: '', label: 'All' },
        ]}
        value={statusFilter} onChange={setStatusFilter}
      />
      {isLoading ? <Center py="md"><Loader size="sm" /></Center> : requests.length === 0 ? (
        <Text c="dimmed" size="sm">No requests found.</Text>
      ) : (
        <Table.ScrollContainer minWidth={700}>
          <Table striped highlightOnHover>
            <Table.Thead>
              <Table.Tr>
                <Table.Th>Staff</Table.Th>
                <Table.Th>Type</Table.Th>
                <Table.Th>Dates</Table.Th>
                <Table.Th>Days</Table.Th>
                <Table.Th>Reason</Table.Th>
                <Table.Th>Status</Table.Th>
                <Table.Th />
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {requests.map((r) => (
                <Table.Tr key={r.id}>
                  <Table.Td>{r.user?.name ?? '—'}</Table.Td>
                  <Table.Td>{r.leave_type?.name ?? '—'}</Table.Td>
                  <Table.Td>{formatDate(r.start_date)} – {formatDate(r.end_date)}</Table.Td>
                  <Table.Td>{r.days}</Table.Td>
                  <Table.Td><Text size="xs" c="dimmed" truncate maw={200}>{r.reason || '—'}</Text></Table.Td>
                  <Table.Td><Badge size="sm" color={statusColors[r.status]}>{r.status}</Badge></Table.Td>
                  <Table.Td>
                    {r.status === 'pending' && (
                      <Group gap={4} wrap="nowrap">
                        <ActionIcon variant="light" color="green" size="sm" onClick={() => confirmReview(r, 'approved')}>
                          <IconCheck size={14} />
                        </ActionIcon>
                        <ActionIcon variant="light" color="red" size="sm" onClick={() => confirmReview(r, 'rejected')}>
                          <IconX size={14} />
                        </ActionIcon>
                      </Group>
                    )}
                  </Table.Td>
                </Table.Tr>
              ))}
            </Table.Tbody>
          </Table>
        </Table.ScrollContainer>
      )}
    </Stack>
  );
}

function SettingsTab() {
  const queryClient = useQueryClient();
  const [modalOpen, setModalOpen] = useState(false);
  const [editing, setEditing] = useState<LeaveType | null>(null);

  const { data, isLoading } = useQuery({ queryKey: ['leave-types'], queryFn: getLeaveTypes });
  const types = data?.data?.data ?? [];

  const form = useForm({
    initialValues: { name: '', days_per_year: 0, is_paid: true, is_active: true, color: '' },
    validate: { name: (v) => (v.length > 0 ? null : 'Required') },
  });

  const createMut = useMutation({
    mutationFn: (values: typeof form.values) => createLeaveType(values),
    onSuccess: () => {
      notifications.show({ title: 'Success', message: 'Leave type created', color: 'green' });
      queryClient.invalidateQueries({ queryKey: ['leave-types'] });
      closeModal();
    },
  });

  const updateMut = useMutation({
    mutationFn: (values: typeof form.values) => updateLeaveType(editing!.id, values),
    onSuccess: () => {
      notifications.show({ title: 'Success', message: 'Leave type updated', color: 'green' });
      queryClient.invalidateQueries({ queryKey: ['leave-types'] });
      closeModal();
    },
  });

  const deleteMut = useMutation({
    mutationFn: (id: string) => deleteLeaveType(id),
    onSuccess: () => {
      notifications.show({ title: 'Success', message: 'Leave type removed', color: 'green' });
      queryClient.invalidateQueries({ queryKey: ['leave-types'] });
    },
  });

  const openCreate = () => { setEditing(null); form.reset(); setModalOpen(true); };
  const openEdit = (t: LeaveType) => {
    setEditing(t);
    form.setValues({ name: t.name, days_per_year: t.days_per_year, is_paid: t.is_paid, is_active: t.is_active, color: t.color || '' });
    setModalOpen(true);
  };
  const closeModal = () => { setModalOpen(false); setEditing(null); form.reset(); };

  const confirmDelete = (t: LeaveType) => {
    modals.openConfirmModal({
      title: 'Remove Leave Type',
      children: <Text size="sm">Remove "{t.name}"? Existing requests keep their history.</Text>,
      labels: { confirm: 'Remove', cancel: 'Cancel' },
      confirmProps: { color: 'red' },
      onConfirm: () => deleteMut.mutate(t.id),
    });
  };

  return (
    <Stack gap="md">
      <Group justify="space-between">
        <Title order={4}>Leave Types</Title>
        <Button leftSection={<IconPlus size={14} />} size="xs" onClick={openCreate}>Add Leave Type</Button>
      </Group>

      {isLoading ? <Center py="md"><Loader size="sm" /></Center> : types.length === 0 ? (
        <Text c="dimmed" size="sm">No leave types yet.</Text>
      ) : (
        <Table striped highlightOnHover>
          <Table.Thead>
            <Table.Tr>
              <Table.Th>Name</Table.Th>
              <Table.Th>Days/Year</Table.Th>
              <Table.Th>Paid</Table.Th>
              <Table.Th>Active</Table.Th>
              <Table.Th>Actions</Table.Th>
            </Table.Tr>
          </Table.Thead>
          <Table.Tbody>
            {types.map((t) => (
              <Table.Tr key={t.id}>
                <Table.Td fw={500}>{t.name}</Table.Td>
                <Table.Td>{t.days_per_year}</Table.Td>
                <Table.Td><Badge size="sm" variant="light" color={t.is_paid ? 'green' : 'gray'}>{t.is_paid ? 'Paid' : 'Unpaid'}</Badge></Table.Td>
                <Table.Td><Badge size="sm" variant="light" color={t.is_active ? 'green' : 'gray'}>{t.is_active ? 'Active' : 'Inactive'}</Badge></Table.Td>
                <Table.Td>
                  <Group gap="xs">
                    <ActionIcon variant="subtle" size="sm" onClick={() => openEdit(t)}><IconEdit size={14} /></ActionIcon>
                    <ActionIcon variant="subtle" size="sm" color="red" onClick={() => confirmDelete(t)}><IconTrash size={14} /></ActionIcon>
                  </Group>
                </Table.Td>
              </Table.Tr>
            ))}
          </Table.Tbody>
        </Table>
      )}

      <Modal opened={modalOpen} onClose={closeModal} title={editing ? 'Edit Leave Type' : 'Add Leave Type'}>
        <form onSubmit={form.onSubmit((values) => editing ? updateMut.mutate(values) : createMut.mutate(values))}>
          <Stack gap="sm">
            <TextInput label="Name" required {...form.getInputProps('name')} />
            <NumberInput label="Days per Year" min={0} max={365} required {...form.getInputProps('days_per_year')} />
            <Switch label="Paid leave" {...form.getInputProps('is_paid', { type: 'checkbox' })} />
            {editing && <Switch label="Active" {...form.getInputProps('is_active', { type: 'checkbox' })} />}
            <Group justify="flex-end">
              <Button variant="default" onClick={closeModal}>Cancel</Button>
              <Button type="submit" loading={createMut.isPending || updateMut.isPending}>
                {editing ? 'Save' : 'Create'}
              </Button>
            </Group>
          </Stack>
        </form>
      </Modal>

      <BalancesSection leaveTypes={types} />
    </Stack>
  );
}

function BalancesSection({ leaveTypes }: { leaveTypes: LeaveType[] }) {
  const queryClient = useQueryClient();
  const year = new Date().getFullYear();
  const { data, isLoading } = useQuery({ queryKey: ['leave-balances', year], queryFn: () => getLeaveBalances(year) });

  const users = data?.data?.data?.users ?? [];
  const balances = data?.data?.data?.balances ?? [];

  const setMut = useMutation({
    mutationFn: (vars: { user_id: string; leave_type_id: string; allocated_days: number }) =>
      setLeaveBalance({ ...vars, year }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['leave-balances', year] });
    },
  });

  if (leaveTypes.length === 0) return null;

  return (
    <Stack gap="sm" mt="lg">
      <Title order={4}>{year} Balances</Title>
      {isLoading ? <Center py="md"><Loader size="sm" /></Center> : (
        <Table.ScrollContainer minWidth={500}>
          <Table striped>
            <Table.Thead>
              <Table.Tr>
                <Table.Th>Staff</Table.Th>
                {leaveTypes.map((t) => <Table.Th key={t.id}>{t.name}</Table.Th>)}
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {users.map((u) => (
                <Table.Tr key={u.id}>
                  <Table.Td fw={500}>{u.name}</Table.Td>
                  {leaveTypes.map((t) => {
                    const bal = balances.find((b) => b.user_id === u.id && b.leave_type_id === t.id);
                    return (
                      <Table.Td key={t.id}>
                        <NumberInput
                          size="xs" w={80} min={0} max={365}
                          defaultValue={bal?.allocated_days ?? t.days_per_year}
                          onBlur={(e) => {
                            const value = Number(e.currentTarget.value) || 0;
                            setMut.mutate({ user_id: u.id, leave_type_id: t.id, allocated_days: value });
                          }}
                        />
                      </Table.Td>
                    );
                  })}
                </Table.Tr>
              ))}
            </Table.Tbody>
          </Table>
        </Table.ScrollContainer>
      )}
    </Stack>
  );
}
