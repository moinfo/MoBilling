import { useState } from 'react';
import {
  Title, Text, Group, Badge, Table, Paper, Stack, Select,
  Loader, Center, Modal, Button, Textarea, NumberInput,
  SimpleGrid, ThemeIcon, ActionIcon, Tooltip, Pagination,
} from '@mantine/core';
import { DateInput } from '@mantine/dates';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { notifications } from '@mantine/notifications';
import {
  IconPhone, IconPhoneCall, IconAlertTriangle, IconCheck,
  IconX, IconPlayerPlay,
} from '@tabler/icons-react';
import {
  getFollowupDashboard, getFollowups, logCall, cancelFollowup,
  FollowupEntry,
} from '../api/followups';
import { formatCurrency } from '../utils/formatCurrency';
import { formatDate } from '../utils/formatDate';

const outcomeColors: Record<string, string> = {
  promised: 'blue',
  declined: 'red',
  no_answer: 'gray',
  disputed: 'orange',
  partial_payment: 'yellow',
};

const statusColors: Record<string, string> = {
  pending: 'blue',
  open: 'cyan',
  fulfilled: 'green',
  broken: 'red',
  escalated: 'orange',
  cancelled: 'gray',
};

export default function Followups() {
  const queryClient = useQueryClient();
  const [logModalOpen, setLogModalOpen] = useState(false);
  const [selectedFollowup, setSelectedFollowup] = useState<FollowupEntry | null>(null);
  const [filterStatus, setFilterStatus] = useState<string>('all');
  const [filterOutcome, setFilterOutcome] = useState<string>('all');
  const [page, setPage] = useState(1);

  // Log call form state
  const [outcome, setOutcome] = useState<string>('');
  const [notes, setNotes] = useState('');
  const [promiseDate, setPromiseDate] = useState<string | null>(null);
  const [promiseAmount, setPromiseAmount] = useState<number | undefined>(undefined);
  const [nextOverride, setNextOverride] = useState<string | null>(null);

  const { data: dashData, isLoading: dashLoading } = useQuery({
    queryKey: ['followup-dashboard'],
    queryFn: getFollowupDashboard,
  });

  const { data: historyData, isLoading: histLoading } = useQuery({
    queryKey: ['followups', filterStatus, filterOutcome, page],
    queryFn: () => getFollowups({
      status: filterStatus,
      outcome: filterOutcome,
      page: String(page),
      per_page: '15',
    }),
  });

  const logMutation = useMutation({
    mutationFn: ({ id, data }: { id: string; data: Parameters<typeof logCall>[1] }) =>
      logCall(id, data),
    onSuccess: (res) => {
      notifications.show({
        title: 'Call Logged',
        message: res.data.message,
        color: res.data.escalated ? 'orange' : 'green',
      });
      queryClient.invalidateQueries({ queryKey: ['followup-dashboard'] });
      queryClient.invalidateQueries({ queryKey: ['followups'] });
      queryClient.invalidateQueries({ queryKey: ['collection-dashboard'] });
      closeLogModal();
    },
    onError: () => {
      notifications.show({ title: 'Error', message: 'Failed to log call.', color: 'red' });
    },
  });

  const cancelMutation = useMutation({
    mutationFn: cancelFollowup,
    onSuccess: () => {
      notifications.show({ title: 'Cancelled', message: 'Follow-up cancelled.', color: 'gray' });
      queryClient.invalidateQueries({ queryKey: ['followup-dashboard'] });
      queryClient.invalidateQueries({ queryKey: ['followups'] });
    },
  });

  const openLogModal = (f: FollowupEntry) => {
    setSelectedFollowup(f);
    setOutcome('');
    setNotes('');
    setPromiseDate(null);
    setPromiseAmount(undefined);
    setNextOverride(null);
    setLogModalOpen(true);
  };

  const closeLogModal = () => {
    setLogModalOpen(false);
    setSelectedFollowup(null);
  };

  const handleLogCall = () => {
    if (!selectedFollowup || !outcome || !notes) return;
    logMutation.mutate({
      id: selectedFollowup.id,
      data: {
        outcome,
        notes,
        promise_date: promiseDate || undefined,
        promise_amount: promiseAmount,
        next_followup_override: nextOverride || undefined,
      },
    });
  };

  const dashboard = dashData?.data?.data;
  const history = historyData?.data;

  if (dashLoading) {
    return <Center py="xl"><Loader /></Center>;
  }

  return (
    <Stack gap="lg">
      <Title order={2}>Follow-ups</Title>

      {/* Stats */}
      <SimpleGrid cols={{ base: 1, xs: 3 }}>
        <Paper withBorder p="md" radius="md">
          <Group gap="sm">
            <ThemeIcon variant="light" color="blue" size="lg" radius="md">
              <IconPhoneCall size={20} />
            </ThemeIcon>
            <div>
              <Text size="xs" c="dimmed" tt="uppercase" fw={600}>Calls Due Today</Text>
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
              <Text size="xs" c="dimmed" tt="uppercase" fw={600}>Overdue Follow-ups</Text>
              <Text size="xl" fw={700}>{dashboard?.stats.overdue ?? 0}</Text>
            </div>
          </Group>
        </Paper>
        <Paper withBorder p="md" radius="md">
          <Group gap="sm">
            <ThemeIcon variant="light" color="cyan" size="lg" radius="md">
              <IconPhone size={20} />
            </ThemeIcon>
            <div>
              <Text size="xs" c="dimmed" tt="uppercase" fw={600}>Total Active</Text>
              <Text size="xl" fw={700}>{dashboard?.stats.total_active ?? 0}</Text>
            </div>
          </Group>
        </Paper>
      </SimpleGrid>

      {/* Calls Due Today */}
      <Paper withBorder p="md" radius="md">
        <Group gap="sm" mb="sm">
          <IconPhoneCall size={20} />
          <Title order={4}>Calls Due Today</Title>
          <Badge color="blue" variant="light" size="sm">{dashboard?.due_today.length ?? 0}</Badge>
        </Group>
        {!dashboard?.due_today.length ? (
          <Text c="dimmed" size="sm">No calls scheduled for today.</Text>
        ) : (
          <Table.ScrollContainer minWidth={700}>
            <Table striped highlightOnHover>
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>Client</Table.Th>
                  <Table.Th>Phone</Table.Th>
                  <Table.Th>Invoice</Table.Th>
                  <Table.Th>Balance</Table.Th>
                  <Table.Th>Calls Made</Table.Th>
                  <Table.Th>Status</Table.Th>
                  <Table.Th>Action</Table.Th>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {dashboard.due_today.map((f) => (
                  <Table.Tr key={f.id}>
                    <Table.Td fw={500}>{f.client_name}</Table.Td>
                    <Table.Td>{f.client_phone || '—'}</Table.Td>
                    <Table.Td>{f.document_number}</Table.Td>
                    <Table.Td fw={600} c="red">{formatCurrency(f.invoice_balance)}</Table.Td>
                    <Table.Td>
                      <Badge color={f.call_count! >= 3 ? 'red' : 'gray'} variant="light" size="sm">
                        {f.call_count}/3
                      </Badge>
                    </Table.Td>
                    <Table.Td>
                      <Badge color={statusColors[f.status]} size="sm">{f.status}</Badge>
                    </Table.Td>
                    <Table.Td>
                      <Group gap="xs">
                        <Tooltip label="Log Call">
                          <ActionIcon color="green" variant="light" onClick={() => openLogModal(f)}>
                            <IconPlayerPlay size={16} />
                          </ActionIcon>
                        </Tooltip>
                        <Tooltip label="Cancel">
                          <ActionIcon color="gray" variant="light" onClick={() => cancelMutation.mutate(f.id)}>
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

      {/* Overdue Follow-ups */}
      {(dashboard?.overdue_followups.length ?? 0) > 0 && (
        <Paper withBorder p="md" radius="md">
          <Group gap="sm" mb="sm">
            <IconAlertTriangle size={20} color="var(--mantine-color-red-6)" />
            <Title order={4}>Overdue Follow-ups</Title>
            <Badge color="red" variant="light" size="sm">{dashboard!.overdue_followups.length}</Badge>
          </Group>
          <Table.ScrollContainer minWidth={700}>
            <Table striped highlightOnHover>
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>Client</Table.Th>
                  <Table.Th>Phone</Table.Th>
                  <Table.Th>Invoice</Table.Th>
                  <Table.Th>Balance</Table.Th>
                  <Table.Th>Scheduled</Table.Th>
                  <Table.Th>Calls</Table.Th>
                  <Table.Th>Action</Table.Th>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {dashboard!.overdue_followups.map((f) => (
                  <Table.Tr key={f.id}>
                    <Table.Td fw={500}>{f.client_name}</Table.Td>
                    <Table.Td>{f.client_phone || '—'}</Table.Td>
                    <Table.Td>{f.document_number}</Table.Td>
                    <Table.Td fw={600} c="red">{formatCurrency(f.invoice_balance)}</Table.Td>
                    <Table.Td>
                      <Badge color="red" variant="light" size="sm">
                        {f.next_followup ? formatDate(f.next_followup) : '—'}
                      </Badge>
                    </Table.Td>
                    <Table.Td>
                      <Badge color={f.call_count! >= 3 ? 'red' : 'gray'} variant="light" size="sm">
                        {f.call_count}/3
                      </Badge>
                    </Table.Td>
                    <Table.Td>
                      <Tooltip label="Log Call">
                        <ActionIcon color="green" variant="light" onClick={() => openLogModal(f)}>
                          <IconPlayerPlay size={16} />
                        </ActionIcon>
                      </Tooltip>
                    </Table.Td>
                  </Table.Tr>
                ))}
              </Table.Tbody>
            </Table>
          </Table.ScrollContainer>
        </Paper>
      )}

      {/* Full History */}
      <Paper withBorder p="md" radius="md">
        <Group justify="space-between" mb="sm">
          <Title order={4}>Follow-up History</Title>
          <Group gap="sm">
            <Select
              size="xs"
              w={130}
              value={filterStatus}
              onChange={(v) => { setFilterStatus(v || 'all'); setPage(1); }}
              data={[
                { value: 'all', label: 'All Status' },
                { value: 'pending', label: 'Pending' },
                { value: 'open', label: 'Open' },
                { value: 'fulfilled', label: 'Fulfilled' },
                { value: 'broken', label: 'Broken' },
                { value: 'escalated', label: 'Escalated' },
                { value: 'cancelled', label: 'Cancelled' },
              ]}
            />
            <Select
              size="xs"
              w={140}
              value={filterOutcome}
              onChange={(v) => { setFilterOutcome(v || 'all'); setPage(1); }}
              data={[
                { value: 'all', label: 'All Outcomes' },
                { value: 'promised', label: 'Promised' },
                { value: 'declined', label: 'Declined' },
                { value: 'no_answer', label: 'No Answer' },
                { value: 'disputed', label: 'Disputed' },
                { value: 'partial_payment', label: 'Partial Payment' },
              ]}
            />
          </Group>
        </Group>

        {histLoading ? (
          <Center py="md"><Loader size="sm" /></Center>
        ) : !history?.data?.length ? (
          <Text c="dimmed" size="sm">No follow-up records yet.</Text>
        ) : (
          <>
            <Table.ScrollContainer minWidth={800}>
              <Table striped highlightOnHover>
                <Table.Thead>
                  <Table.Tr>
                    <Table.Th>Date</Table.Th>
                    <Table.Th>Client</Table.Th>
                    <Table.Th>Invoice</Table.Th>
                    <Table.Th>Balance</Table.Th>
                    <Table.Th>Called By</Table.Th>
                    <Table.Th>Outcome</Table.Th>
                    <Table.Th>Promise</Table.Th>
                    <Table.Th>Notes</Table.Th>
                    <Table.Th>Status</Table.Th>
                  </Table.Tr>
                </Table.Thead>
                <Table.Tbody>
                  {history.data.map((f: FollowupEntry) => (
                    <Table.Tr key={f.id}>
                      <Table.Td>{f.call_date ? new Date(f.call_date).toLocaleDateString() : '—'}</Table.Td>
                      <Table.Td fw={500}>{f.client_name}</Table.Td>
                      <Table.Td>{f.document_number}</Table.Td>
                      <Table.Td c="red">{formatCurrency(f.invoice_balance)}</Table.Td>
                      <Table.Td>{f.assigned_to || '—'}</Table.Td>
                      <Table.Td>
                        {f.outcome ? (
                          <Badge color={outcomeColors[f.outcome] || 'gray'} size="sm" variant="light">
                            {f.outcome.replace('_', ' ')}
                          </Badge>
                        ) : '—'}
                      </Table.Td>
                      <Table.Td>
                        {f.promise_date ? (
                          <Text size="xs">
                            {formatDate(f.promise_date)}
                            {f.promise_amount ? ` (${formatCurrency(f.promise_amount)})` : ''}
                          </Text>
                        ) : '—'}
                      </Table.Td>
                      <Table.Td>
                        <Text size="xs" truncate maw={200}>{f.notes || '—'}</Text>
                      </Table.Td>
                      <Table.Td>
                        <Badge color={statusColors[f.status]} size="sm">{f.status}</Badge>
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

      {/* Log Call Modal */}
      <Modal
        opened={logModalOpen}
        onClose={closeLogModal}
        title={
          <Group gap="sm">
            <IconPhoneCall size={20} />
            <Text fw={600}>Log Call</Text>
          </Group>
        }
        size="lg"
      >
        {selectedFollowup && (
          <Stack gap="md">
            <Paper p="sm" radius="sm" bg="var(--mantine-color-default)">
              <Group justify="space-between">
                <div>
                  <Text size="xs" c="dimmed">Client</Text>
                  <Text fw={600}>{selectedFollowup.client_name}</Text>
                </div>
                <div>
                  <Text size="xs" c="dimmed">Phone</Text>
                  <Text fw={600}>{selectedFollowup.client_phone || 'No phone'}</Text>
                </div>
                <div>
                  <Text size="xs" c="dimmed">Invoice</Text>
                  <Text fw={600}>{selectedFollowup.document_number}</Text>
                </div>
                <div>
                  <Text size="xs" c="dimmed">Balance</Text>
                  <Text fw={700} c="red">{formatCurrency(selectedFollowup.invoice_balance)}</Text>
                </div>
              </Group>
            </Paper>

            <Select
              label="Call Outcome"
              placeholder="What happened?"
              required
              value={outcome}
              onChange={(v) => setOutcome(v || '')}
              data={[
                { value: 'promised', label: 'Promised to Pay' },
                { value: 'no_answer', label: 'No Answer' },
                { value: 'declined', label: 'Declined / Refused' },
                { value: 'disputed', label: 'Disputed Invoice' },
                { value: 'partial_payment', label: 'Will Make Partial Payment' },
              ]}
            />

            <Textarea
              label="Call Notes"
              placeholder="What did the client say? Record the conversation details..."
              required
              minRows={3}
              value={notes}
              onChange={(e) => setNotes(e.currentTarget.value)}
            />

            {(outcome === 'promised' || outcome === 'partial_payment') && (
              <Group grow>
                <DateInput
                  label="Promise Date"
                  placeholder="When will they pay?"
                  value={promiseDate}
                  onChange={setPromiseDate}
                  minDate={new Date()}
                />
                <NumberInput
                  label="Promise Amount"
                  placeholder="How much?"
                  value={promiseAmount}
                  onChange={(v) => setPromiseAmount(v as number)}
                  min={0}
                  decimalScale={2}
                />
              </Group>
            )}

            <DateInput
              label="Override Next Follow-up Date (optional)"
              description="Leave blank to use auto-scheduling rules"
              placeholder="Custom date"
              value={nextOverride}
              onChange={setNextOverride}
              minDate={new Date()}
              clearable
            />

            <Group justify="flex-end" mt="sm">
              <Button variant="default" onClick={closeLogModal}>Cancel</Button>
              <Button
                color="green"
                leftSection={<IconCheck size={16} />}
                onClick={handleLogCall}
                loading={logMutation.isPending}
                disabled={!outcome || !notes}
              >
                Log Call
              </Button>
            </Group>
          </Stack>
        )}
      </Modal>
    </Stack>
  );
}
