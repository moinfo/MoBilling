import {
  Title, Text, Group, Badge, Table, Paper, SimpleGrid, Stack,
  Loader, Center, ThemeIcon, Progress, RingProgress, Button,
  ActionIcon, Tooltip,
} from '@mantine/core';
import { useQuery } from '@tanstack/react-query';
import { useNavigate } from 'react-router-dom';
import {
  IconCash, IconCalendarDue, IconAlertTriangle, IconTrendingUp,
  IconReceipt, IconClock, IconPhoneCall, IconArrowRight,
} from '@tabler/icons-react';
import { getCollectionDashboard } from '../api/collection';
import { getFollowupDashboard } from '../api/followups';
import { formatCurrency } from '../utils/formatCurrency';
import { formatDate } from '../utils/formatDate';

export default function Collection() {
  const navigate = useNavigate();

  const { data, isLoading } = useQuery({
    queryKey: ['collection-dashboard'],
    queryFn: getCollectionDashboard,
  });

  const { data: followupData } = useQuery({
    queryKey: ['followup-dashboard'],
    queryFn: getFollowupDashboard,
  });

  if (isLoading) {
    return <Center py="xl"><Loader /></Center>;
  }

  const dashboard = data?.data?.data;
  if (!dashboard) {
    return <Text c="dimmed" ta="center" py="xl">No data available.</Text>;
  }

  const followups = followupData?.data?.data;

  const { summary } = dashboard;
  const monthProgress = summary.month_target > 0
    ? Math.round((summary.month_collected / summary.month_target) * 100)
    : 0;
  const todayProgress = summary.today_due > 0
    ? Math.round((summary.today_due_paid / summary.today_due) * 100)
    : 0;

  return (
    <Stack gap="lg">
      <Title order={2}>Collection</Title>

      {/* Summary Cards */}
      <SimpleGrid cols={{ base: 1, xs: 2, md: 4 }}>
        <Paper withBorder p="md" radius="md">
          <Group gap="sm" mb="xs">
            <ThemeIcon variant="light" color="blue" size="lg" radius="md">
              <IconCalendarDue size={20} />
            </ThemeIcon>
            <div>
              <Text size="xs" c="dimmed" tt="uppercase" fw={600}>Due Today</Text>
              <Text size="lg" fw={700}>{formatCurrency(summary.today_due)}</Text>
            </div>
          </Group>
          <Progress value={todayProgress} color="blue" size="sm" radius="xl" />
          <Text size="xs" c="dimmed" mt={4}>
            {formatCurrency(summary.today_due_paid)} collected ({todayProgress}%)
          </Text>
        </Paper>

        <Paper withBorder p="md" radius="md">
          <Group gap="sm" mb="xs">
            <ThemeIcon variant="light" color="green" size="lg" radius="md">
              <IconCash size={20} />
            </ThemeIcon>
            <div>
              <Text size="xs" c="dimmed" tt="uppercase" fw={600}>Collected Today</Text>
              <Text size="lg" fw={700}>{formatCurrency(summary.today_collected)}</Text>
            </div>
          </Group>
          <Text size="xs" c="dimmed">
            {dashboard.today_payments.length} payment(s) received
          </Text>
        </Paper>

        <Paper withBorder p="md" radius="md">
          <Group gap="sm" mb="xs">
            <ThemeIcon variant="light" color="red" size="lg" radius="md">
              <IconAlertTriangle size={20} />
            </ThemeIcon>
            <div>
              <Text size="xs" c="dimmed" tt="uppercase" fw={600}>Overdue</Text>
              <Text size="lg" fw={700}>{formatCurrency(summary.overdue_balance)}</Text>
            </div>
          </Group>
          <Text size="xs" c="dimmed">
            {dashboard.overdue.length} invoice(s) past due
          </Text>
        </Paper>

        <Paper withBorder p="md" radius="md">
          <Group gap="sm" mb="xs">
            <ThemeIcon variant="light" color="violet" size="lg" radius="md">
              <IconTrendingUp size={20} />
            </ThemeIcon>
            <div>
              <Text size="xs" c="dimmed" tt="uppercase" fw={600}>Month Target</Text>
              <Text size="lg" fw={700}>{formatCurrency(summary.month_target)}</Text>
            </div>
          </Group>
          <Progress value={monthProgress} color="violet" size="sm" radius="xl" />
          <Text size="xs" c="dimmed" mt={4}>
            {formatCurrency(summary.month_collected)} collected ({monthProgress}%)
          </Text>
        </Paper>
      </SimpleGrid>

      {/* Calls Due Today — prominent at the top */}
      {(followups?.due_today.length ?? 0) + (followups?.overdue_followups.length ?? 0) > 0 && (
        <Paper withBorder p="md" radius="md" style={{ borderColor: 'var(--mantine-color-orange-4)' }}>
          <Group justify="space-between" mb="sm">
            <Group gap="sm">
              <IconPhoneCall size={20} color="var(--mantine-color-orange-6)" />
              <Title order={4}>Calls to Make</Title>
              <Badge color="orange" variant="filled" size="sm">
                {(followups?.due_today.length ?? 0) + (followups?.overdue_followups.length ?? 0)}
              </Badge>
            </Group>
            <Button
              variant="light"
              size="xs"
              rightSection={<IconArrowRight size={14} />}
              onClick={() => navigate('/followups')}
            >
              View All
            </Button>
          </Group>
          <Table.ScrollContainer minWidth={500}>
            <Table striped highlightOnHover>
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>Client</Table.Th>
                  <Table.Th>Phone</Table.Th>
                  <Table.Th>Invoice</Table.Th>
                  <Table.Th>Balance</Table.Th>
                  <Table.Th>Calls</Table.Th>
                  <Table.Th>Status</Table.Th>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {[...(followups?.due_today ?? []), ...(followups?.overdue_followups ?? [])].slice(0, 10).map((f) => (
                  <Table.Tr key={f.id} onClick={() => navigate('/followups')} style={{ cursor: 'pointer' }}>
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
                      <Badge color={f.status === 'broken' ? 'red' : 'orange'} size="sm">
                        {f.status === 'broken' ? 'broken promise' : f.status}
                      </Badge>
                    </Table.Td>
                  </Table.Tr>
                ))}
              </Table.Tbody>
            </Table>
          </Table.ScrollContainer>
        </Paper>
      )}

      {/* Month Overview Ring */}
      <SimpleGrid cols={{ base: 1, md: 2 }}>
        <Paper withBorder p="md" radius="md">
          <Title order={5} mb="sm">Monthly Progress</Title>
          <Group justify="center" gap="xl">
            <RingProgress
              size={140}
              thickness={14}
              roundCaps
              sections={[
                { value: monthProgress, color: 'violet' },
              ]}
              label={
                <Text ta="center" fw={700} size="lg">{monthProgress}%</Text>
              }
            />
            <Stack gap="xs">
              <div>
                <Text size="xs" c="dimmed">Target</Text>
                <Text fw={600}>{formatCurrency(summary.month_target)}</Text>
              </div>
              <div>
                <Text size="xs" c="dimmed">Collected</Text>
                <Text fw={600} c="green">{formatCurrency(summary.month_collected)}</Text>
              </div>
              <div>
                <Text size="xs" c="dimmed">Remaining</Text>
                <Text fw={600} c="red">{formatCurrency(summary.month_balance)}</Text>
              </div>
            </Stack>
          </Group>
        </Paper>

        <Paper withBorder p="md" radius="md">
          <Title order={5} mb="sm">Today's Progress</Title>
          <Group justify="center" gap="xl">
            <RingProgress
              size={140}
              thickness={14}
              roundCaps
              sections={[
                { value: todayProgress, color: 'blue' },
              ]}
              label={
                <Text ta="center" fw={700} size="lg">{todayProgress}%</Text>
              }
            />
            <Stack gap="xs">
              <div>
                <Text size="xs" c="dimmed">Due Today</Text>
                <Text fw={600}>{formatCurrency(summary.today_due)}</Text>
              </div>
              <div>
                <Text size="xs" c="dimmed">Paid</Text>
                <Text fw={600} c="green">{formatCurrency(summary.today_due_paid)}</Text>
              </div>
              <div>
                <Text size="xs" c="dimmed">Balance</Text>
                <Text fw={600} c="red">{formatCurrency(summary.today_balance)}</Text>
              </div>
            </Stack>
          </Group>
        </Paper>
      </SimpleGrid>

      {/* Today's Due Invoices */}
      <Paper withBorder p="md" radius="md">
        <Group gap="sm" mb="sm">
          <IconCalendarDue size={20} />
          <Title order={4}>Due Today</Title>
          <Badge color="blue" variant="light" size="sm">{dashboard.today_due.length}</Badge>
        </Group>
        {dashboard.today_due.length === 0 ? (
          <Text c="dimmed" size="sm">No invoices due today.</Text>
        ) : (
          <Table.ScrollContainer minWidth={500}>
            <Table striped highlightOnHover>
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>Invoice</Table.Th>
                  <Table.Th>Client</Table.Th>
                  <Table.Th>Total</Table.Th>
                  <Table.Th>Paid</Table.Th>
                  <Table.Th>Balance</Table.Th>
                  <Table.Th>Status</Table.Th>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {dashboard.today_due.map((inv) => (
                  <Table.Tr key={inv.id}>
                    <Table.Td fw={500}>{inv.document_number}</Table.Td>
                    <Table.Td>{inv.client_name}</Table.Td>
                    <Table.Td>{formatCurrency(inv.total)}</Table.Td>
                    <Table.Td c="green">{formatCurrency(inv.paid_amount)}</Table.Td>
                    <Table.Td fw={600} c="red">{formatCurrency(inv.balance_due)}</Table.Td>
                    <Table.Td>
                      <Badge color={inv.status === 'partially_paid' ? 'yellow' : 'blue'} size="sm">
                        {inv.status.replace('_', ' ')}
                      </Badge>
                    </Table.Td>
                  </Table.Tr>
                ))}
              </Table.Tbody>
            </Table>
          </Table.ScrollContainer>
        )}
      </Paper>

      {/* Today's Payments */}
      <Paper withBorder p="md" radius="md">
        <Group gap="sm" mb="sm">
          <IconReceipt size={20} />
          <Title order={4}>Today's Payments</Title>
          <Badge color="green" variant="light" size="sm">{dashboard.today_payments.length}</Badge>
        </Group>
        {dashboard.today_payments.length === 0 ? (
          <Text c="dimmed" size="sm">No payments received today.</Text>
        ) : (
          <Table.ScrollContainer minWidth={400}>
            <Table striped highlightOnHover>
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>Client</Table.Th>
                  <Table.Th>Invoice</Table.Th>
                  <Table.Th>Amount</Table.Th>
                  <Table.Th>Method</Table.Th>
                  <Table.Th>Reference</Table.Th>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {dashboard.today_payments.map((p) => (
                  <Table.Tr key={p.id}>
                    <Table.Td>{p.client_name || '—'}</Table.Td>
                    <Table.Td fw={500}>{p.document_number || '—'}</Table.Td>
                    <Table.Td fw={600} c="green">{formatCurrency(p.amount)}</Table.Td>
                    <Table.Td>{p.payment_method || '—'}</Table.Td>
                    <Table.Td>{p.reference || '—'}</Table.Td>
                  </Table.Tr>
                ))}
              </Table.Tbody>
            </Table>
          </Table.ScrollContainer>
        )}
      </Paper>

      {/* Overdue */}
      <Paper withBorder p="md" radius="md">
        <Group gap="sm" mb="sm">
          <IconAlertTriangle size={20} color="var(--mantine-color-red-6)" />
          <Title order={4}>Overdue</Title>
          <Badge color="red" variant="light" size="sm">{dashboard.overdue.length}</Badge>
        </Group>
        {dashboard.overdue.length === 0 ? (
          <Text c="dimmed" size="sm">No overdue invoices.</Text>
        ) : (
          <Table.ScrollContainer minWidth={600}>
            <Table striped highlightOnHover>
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>Invoice</Table.Th>
                  <Table.Th>Client</Table.Th>
                  <Table.Th>Due Date</Table.Th>
                  <Table.Th>Days Overdue</Table.Th>
                  <Table.Th>Total</Table.Th>
                  <Table.Th>Paid</Table.Th>
                  <Table.Th>Balance</Table.Th>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {dashboard.overdue.map((inv) => (
                  <Table.Tr key={inv.id}>
                    <Table.Td fw={500}>{inv.document_number}</Table.Td>
                    <Table.Td>{inv.client_name}</Table.Td>
                    <Table.Td>{inv.due_date ? formatDate(inv.due_date) : '—'}</Table.Td>
                    <Table.Td>
                      <Badge color="red" variant="light" size="sm">
                        {inv.days_overdue}d overdue
                      </Badge>
                    </Table.Td>
                    <Table.Td>{formatCurrency(inv.total)}</Table.Td>
                    <Table.Td c="green">{formatCurrency(inv.paid_amount)}</Table.Td>
                    <Table.Td fw={600} c="red">{formatCurrency(inv.balance_due)}</Table.Td>
                  </Table.Tr>
                ))}
              </Table.Tbody>
            </Table>
          </Table.ScrollContainer>
        )}
      </Paper>

      {/* Upcoming */}
      <Paper withBorder p="md" radius="md">
        <Group gap="sm" mb="sm">
          <IconClock size={20} />
          <Title order={4}>Upcoming (Next 30 Days)</Title>
          <Badge color="gray" variant="light" size="sm">{dashboard.upcoming.length}</Badge>
        </Group>
        {dashboard.upcoming.length === 0 ? (
          <Text c="dimmed" size="sm">No upcoming invoices in the next 30 days.</Text>
        ) : (
          <Table.ScrollContainer minWidth={600}>
            <Table striped highlightOnHover>
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>Invoice</Table.Th>
                  <Table.Th>Client</Table.Th>
                  <Table.Th>Due Date</Table.Th>
                  <Table.Th>Days Left</Table.Th>
                  <Table.Th>Total</Table.Th>
                  <Table.Th>Balance</Table.Th>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {dashboard.upcoming.map((inv) => (
                  <Table.Tr key={inv.id}>
                    <Table.Td fw={500}>{inv.document_number}</Table.Td>
                    <Table.Td>{inv.client_name}</Table.Td>
                    <Table.Td>{inv.due_date ? formatDate(inv.due_date) : '—'}</Table.Td>
                    <Table.Td>
                      <Badge
                        color={inv.days_until_due! <= 3 ? 'orange' : inv.days_until_due! <= 7 ? 'yellow' : 'gray'}
                        variant="light"
                        size="sm"
                      >
                        {inv.days_until_due}d left
                      </Badge>
                    </Table.Td>
                    <Table.Td>{formatCurrency(inv.total)}</Table.Td>
                    <Table.Td fw={600}>{formatCurrency(inv.balance_due)}</Table.Td>
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
