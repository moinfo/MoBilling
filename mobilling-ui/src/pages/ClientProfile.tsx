import { useParams, useNavigate } from 'react-router-dom';
import {
  Title, Text, Group, Badge, Table, Paper, SimpleGrid, Stack,
  Anchor, Loader, Center, ThemeIcon,
} from '@mantine/core';
import { useQuery } from '@tanstack/react-query';
import {
  IconArrowLeft, IconMail, IconPhone, IconMapPin, IconId,
  IconFileInvoice, IconCash, IconCalendarDue, IconRepeat,
} from '@tabler/icons-react';
import { getClientProfile, ClientProfile as ClientProfileType } from '../api/clients';
import { formatCurrency } from '../utils/formatCurrency';
import { formatDate } from '../utils/formatDate';

const cycleLabels: Record<string, string> = {
  monthly: 'Monthly',
  quarterly: 'Quarterly',
  half_yearly: 'Semi-Annual',
  yearly: 'Annually',
};

const statusColors: Record<string, string> = {
  active: 'green',
  pending: 'blue',
  cancelled: 'red',
  suspended: 'yellow',
  sent: 'blue',
  paid: 'green',
  overdue: 'red',
  draft: 'gray',
  partially_paid: 'yellow',
};

export default function ClientProfile() {
  const { clientId } = useParams<{ clientId: string }>();
  const navigate = useNavigate();

  const { data, isLoading } = useQuery({
    queryKey: ['client-profile', clientId],
    queryFn: () => getClientProfile(clientId!),
    enabled: !!clientId,
  });

  if (isLoading) {
    return <Center py="xl"><Loader /></Center>;
  }

  const profile: ClientProfileType | undefined = data?.data?.data;
  if (!profile) {
    return <Text c="dimmed" ta="center" py="xl">Client not found.</Text>;
  }

  const { client, summary, subscriptions, invoices, payments } = profile;

  return (
    <Stack gap="lg">
      {/* Header */}
      <Group>
        <Anchor onClick={() => navigate('/clients')} c="dimmed" size="sm" style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
          <IconArrowLeft size={14} /> Back to Clients
        </Anchor>
      </Group>

      <Group justify="space-between" align="flex-start" wrap="wrap">
        <div>
          <Title order={2}>{client.name}</Title>
          <Group gap="md" mt={4}>
            {client.email && (
              <Group gap={4}><IconMail size={14} color="gray" /><Text size="sm" c="dimmed">{client.email}</Text></Group>
            )}
            {client.phone && (
              <Group gap={4}><IconPhone size={14} color="gray" /><Text size="sm" c="dimmed">{client.phone}</Text></Group>
            )}
            {client.tax_id && (
              <Group gap={4}><IconId size={14} color="gray" /><Text size="sm" c="dimmed">{client.tax_id}</Text></Group>
            )}
          </Group>
          {client.address && (
            <Group gap={4} mt={2}><IconMapPin size={14} color="gray" /><Text size="sm" c="dimmed">{client.address}</Text></Group>
          )}
        </div>
      </Group>

      {/* Summary Cards */}
      <SimpleGrid cols={{ base: 2, sm: 4 }}>
        <SummaryCard icon={<IconFileInvoice size={20} />} label="Total Invoiced" value={formatCurrency(summary.total_invoiced)} color="blue" />
        <SummaryCard icon={<IconCash size={20} />} label="Total Paid" value={formatCurrency(summary.total_paid)} color="green" />
        <SummaryCard icon={<IconCalendarDue size={20} />} label="Balance Due" value={formatCurrency(summary.balance)} color={summary.balance > 0 ? 'red' : 'green'} />
        <SummaryCard icon={<IconRepeat size={20} />} label="Active Subscriptions" value={String(summary.active_subscriptions)} color="violet" />
      </SimpleGrid>

      {/* Subscriptions */}
      <Paper withBorder p="md" radius="md">
        <Title order={4} mb="sm">Subscriptions</Title>
        {subscriptions.length === 0 ? (
          <Text c="dimmed" size="sm">No subscriptions.</Text>
        ) : (
          <Table.ScrollContainer minWidth={600}>
            <Table striped highlightOnHover>
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>Product / Service</Table.Th>
                  <Table.Th>Cycle</Table.Th>
                  <Table.Th>Qty</Table.Th>
                  <Table.Th>Price</Table.Th>
                  <Table.Th>Start</Table.Th>
                  <Table.Th>Next Due</Table.Th>
                  <Table.Th>Status</Table.Th>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {subscriptions.map((sub) => (
                  <Table.Tr key={sub.id}>
                    <Table.Td>
                      <Text size="sm" fw={500}>{sub.product_service_name}</Text>
                      {sub.label && <Text size="xs" c="dimmed">{sub.label}</Text>}
                    </Table.Td>
                    <Table.Td>
                      <Badge variant="light" size="sm">{cycleLabels[sub.billing_cycle] || sub.billing_cycle}</Badge>
                    </Table.Td>
                    <Table.Td>{sub.quantity}</Table.Td>
                    <Table.Td>{formatCurrency(sub.price)}</Table.Td>
                    <Table.Td>{formatDate(sub.start_date)}</Table.Td>
                    <Table.Td fw={500}>{sub.next_bill ? formatDate(sub.next_bill) : '—'}</Table.Td>
                    <Table.Td>
                      <Badge color={statusColors[sub.status] || 'gray'} size="sm">{sub.status}</Badge>
                    </Table.Td>
                  </Table.Tr>
                ))}
              </Table.Tbody>
            </Table>
          </Table.ScrollContainer>
        )}
      </Paper>

      {/* Invoices */}
      <Paper withBorder p="md" radius="md">
        <Title order={4} mb="sm">Invoices</Title>
        {invoices.length === 0 ? (
          <Text c="dimmed" size="sm">No invoices yet.</Text>
        ) : (
          <Table.ScrollContainer minWidth={500}>
            <Table striped highlightOnHover>
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>Invoice #</Table.Th>
                  <Table.Th>Date</Table.Th>
                  <Table.Th>Due Date</Table.Th>
                  <Table.Th>Total</Table.Th>
                  <Table.Th>Status</Table.Th>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {invoices.map((inv) => (
                  <Table.Tr key={inv.id}>
                    <Table.Td fw={500}>{inv.document_number}</Table.Td>
                    <Table.Td>{formatDate(inv.date)}</Table.Td>
                    <Table.Td>{inv.due_date ? formatDate(inv.due_date) : '—'}</Table.Td>
                    <Table.Td>{formatCurrency(inv.total)}</Table.Td>
                    <Table.Td>
                      <Badge color={statusColors[inv.status] || 'gray'} size="sm">{inv.status}</Badge>
                    </Table.Td>
                  </Table.Tr>
                ))}
              </Table.Tbody>
            </Table>
          </Table.ScrollContainer>
        )}
      </Paper>

      {/* Payments */}
      <Paper withBorder p="md" radius="md">
        <Title order={4} mb="sm">Payments</Title>
        {payments.length === 0 ? (
          <Text c="dimmed" size="sm">No payments recorded.</Text>
        ) : (
          <Table.ScrollContainer minWidth={500}>
            <Table striped highlightOnHover>
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>Date</Table.Th>
                  <Table.Th>Amount</Table.Th>
                  <Table.Th>Method</Table.Th>
                  <Table.Th>Reference</Table.Th>
                  <Table.Th>Invoice</Table.Th>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {payments.map((p) => (
                  <Table.Tr key={p.id}>
                    <Table.Td>{formatDate(p.payment_date)}</Table.Td>
                    <Table.Td fw={500}>{formatCurrency(p.amount)}</Table.Td>
                    <Table.Td>{p.payment_method || '—'}</Table.Td>
                    <Table.Td>{p.reference || '—'}</Table.Td>
                    <Table.Td>{p.document_number || '—'}</Table.Td>
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

function SummaryCard({ icon, label, value, color }: { icon: React.ReactNode; label: string; value: string; color: string }) {
  return (
    <Paper withBorder p="md" radius="md">
      <Group gap="sm">
        <ThemeIcon variant="light" color={color} size="lg" radius="md">
          {icon}
        </ThemeIcon>
        <div>
          <Text size="xs" c="dimmed" tt="uppercase" fw={600}>{label}</Text>
          <Text size="lg" fw={700}>{value}</Text>
        </div>
      </Group>
    </Paper>
  );
}
