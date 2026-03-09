import { useState } from 'react';
import {
  Title, Text, Group, Badge, Table, Paper, Stack, Select, Switch,
  Loader, Center, Modal, Button, Textarea, TextInput,
  SimpleGrid, ThemeIcon, ActionIcon, Tooltip, Pagination,
  RingProgress, Rating, Drawer, Divider, Anchor, Timeline,
} from '@mantine/core';
import { DateInput } from '@mantine/dates';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { notifications } from '@mantine/notifications';
import {
  IconHeartHandshake, IconAlertTriangle, IconCheck,
  IconX, IconCalendarEvent, IconStar, IconPhone,
  IconUser, IconPackages, IconFileInvoice, IconMessage, IconRepeat, IconMapPin,
  IconScript,
} from '@tabler/icons-react';
import {
  getSatisfactionDashboard, getSatisfactionCalls, logSatisfactionCall,
  rescheduleSatisfactionCall, cancelSatisfactionCall, assignSatisfactionCall,
  getClientSatisfactionHistory, SatisfactionCallEntry,
} from '../api/satisfactionCalls';
import { getClientProfile, ClientProfile } from '../api/clients';
import { getUsers, TenantUser } from '../api/users';
import { formatDate } from '../utils/formatDate';
import { formatCurrency } from '../utils/formatCurrency';
import { usePermissions } from '../hooks/usePermissions';
import { useAuth } from '../context/AuthContext';
import CallScriptDrawer from '../components/CallScriptDrawer';

const outcomeColors: Record<string, string> = {
  satisfied: 'green',
  needs_improvement: 'orange',
  complaint: 'red',
  suggestion: 'blue',
  no_answer: 'gray',
  unreachable: 'dark',
};

const outcomeLabels: Record<string, string> = {
  satisfied: 'Satisfied',
  needs_improvement: 'Needs Improvement',
  complaint: 'Complaint',
  suggestion: 'Suggestion',
  no_answer: 'No Answer',
  unreachable: 'Unreachable',
};

const statusColors: Record<string, string> = {
  scheduled: 'blue',
  completed: 'green',
  missed: 'red',
  cancelled: 'gray',
};

export default function SatisfactionCalls() {
  const queryClient = useQueryClient();
  const { can } = usePermissions();
  const { user } = useAuth();
  const agentName = user?.name || 'Agent';
  const [scriptDrawerOpen, setScriptDrawerOpen] = useState(false);
  const [logModalOpen, setLogModalOpen] = useState(false);
  const [rescheduleModalOpen, setRescheduleModalOpen] = useState(false);
  const [selectedCall, setSelectedCall] = useState<SatisfactionCallEntry | null>(null);
  const [filterStatus, setFilterStatus] = useState<string>('all');
  const [filterOutcome, setFilterOutcome] = useState<string>('all');
  const [filterMonth, setFilterMonth] = useState<string | null>(null);
  const [page, setPage] = useState(1);

  // Assign modal state
  const [assignModalOpen, setAssignModalOpen] = useState(false);
  const [assignUserId, setAssignUserId] = useState<string>('');

  // Client drawer state
  const [drawerOpen, setDrawerOpen] = useState(false);
  const [drawerClientId, setDrawerClientId] = useState<string | null>(null);

  // Log call form state
  const [outcome, setOutcome] = useState<string>('');
  const [rating, setRating] = useState<number>(0);
  const [feedback, setFeedback] = useState('');
  const [internalNotes, setInternalNotes] = useState('');

  // Appointment state
  const [appointmentRequested, setAppointmentRequested] = useState(false);
  const [appointmentDate, setAppointmentDate] = useState<string | null>(null);
  const [appointmentNotes, setAppointmentNotes] = useState('');

  // Reschedule state
  const [rescheduleDate, setRescheduleDate] = useState<string | null>(null);

  const { data: dashData, isLoading: dashLoading } = useQuery({
    queryKey: ['satisfaction-dashboard'],
    queryFn: getSatisfactionDashboard,
  });

  const { data: usersData } = useQuery({
    queryKey: ['users-list'],
    queryFn: () => getUsers({ per_page: 100 }),
  });

  const { data: historyData, isLoading: histLoading } = useQuery({
    queryKey: ['satisfaction-calls', filterStatus, filterOutcome, filterMonth, page],
    queryFn: () => getSatisfactionCalls({
      status: filterStatus,
      outcome: filterOutcome,
      ...(filterMonth ? { month: filterMonth } : {}),
      page: String(page),
      per_page: '15',
    }),
  });

  // Client profile for drawer
  const { data: profileData, isLoading: profileLoading } = useQuery({
    queryKey: ['client-profile', drawerClientId],
    queryFn: () => getClientProfile(drawerClientId!),
    enabled: !!drawerClientId,
  });

  // Client satisfaction history for drawer
  const { data: clientHistData } = useQuery({
    queryKey: ['client-satisfaction-history', drawerClientId],
    queryFn: () => getClientSatisfactionHistory(drawerClientId!),
    enabled: !!drawerClientId,
  });

  const logMutation = useMutation({
    mutationFn: ({ id, data }: { id: string; data: Parameters<typeof logSatisfactionCall>[1] }) =>
      logSatisfactionCall(id, data),
    onSuccess: (res) => {
      notifications.show({
        title: res.data.follow_up ? 'Call Logged — Follow-up Scheduled' : 'Call Logged',
        message: res.data.message,
        color: res.data.follow_up ? 'orange' : 'green',
        autoClose: res.data.follow_up ? 8000 : 4000,
      });
      invalidateAll();
      closeLogModal();
    },
    onError: (err: any) => {
      let msg = 'Failed to log call.';
      if (err?.response?.data?.errors) {
        msg = Object.values(err.response.data.errors as Record<string, string[]>).flat().join(', ');
      } else if (err?.response?.data?.message) {
        msg = err.response.data.message;
      }
      notifications.show({ title: 'Error', message: msg, color: 'red' });
    },
  });

  const rescheduleMutation = useMutation({
    mutationFn: ({ id, data }: { id: string; data: { scheduled_date: string } }) =>
      rescheduleSatisfactionCall(id, data),
    onSuccess: (res) => {
      notifications.show({
        title: 'Rescheduled',
        message: res.data.message,
        color: 'blue',
      });
      invalidateAll();
      closeRescheduleModal();
    },
    onError: () => {
      notifications.show({ title: 'Error', message: 'Failed to reschedule.', color: 'red' });
    },
  });

  const cancelMutation = useMutation({
    mutationFn: cancelSatisfactionCall,
    onSuccess: () => {
      notifications.show({ title: 'Cancelled', message: 'Satisfaction call cancelled.', color: 'gray' });
      invalidateAll();
    },
  });

  const assignMutation = useMutation({
    mutationFn: ({ id, data }: { id: string; data: { user_id: string } }) =>
      assignSatisfactionCall(id, data),
    onSuccess: (res) => {
      notifications.show({ title: 'Assigned', message: res.data.message, color: 'blue' });
      invalidateAll();
      closeAssignModal();
    },
    onError: () => {
      notifications.show({ title: 'Error', message: 'Failed to assign call.', color: 'red' });
    },
  });

  const invalidateAll = () => {
    queryClient.invalidateQueries({ queryKey: ['satisfaction-dashboard'] });
    queryClient.invalidateQueries({ queryKey: ['satisfaction-calls'] });
    queryClient.invalidateQueries({ queryKey: ['client-satisfaction-history'] });
  };

  const openAssignModal = (c: SatisfactionCallEntry) => {
    setSelectedCall(c);
    setAssignUserId(c.user_id || '');
    setAssignModalOpen(true);
  };

  const closeAssignModal = () => {
    setAssignModalOpen(false);
    setSelectedCall(null);
    setAssignUserId('');
  };

  const handleAssign = () => {
    if (!selectedCall || !assignUserId) return;
    assignMutation.mutate({ id: selectedCall.id, data: { user_id: assignUserId } });
  };

  const users: TenantUser[] = usersData?.data?.data ?? [];
  const userSelectData = users.filter((u) => u.is_active).map((u) => ({ value: u.id, label: u.name }));

  // Generate last 12 months for filter
  const monthOptions = Array.from({ length: 12 }, (_, i) => {
    const d = new Date();
    d.setMonth(d.getMonth() - i);
    const key = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
    const label = d.toLocaleString('default', { month: 'long', year: 'numeric' });
    return { value: key, label };
  });

  const openClientDrawer = (clientId: string) => {
    setDrawerClientId(clientId);
    setDrawerOpen(true);
  };

  const openLogModal = (c: SatisfactionCallEntry) => {
    setSelectedCall(c);
    setOutcome('');
    setRating(0);
    setFeedback('');
    setInternalNotes('');
    setAppointmentRequested(false);
    setAppointmentDate(null);
    setAppointmentNotes('');
    setLogModalOpen(true);
  };

  const closeLogModal = () => {
    setLogModalOpen(false);
    setSelectedCall(null);
  };

  const openRescheduleModal = (c: SatisfactionCallEntry) => {
    setSelectedCall(c);
    setRescheduleDate(null);
    setRescheduleModalOpen(true);
  };

  const closeRescheduleModal = () => {
    setRescheduleModalOpen(false);
    setSelectedCall(null);
  };

  const handleLogCall = () => {
    if (!selectedCall || !outcome) return;
    logMutation.mutate({
      id: selectedCall.id,
      data: {
        outcome,
        rating: rating > 0 ? rating : undefined,
        feedback: feedback || undefined,
        internal_notes: internalNotes || undefined,
        appointment_requested: appointmentRequested,
        appointment_date: appointmentRequested ? (appointmentDate || undefined) : undefined,
        appointment_notes: appointmentRequested ? (appointmentNotes || undefined) : undefined,
      },
    });
  };

  const handleReschedule = () => {
    if (!selectedCall || !rescheduleDate) return;
    rescheduleMutation.mutate({
      id: selectedCall.id,
      data: { scheduled_date: rescheduleDate },
    });
  };

  const dashboard = dashData?.data?.data;
  const history = historyData?.data;
  const profile: ClientProfile | undefined = profileData?.data?.data;
  const clientCallHistory: SatisfactionCallEntry[] = clientHistData?.data?.data ?? [];

  if (dashLoading) {
    return <Center py="xl"><Loader /></Center>;
  }

  const completionPct = dashboard?.stats.total_this_month
    ? Math.round((dashboard.stats.completed_this_month / dashboard.stats.total_this_month) * 100)
    : 0;

  const my = dashboard?.my_stats;
  const myTodayPct = my && my.today_total > 0 ? Math.round((my.today_completed / my.today_total) * 100) : 0;
  const myMonthPct = my && my.month_total > 0 ? Math.round((my.month_completed / my.month_total) * 100) : 0;

  // Reusable client name link
  const ClientLink = ({ call }: { call: SatisfactionCallEntry }) => (
    <Group gap={6} wrap="nowrap">
      <Anchor
        size="sm"
        fw={500}
        onClick={(e) => { e.stopPropagation(); openClientDrawer(call.client_id); }}
        style={{ cursor: 'pointer', textTransform: 'uppercase' }}
      >
        {call.client_name}
      </Anchor>
      {call.is_follow_up && (
        <Tooltip label="Follow-up: client didn't answer previously">
          <Badge size="xs" variant="light" color="orange" leftSection={<IconRepeat size={10} />}>
            Follow-up
          </Badge>
        </Tooltip>
      )}
    </Group>
  );

  return (
    <Stack gap="lg">
      <Group justify="space-between">
        <Title order={2}>Satisfaction Calls</Title>
        <Button
          variant="light"
          color="teal"
          leftSection={<IconScript size={18} />}
          onClick={() => setScriptDrawerOpen(true)}
        >
          Call Script
        </Button>
      </Group>

      {/* Stats */}
      <SimpleGrid cols={{ base: 1, xs: 2, sm: 4 }}>
        <Paper withBorder p="md" radius="md">
          <Group gap="sm">
            <ThemeIcon variant="light" color="blue" size="lg" radius="md">
              <IconPhone size={20} />
            </ThemeIcon>
            <div>
              <Text size="xs" c="dimmed" tt="uppercase" fw={600}>Due Today</Text>
              <Text size="xl" fw={700}>{dashboard?.stats.due_today ?? 0}</Text>
            </div>
          </Group>
        </Paper>
        <Paper withBorder p="md" radius="md">
          <Group gap="sm">
            <ThemeIcon variant="light" color="red" size="lg" radius="md">
              <IconAlertTriangle size={20} />
            </ThemeIcon>
            <div>
              <Text size="xs" c="dimmed" tt="uppercase" fw={600}>Overdue / Missed</Text>
              <Text size="xl" fw={700}>{dashboard?.stats.overdue ?? 0}</Text>
            </div>
          </Group>
        </Paper>
        <Paper withBorder p="md" radius="md">
          <Group gap="sm">
            <RingProgress
              size={46}
              thickness={5}
              roundCaps
              sections={[{ value: completionPct, color: 'green' }]}
              label={<Text size="xs" ta="center" fw={700}>{completionPct}%</Text>}
            />
            <div>
              <Text size="xs" c="dimmed" tt="uppercase" fw={600}>Completed</Text>
              <Text size="xl" fw={700}>
                {dashboard?.stats.completed_this_month ?? 0}/{dashboard?.stats.total_this_month ?? 0}
              </Text>
            </div>
          </Group>
        </Paper>
        <Paper withBorder p="md" radius="md">
          <Group gap="sm">
            <ThemeIcon variant="light" color="yellow" size="lg" radius="md">
              <IconStar size={20} />
            </ThemeIcon>
            <div>
              <Text size="xs" c="dimmed" tt="uppercase" fw={600}>Avg Rating</Text>
              <Text size="xl" fw={700}>
                {dashboard?.stats.avg_rating ? `${dashboard.stats.avg_rating}/5` : '—'}
              </Text>
            </div>
          </Group>
        </Paper>
      </SimpleGrid>

      {/* My Performance */}
      {my && (
        <Paper withBorder p="md" radius="md">
          <Group gap="sm" mb="sm">
            <IconUser size={20} />
            <Title order={4}>My Performance</Title>
            <Text size="xs" c="dimmed">({agentName})</Text>
          </Group>
          <SimpleGrid cols={{ base: 2, xs: 3, sm: 5 }}>
            <div>
              <Text size="xs" c="dimmed" tt="uppercase" fw={600}>Today</Text>
              <Group gap={6} align="baseline">
                <Text size="xl" fw={700}>{my.today_completed}/{my.today_total}</Text>
                {my.today_total > 0 && (
                  <Badge size="sm" variant="light" color={myTodayPct === 100 ? 'green' : myTodayPct >= 50 ? 'blue' : 'orange'}>
                    {myTodayPct}%
                  </Badge>
                )}
              </Group>
            </div>
            <div>
              <Text size="xs" c="dimmed" tt="uppercase" fw={600}>This Month</Text>
              <Group gap={6} align="baseline">
                <Text size="xl" fw={700}>{my.month_completed}/{my.month_total}</Text>
                {my.month_total > 0 && (
                  <Badge size="sm" variant="light" color={myMonthPct >= 80 ? 'green' : myMonthPct >= 50 ? 'blue' : 'orange'}>
                    {myMonthPct}%
                  </Badge>
                )}
              </Group>
            </div>
            <div>
              <Text size="xs" c="dimmed" tt="uppercase" fw={600}>My Avg Rating</Text>
              <Group gap={6} align="baseline">
                <Text size="xl" fw={700}>{my.avg_rating ? `${my.avg_rating}/5` : '—'}</Text>
                {my.avg_rating && <Rating value={my.avg_rating} readOnly size="xs" fractions={2} />}
              </Group>
            </div>
            <div>
              <Text size="xs" c="dimmed" tt="uppercase" fw={600}>My Overdue</Text>
              <Text size="xl" fw={700} c={my.overdue > 0 ? 'red' : undefined}>{my.overdue}</Text>
            </div>
            <div>
              <Text size="xs" c="dimmed" tt="uppercase" fw={600}>Remaining Today</Text>
              <Text size="xl" fw={700} c={my.today_total - my.today_completed > 0 ? 'blue' : 'green'}>
                {my.today_total - my.today_completed}
              </Text>
            </div>
          </SimpleGrid>
        </Paper>
      )}

      {/* Due Today */}
      <Paper withBorder p="md" radius="md">
        <Group gap="sm" mb="sm">
          <IconHeartHandshake size={20} />
          <Title order={4}>Calls Due Today</Title>
          <Badge color="blue" variant="light" size="sm">{dashboard?.due_today.length ?? 0}</Badge>
        </Group>
        {!dashboard?.due_today.length ? (
          <Text c="dimmed" size="sm">No satisfaction calls scheduled for today.</Text>
        ) : (
          <Table.ScrollContainer minWidth={600}>
            <Table striped highlightOnHover>
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>Client</Table.Th>
                  <Table.Th>Phone</Table.Th>
                  <Table.Th>Assigned To</Table.Th>
                  <Table.Th>Scheduled</Table.Th>
                  <Table.Th>Action</Table.Th>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {dashboard.due_today.map((c) => (
                  <Table.Tr key={c.id}>
                    <Table.Td><ClientLink call={c} /></Table.Td>
                    <Table.Td>{c.client_phone || '—'}</Table.Td>
                    <Table.Td>
                      {c.assigned_to ? (
                        <Badge variant="light" size="sm">{c.assigned_to}</Badge>
                      ) : (
                        <Text size="xs" c="dimmed">Unassigned</Text>
                      )}
                    </Table.Td>
                    <Table.Td>{formatDate(c.scheduled_date)}</Table.Td>
                    <Table.Td>
                      <Group gap="xs">
                        {can('satisfaction_calls.log') && (
                          <Tooltip label="Log Call">
                            <ActionIcon color="green" variant="light" onClick={() => openLogModal(c)}>
                              <IconCheck size={16} />
                            </ActionIcon>
                          </Tooltip>
                        )}
                        {can('satisfaction_calls.assign') && (
                          <Tooltip label="Assign">
                            <ActionIcon color="violet" variant="light" onClick={() => openAssignModal(c)}>
                              <IconUser size={16} />
                            </ActionIcon>
                          </Tooltip>
                        )}
                        {can('satisfaction_calls.reschedule') && (
                          <Tooltip label="Reschedule">
                            <ActionIcon color="blue" variant="light" onClick={() => openRescheduleModal(c)}>
                              <IconCalendarEvent size={16} />
                            </ActionIcon>
                          </Tooltip>
                        )}
                        {can('satisfaction_calls.cancel') && (
                          <Tooltip label="Cancel">
                            <ActionIcon color="gray" variant="light" onClick={() => cancelMutation.mutate(c.id)}>
                              <IconX size={16} />
                            </ActionIcon>
                          </Tooltip>
                        )}
                      </Group>
                    </Table.Td>
                  </Table.Tr>
                ))}
              </Table.Tbody>
            </Table>
          </Table.ScrollContainer>
        )}
      </Paper>

      {/* Overdue / Missed */}
      {(dashboard?.overdue.length ?? 0) > 0 && (
        <Paper withBorder p="md" radius="md">
          <Group gap="sm" mb="sm">
            <IconAlertTriangle size={20} color="var(--mantine-color-red-6)" />
            <Title order={4}>Overdue / Missed</Title>
            <Badge color="red" variant="light" size="sm">{dashboard!.overdue.length}</Badge>
          </Group>
          <Table.ScrollContainer minWidth={600}>
            <Table striped highlightOnHover>
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>Client</Table.Th>
                  <Table.Th>Phone</Table.Th>
                  <Table.Th>Assigned To</Table.Th>
                  <Table.Th>Was Scheduled</Table.Th>
                  <Table.Th>Action</Table.Th>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {dashboard!.overdue.map((c) => (
                  <Table.Tr key={c.id}>
                    <Table.Td><ClientLink call={c} /></Table.Td>
                    <Table.Td>{c.client_phone || '—'}</Table.Td>
                    <Table.Td>
                      {c.assigned_to ? (
                        <Badge variant="light" size="sm">{c.assigned_to}</Badge>
                      ) : (
                        <Text size="xs" c="dimmed">Unassigned</Text>
                      )}
                    </Table.Td>
                    <Table.Td>
                      <Badge color="red" variant="light" size="sm">
                        {formatDate(c.scheduled_date)}
                      </Badge>
                    </Table.Td>
                    <Table.Td>
                      <Group gap="xs">
                        {can('satisfaction_calls.log') && (
                          <Tooltip label="Log Call">
                            <ActionIcon color="green" variant="light" onClick={() => openLogModal(c)}>
                              <IconCheck size={16} />
                            </ActionIcon>
                          </Tooltip>
                        )}
                        {can('satisfaction_calls.assign') && (
                          <Tooltip label="Assign">
                            <ActionIcon color="violet" variant="light" onClick={() => openAssignModal(c)}>
                              <IconUser size={16} />
                            </ActionIcon>
                          </Tooltip>
                        )}
                        {can('satisfaction_calls.reschedule') && (
                          <Tooltip label="Reschedule">
                            <ActionIcon color="blue" variant="light" onClick={() => openRescheduleModal(c)}>
                              <IconCalendarEvent size={16} />
                            </ActionIcon>
                          </Tooltip>
                        )}
                      </Group>
                    </Table.Td>
                  </Table.Tr>
                ))}
              </Table.Tbody>
            </Table>
          </Table.ScrollContainer>
        </Paper>
      )}

      {/* History */}
      <Paper withBorder p="md" radius="md">
        <Group justify="space-between" mb="sm">
          <Title order={4}>Call History</Title>
          <Group gap="sm">
            <Select
              size="xs"
              w={130}
              value={filterStatus}
              onChange={(v) => { setFilterStatus(v || 'all'); setPage(1); }}
              data={[
                { value: 'all', label: 'All Status' },
                { value: 'scheduled', label: 'Scheduled' },
                { value: 'completed', label: 'Completed' },
                { value: 'missed', label: 'Missed' },
                { value: 'cancelled', label: 'Cancelled' },
              ]}
            />
            <Select
              size="xs"
              w={160}
              value={filterOutcome}
              onChange={(v) => { setFilterOutcome(v || 'all'); setPage(1); }}
              data={[
                { value: 'all', label: 'All Outcomes' },
                { value: 'satisfied', label: 'Satisfied' },
                { value: 'needs_improvement', label: 'Needs Improvement' },
                { value: 'complaint', label: 'Complaint' },
                { value: 'suggestion', label: 'Suggestion' },
                { value: 'no_answer', label: 'No Answer' },
                { value: 'unreachable', label: 'Unreachable' },
              ]}
            />
            <Select
              size="xs"
              w={170}
              placeholder="All Months"
              value={filterMonth}
              onChange={(v) => { setFilterMonth(v); setPage(1); }}
              data={monthOptions}
              clearable
            />
          </Group>
        </Group>

        {histLoading ? (
          <Center py="md"><Loader size="sm" /></Center>
        ) : !history?.data?.length ? (
          <Text c="dimmed" size="sm">No satisfaction call records yet.</Text>
        ) : (
          <>
            <Table.ScrollContainer minWidth={800}>
              <Table striped highlightOnHover>
                <Table.Thead>
                  <Table.Tr>
                    <Table.Th>Date</Table.Th>
                    <Table.Th>Client</Table.Th>
                    <Table.Th>Called By</Table.Th>
                    <Table.Th>Outcome</Table.Th>
                    <Table.Th>Rating</Table.Th>
                    <Table.Th>Feedback</Table.Th>
                    <Table.Th>Appointment</Table.Th>
                    <Table.Th>Status</Table.Th>
                    <Table.Th>Action</Table.Th>
                  </Table.Tr>
                </Table.Thead>
                <Table.Tbody>
                  {history.data.map((c: SatisfactionCallEntry) => (
                    <Table.Tr key={c.id}>
                      <Table.Td>{formatDate(c.scheduled_date)}</Table.Td>
                      <Table.Td><ClientLink call={c} /></Table.Td>
                      <Table.Td>{c.assigned_to || '—'}</Table.Td>
                      <Table.Td>
                        {c.outcome ? (
                          <Badge color={outcomeColors[c.outcome] || 'gray'} size="sm" variant="light">
                            {outcomeLabels[c.outcome] || c.outcome}
                          </Badge>
                        ) : '—'}
                      </Table.Td>
                      <Table.Td>
                        {c.rating ? <Rating value={c.rating} readOnly size="xs" /> : '—'}
                      </Table.Td>
                      <Table.Td>
                        <Text size="xs" truncate maw={200}>{c.feedback || '—'}</Text>
                      </Table.Td>
                      <Table.Td>
                        {c.appointment_requested ? (
                          <Tooltip label={c.appointment_notes || 'Physical visit requested'}>
                            <Badge
                              size="sm"
                              variant="light"
                              color={c.appointment_status === 'completed' ? 'green' : c.appointment_status === 'cancelled' ? 'gray' : 'orange'}
                              leftSection={<IconMapPin size={10} />}
                            >
                              {c.appointment_date ? formatDate(c.appointment_date) : 'TBD'}
                            </Badge>
                          </Tooltip>
                        ) : (
                          <Text size="xs" c="dimmed">—</Text>
                        )}
                      </Table.Td>
                      <Table.Td>
                        <Badge color={statusColors[c.status]} size="sm">{c.status}</Badge>
                      </Table.Td>
                      <Table.Td>
                        {c.status === 'scheduled' ? (
                          <Group gap="xs" wrap="nowrap">
                            {can('satisfaction_calls.log') && (
                              <Tooltip label="Log Call">
                                <ActionIcon color="green" variant="light" size="sm" onClick={() => openLogModal(c)}>
                                  <IconCheck size={14} />
                                </ActionIcon>
                              </Tooltip>
                            )}
                            {can('satisfaction_calls.assign') && (
                              <Tooltip label="Assign">
                                <ActionIcon color="violet" variant="light" size="sm" onClick={() => openAssignModal(c)}>
                                  <IconUser size={14} />
                                </ActionIcon>
                              </Tooltip>
                            )}
                            {can('satisfaction_calls.reschedule') && (
                              <Tooltip label="Reschedule">
                                <ActionIcon color="blue" variant="light" size="sm" onClick={() => openRescheduleModal(c)}>
                                  <IconCalendarEvent size={14} />
                                </ActionIcon>
                              </Tooltip>
                            )}
                            {can('satisfaction_calls.cancel') && (
                              <Tooltip label="Cancel">
                                <ActionIcon color="gray" variant="light" size="sm" onClick={() => cancelMutation.mutate(c.id)}>
                                  <IconX size={14} />
                                </ActionIcon>
                              </Tooltip>
                            )}
                          </Group>
                        ) : (
                          <Text size="xs" c="dimmed">—</Text>
                        )}
                      </Table.Td>
                    </Table.Tr>
                  ))}
                </Table.Tbody>
              </Table>
            </Table.ScrollContainer>
            {history.last_page > 1 && (
              <Group justify="center" mt="md">
                <Pagination value={page} onChange={setPage} total={history.last_page} size="sm" />
              </Group>
            )}
          </>
        )}
      </Paper>

      {/* Client Info Drawer */}
      <Drawer
        opened={drawerOpen}
        onClose={() => { setDrawerOpen(false); setDrawerClientId(null); }}
        title={
          <Group gap="sm">
            <IconUser size={20} />
            <Text fw={600}>{profile?.client.name ?? 'Client Details'}</Text>
          </Group>
        }
        position="right"
        size="lg"
        padding="md"
      >
        {profileLoading ? (
          <Center py="xl"><Loader /></Center>
        ) : profile ? (
          <Stack gap="md">
            {/* Client Info */}
            <Paper p="sm" radius="sm" withBorder>
              <SimpleGrid cols={2}>
                <div>
                  <Text size="xs" c="dimmed">Phone</Text>
                  <Text fw={500}>{profile.client.phone || '—'}</Text>
                </div>
                <div>
                  <Text size="xs" c="dimmed">Email</Text>
                  <Text fw={500}>{profile.client.email || '—'}</Text>
                </div>
                <div>
                  <Text size="xs" c="dimmed">Total Invoiced</Text>
                  <Text fw={600}>{formatCurrency(profile.summary.total_invoiced)}</Text>
                </div>
                <div>
                  <Text size="xs" c="dimmed">Balance Due</Text>
                  <Text fw={600} c={profile.summary.balance > 0 ? 'red' : 'green'}>
                    {formatCurrency(profile.summary.balance)}
                  </Text>
                </div>
              </SimpleGrid>
            </Paper>

            {/* Products / Subscriptions */}
            <div>
              <Group gap="xs" mb="xs">
                <IconPackages size={18} />
                <Text fw={600} size="sm">Products / Subscriptions</Text>
              </Group>
              {!profile.subscriptions.length ? (
                <Text size="sm" c="dimmed">No active subscriptions.</Text>
              ) : (
                <Stack gap={4}>
                  {profile.subscriptions.map((s) => (
                    <Paper key={s.id} p="xs" radius="sm" withBorder>
                      <Group justify="space-between">
                        <div>
                          <Text size="sm" fw={500}>{s.product_service_name}</Text>
                          {s.label && <Text size="xs" c="dimmed">{s.label}</Text>}
                        </div>
                        <Group gap="xs">
                          <Badge size="xs" variant="light" color={s.status === 'active' ? 'green' : 'gray'}>
                            {s.status}
                          </Badge>
                          <Text size="xs" fw={600}>{formatCurrency(Number(s.price))}</Text>
                          <Text size="xs" c="dimmed">/ {s.billing_cycle}</Text>
                        </Group>
                      </Group>
                      {s.next_bill && (
                        <Text size="xs" c="dimmed" mt={4}>
                          Next bill: <Text span fw={600} c="blue">{formatDate(s.next_bill)}</Text>
                        </Text>
                      )}
                    </Paper>
                  ))}
                </Stack>
              )}
            </div>

            <Divider />

            {/* Recent Invoices */}
            <div>
              <Group gap="xs" mb="xs">
                <IconFileInvoice size={18} />
                <Text fw={600} size="sm">Recent Invoices</Text>
              </Group>
              {!profile.invoices.length ? (
                <Text size="sm" c="dimmed">No invoices.</Text>
              ) : (
                <Table.ScrollContainer minWidth={300}>
                  <Table striped highlightOnHover verticalSpacing={4}>
                    <Table.Thead>
                      <Table.Tr>
                        <Table.Th style={{ fontSize: 12 }}>Invoice</Table.Th>
                        <Table.Th style={{ fontSize: 12 }}>Date</Table.Th>
                        <Table.Th style={{ fontSize: 12 }}>Due Date</Table.Th>
                        <Table.Th style={{ fontSize: 12 }}>Amount</Table.Th>
                        <Table.Th style={{ fontSize: 12 }}>Status</Table.Th>
                      </Table.Tr>
                    </Table.Thead>
                    <Table.Tbody>
                      {profile.invoices.slice(0, 10).map((inv) => (
                        <Table.Tr key={inv.id}>
                          <Table.Td><Text size="xs">{inv.document_number}</Text></Table.Td>
                          <Table.Td><Text size="xs">{formatDate(inv.date)}</Text></Table.Td>
                          <Table.Td><Text size="xs">{inv.due_date ? formatDate(inv.due_date) : '—'}</Text></Table.Td>
                          <Table.Td><Text size="xs" fw={500}>{formatCurrency(Number(inv.total))}</Text></Table.Td>
                          <Table.Td>
                            <Badge size="xs" variant="light"
                              color={inv.status === 'paid' ? 'green' : inv.status === 'overdue' ? 'red' : 'blue'}>
                              {inv.status}
                            </Badge>
                          </Table.Td>
                        </Table.Tr>
                      ))}
                    </Table.Tbody>
                  </Table>
                </Table.ScrollContainer>
              )}
            </div>

            <Divider />

            {/* Past Satisfaction Calls — what they said */}
            <div>
              <Group gap="xs" mb="xs">
                <IconMessage size={18} />
                <Text fw={600} size="sm">Past Satisfaction Calls</Text>
              </Group>
              {!clientCallHistory.length ? (
                <Text size="sm" c="dimmed">No previous satisfaction calls.</Text>
              ) : (
                <Timeline active={clientCallHistory.length} bulletSize={24} lineWidth={2}>
                  {clientCallHistory.map((call) => (
                    <Timeline.Item
                      key={call.id}
                      bullet={call.rating ? <Text size="xs" fw={700}>{call.rating}</Text> : <IconPhone size={12} />}
                      title={
                        <Group gap="xs">
                          <Text size="sm" fw={500}>{call.month_key}</Text>
                          {call.outcome && (
                            <Badge size="xs" variant="light" color={outcomeColors[call.outcome] || 'gray'}>
                              {outcomeLabels[call.outcome] || call.outcome}
                            </Badge>
                          )}
                          {call.rating && <Rating value={call.rating} readOnly size="xs" />}
                          <Badge size="xs" variant="light" color={statusColors[call.status]}>{call.status}</Badge>
                        </Group>
                      }
                    >
                      {call.feedback ? (
                        <Paper p="xs" radius="sm" bg="var(--mantine-color-default)" mt={4}>
                          <Text size="xs" c="dimmed" fw={500} mb={2}>Customer said:</Text>
                          <Text size="sm" style={{ whiteSpace: 'pre-wrap' }}>{call.feedback}</Text>
                        </Paper>
                      ) : (
                        <Text size="xs" c="dimmed" mt={4}>No feedback recorded.</Text>
                      )}
                      {call.appointment_requested && (
                        <Group gap="xs" mt={4}>
                          <Badge size="xs" variant="light" color="orange" leftSection={<IconMapPin size={10} />}>
                            Visit: {call.appointment_date ? formatDate(call.appointment_date) : 'TBD'}
                          </Badge>
                          {call.appointment_notes && (
                            <Text size="xs" c="dimmed">{call.appointment_notes}</Text>
                          )}
                        </Group>
                      )}
                      {call.internal_notes && (
                        <Text size="xs" c="dimmed" mt={4} fs="italic">Notes: {call.internal_notes}</Text>
                      )}
                      {call.assigned_to && (
                        <Text size="xs" c="dimmed" mt={2}>Called by: {call.assigned_to}</Text>
                      )}
                    </Timeline.Item>
                  ))}
                </Timeline>
              )}
            </div>
          </Stack>
        ) : null}
      </Drawer>

      {/* Log Call Modal */}
      <Modal
        opened={logModalOpen}
        onClose={closeLogModal}
        title={
          <Group gap="sm">
            <IconHeartHandshake size={20} />
            <Text fw={600}>Log Satisfaction Call</Text>
          </Group>
        }
        size="lg"
      >
        {selectedCall && (
          <Stack gap="md">
            <Paper p="sm" radius="sm" bg="var(--mantine-color-default)">
              <Group justify="space-between">
                <div>
                  <Text size="xs" c="dimmed">Client</Text>
                  <Text fw={600} tt="uppercase">{selectedCall.client_name}</Text>
                </div>
                <div>
                  <Text size="xs" c="dimmed">Phone</Text>
                  <Text fw={600}>{selectedCall.client_phone || 'No phone'}</Text>
                </div>
                <div>
                  <Text size="xs" c="dimmed">Scheduled</Text>
                  <Text fw={600}>{formatDate(selectedCall.scheduled_date)}</Text>
                </div>
              </Group>
            </Paper>

            <Select
              label="Call Outcome"
              placeholder="How did the call go?"
              required
              value={outcome}
              onChange={(v) => setOutcome(v || '')}
              data={[
                { value: 'satisfied', label: 'Satisfied — Happy with services' },
                { value: 'needs_improvement', label: 'Needs Improvement — Some concerns' },
                { value: 'complaint', label: 'Complaint — Unhappy, needs resolution' },
                { value: 'suggestion', label: 'Suggestion — Has ideas for improvement' },
                { value: 'no_answer', label: 'No Answer — Did not pick up' },
                { value: 'unreachable', label: 'Unreachable — Number not reachable' },
              ]}
            />

            <div>
              <Text size="sm" fw={500} mb={4}>Satisfaction Rating</Text>
              <Rating value={rating} onChange={setRating} size="lg" />
            </div>

            <Textarea
              label="Customer Feedback"
              placeholder="What did the customer say about our services? Any challenges?"
              minRows={3}
              value={feedback}
              onChange={(e) => setFeedback(e.currentTarget.value)}
            />

            {/* Appointment / Physical Visit */}
            <Paper p="sm" radius="sm" withBorder>
              <Switch
                label="Client requested a physical visit"
                checked={appointmentRequested}
                onChange={(e) => setAppointmentRequested(e.currentTarget.checked)}
                mb={appointmentRequested ? 'sm' : 0}
              />
              {appointmentRequested && (
                <Stack gap="xs" mt="xs">
                  <DateInput
                    label="Appointment Date (suggested by client)"
                    placeholder="Pick date"
                    required
                    value={appointmentDate}
                    onChange={setAppointmentDate}
                    minDate={new Date()}
                  />
                  <TextInput
                    label="Visit Notes"
                    placeholder="Location, purpose, contact person..."
                    value={appointmentNotes}
                    onChange={(e) => setAppointmentNotes(e.currentTarget.value)}
                  />
                </Stack>
              )}
            </Paper>

            <Textarea
              label="Internal Notes / Action Items"
              placeholder="Any follow-up actions needed?"
              minRows={2}
              value={internalNotes}
              onChange={(e) => setInternalNotes(e.currentTarget.value)}
            />

            <Group justify="flex-end" mt="sm">
              <Button variant="default" onClick={closeLogModal}>Cancel</Button>
              <Button
                color="green"
                leftSection={<IconCheck size={16} />}
                onClick={handleLogCall}
                loading={logMutation.isPending}
                disabled={!outcome}
              >
                Log Call
              </Button>
            </Group>
          </Stack>
        )}
      </Modal>

      {/* Assign Modal */}
      <Modal
        opened={assignModalOpen}
        onClose={closeAssignModal}
        title={
          <Group gap="sm">
            <IconUser size={20} />
            <Text fw={600}>Assign Call</Text>
          </Group>
        }
      >
        {selectedCall && (
          <Stack gap="md">
            <Text size="sm">
              Assign satisfaction call for <Text span fw={600}>{selectedCall.client_name}</Text> to a team member.
            </Text>
            <Select
              label="Assign To"
              placeholder="Select team member"
              required
              value={assignUserId}
              onChange={(v) => setAssignUserId(v || '')}
              data={userSelectData}
              searchable
            />
            <Group justify="flex-end">
              <Button variant="default" onClick={closeAssignModal}>Cancel</Button>
              <Button
                color="violet"
                onClick={handleAssign}
                loading={assignMutation.isPending}
                disabled={!assignUserId}
              >
                Assign
              </Button>
            </Group>
          </Stack>
        )}
      </Modal>

      {/* Reschedule Modal */}
      <Modal
        opened={rescheduleModalOpen}
        onClose={closeRescheduleModal}
        title={
          <Group gap="sm">
            <IconCalendarEvent size={20} />
            <Text fw={600}>Reschedule Call</Text>
          </Group>
        }
      >
        {selectedCall && (
          <Stack gap="md">
            <Text size="sm">
              Reschedule satisfaction call for <Text span fw={600}>{selectedCall.client_name}</Text>
            </Text>
            <DateInput
              label="New Date"
              placeholder="Pick a date"
              required
              value={rescheduleDate}
              onChange={setRescheduleDate}
              minDate={new Date()}
            />
            <Group justify="flex-end">
              <Button variant="default" onClick={closeRescheduleModal}>Cancel</Button>
              <Button
                color="blue"
                onClick={handleReschedule}
                loading={rescheduleMutation.isPending}
                disabled={!rescheduleDate}
              >
                Reschedule
              </Button>
            </Group>
          </Stack>
        )}
      </Modal>

      <CallScriptDrawer
        opened={scriptDrawerOpen}
        onClose={() => setScriptDrawerOpen(false)}
        agentName={agentName}
        defaultSection="section5"
      />
    </Stack>
  );
}
