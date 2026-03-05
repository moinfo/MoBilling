import { useState } from 'react';
import {
  Title, Text, Group, Badge, Table, Paper, Stack, Select,
  Loader, Center, Modal, Button, Textarea,
  SimpleGrid, ThemeIcon, ActionIcon, Tooltip, Pagination,
  RingProgress, Rating, Drawer, Divider, Anchor, Timeline,
} from '@mantine/core';
import { DateInput } from '@mantine/dates';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { notifications } from '@mantine/notifications';
import {
  IconHeartHandshake, IconAlertTriangle, IconCheck,
  IconX, IconCalendarEvent, IconStar, IconPhone,
  IconUser, IconPackages, IconFileInvoice, IconMessage,
} from '@tabler/icons-react';
import {
  getSatisfactionDashboard, getSatisfactionCalls, logSatisfactionCall,
  rescheduleSatisfactionCall, cancelSatisfactionCall,
  getClientSatisfactionHistory, SatisfactionCallEntry,
} from '../api/satisfactionCalls';
import { getClientProfile, ClientProfile } from '../api/clients';
import { formatDate } from '../utils/formatDate';
import { formatCurrency } from '../utils/formatCurrency';

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
  const [logModalOpen, setLogModalOpen] = useState(false);
  const [rescheduleModalOpen, setRescheduleModalOpen] = useState(false);
  const [selectedCall, setSelectedCall] = useState<SatisfactionCallEntry | null>(null);
  const [filterStatus, setFilterStatus] = useState<string>('all');
  const [filterOutcome, setFilterOutcome] = useState<string>('all');
  const [page, setPage] = useState(1);

  // Client drawer state
  const [drawerOpen, setDrawerOpen] = useState(false);
  const [drawerClientId, setDrawerClientId] = useState<string | null>(null);

  // Log call form state
  const [outcome, setOutcome] = useState<string>('');
  const [rating, setRating] = useState<number>(0);
  const [feedback, setFeedback] = useState('');
  const [internalNotes, setInternalNotes] = useState('');

  // Reschedule state
  const [rescheduleDate, setRescheduleDate] = useState<Date | null>(null);

  const { data: dashData, isLoading: dashLoading } = useQuery({
    queryKey: ['satisfaction-dashboard'],
    queryFn: getSatisfactionDashboard,
  });

  const { data: historyData, isLoading: histLoading } = useQuery({
    queryKey: ['satisfaction-calls', filterStatus, filterOutcome, page],
    queryFn: () => getSatisfactionCalls({
      status: filterStatus,
      outcome: filterOutcome,
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
        title: 'Call Logged',
        message: res.data.message,
        color: 'green',
      });
      invalidateAll();
      closeLogModal();
    },
    onError: () => {
      notifications.show({ title: 'Error', message: 'Failed to log call.', color: 'red' });
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

  const invalidateAll = () => {
    queryClient.invalidateQueries({ queryKey: ['satisfaction-dashboard'] });
    queryClient.invalidateQueries({ queryKey: ['satisfaction-calls'] });
    queryClient.invalidateQueries({ queryKey: ['client-satisfaction-history'] });
  };

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
      },
    });
  };

  const handleReschedule = () => {
    if (!selectedCall || !rescheduleDate) return;
    rescheduleMutation.mutate({
      id: selectedCall.id,
      data: { scheduled_date: rescheduleDate.toISOString().split('T')[0] },
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

  // Reusable client name link
  const ClientLink = ({ call }: { call: SatisfactionCallEntry }) => (
    <Anchor
      size="sm"
      fw={500}
      onClick={(e) => { e.stopPropagation(); openClientDrawer(call.client_id); }}
      style={{ cursor: 'pointer' }}
    >
      {call.client_name}
    </Anchor>
  );

  return (
    <Stack gap="lg">
      <Title order={2}>Satisfaction Calls</Title>

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
                  <Table.Th>Scheduled</Table.Th>
                  <Table.Th>Action</Table.Th>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {dashboard.due_today.map((c) => (
                  <Table.Tr key={c.id}>
                    <Table.Td><ClientLink call={c} /></Table.Td>
                    <Table.Td>{c.client_phone || '—'}</Table.Td>
                    <Table.Td>{formatDate(c.scheduled_date)}</Table.Td>
                    <Table.Td>
                      <Group gap="xs">
                        <Tooltip label="Log Call">
                          <ActionIcon color="green" variant="light" onClick={() => openLogModal(c)}>
                            <IconCheck size={16} />
                          </ActionIcon>
                        </Tooltip>
                        <Tooltip label="Reschedule">
                          <ActionIcon color="blue" variant="light" onClick={() => openRescheduleModal(c)}>
                            <IconCalendarEvent size={16} />
                          </ActionIcon>
                        </Tooltip>
                        <Tooltip label="Cancel">
                          <ActionIcon color="gray" variant="light" onClick={() => cancelMutation.mutate(c.id)}>
                            <IconX size={16} />
                          </ActionIcon>
                        </Tooltip>
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
                      <Badge color="red" variant="light" size="sm">
                        {formatDate(c.scheduled_date)}
                      </Badge>
                    </Table.Td>
                    <Table.Td>
                      <Group gap="xs">
                        <Tooltip label="Log Call">
                          <ActionIcon color="green" variant="light" onClick={() => openLogModal(c)}>
                            <IconCheck size={16} />
                          </ActionIcon>
                        </Tooltip>
                        <Tooltip label="Reschedule">
                          <ActionIcon color="blue" variant="light" onClick={() => openRescheduleModal(c)}>
                            <IconCalendarEvent size={16} />
                          </ActionIcon>
                        </Tooltip>
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
                    <Table.Th>Status</Table.Th>
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
                        <Badge color={statusColors[c.status]} size="sm">{c.status}</Badge>
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
                      bullet={call.rating ? <Text size={10} fw={700}>{call.rating}</Text> : <IconPhone size={12} />}
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
                  <Text fw={600}>{selectedCall.client_name}</Text>
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

            {outcome && outcome !== 'no_answer' && outcome !== 'unreachable' && (
              <>
                <div>
                  <Text size="sm" fw={500} mb={4}>Satisfaction Rating</Text>
                  <Rating value={rating} onChange={setRating} size="lg" />
                </div>

                <Textarea
                  label="Customer Feedback"
                  placeholder="What did the customer say about our services?"
                  minRows={3}
                  value={feedback}
                  onChange={(e) => setFeedback(e.currentTarget.value)}
                />
              </>
            )}

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
    </Stack>
  );
}
