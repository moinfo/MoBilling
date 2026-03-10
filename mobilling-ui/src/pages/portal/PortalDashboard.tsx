import { Stack, SimpleGrid, Paper, Text, Table, Badge, LoadingOverlay, Group, Title } from '@mantine/core';
import { useQuery } from '@tanstack/react-query';
import { IconFileInvoice, IconCash, IconAlertTriangle, IconClock, IconCalendarRepeat } from '@tabler/icons-react';
import { useNavigate } from 'react-router-dom';
import { getPortalDashboard } from '../../api/portal';
import { useAuth } from '../../context/AuthContext';

const fmt = (n: number) => n.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const fmtDate = (d: string | null) => d ? new Date(d).toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric' }) : '-';

const statusColor: Record<string, string> = {
  sent: 'blue', viewed: 'cyan', partial: 'orange', paid: 'green', overdue: 'red',
};

export default function PortalDashboard() {
  const { user } = useAuth();
  const navigate = useNavigate();
  const { data, isLoading } = useQuery({
    queryKey: ['portal-dashboard'],
    queryFn: () => getPortalDashboard(),
  });

  const d = data?.data;

  return (
    <Stack gap="lg" pos="relative">
      <LoadingOverlay visible={isLoading} />
      <Group justify="space-between">
        <Title order={3}>Welcome, {user?.name}</Title>
      </Group>

      {d && (
        <>
          <SimpleGrid cols={{ base: 1, xs: 2, md: 4 }}>
            <StatCard label="Total Invoiced" value={fmt(d.total_invoiced)} icon={<IconFileInvoice size={24} />} color="blue" />
            <StatCard label="Total Paid" value={fmt(d.total_paid)} icon={<IconCash size={24} />} color="green" />
            <StatCard label="Outstanding Balance" value={fmt(d.total_balance)} icon={<IconAlertTriangle size={24} />} color="orange" />
            <StatCard label="Overdue Invoices" value={d.overdue_count} icon={<IconClock size={24} />} color="red" />
          </SimpleGrid>

          <SimpleGrid cols={{ base: 1, md: 2 }}>
            <Paper withBorder p="md">
              <Text fw={600} mb="md">Recent Invoices</Text>
              <Table striped highlightOnHover>
                <Table.Thead>
                  <Table.Tr>
                    <Table.Th>Invoice #</Table.Th>
                    <Table.Th>Description</Table.Th>
                    <Table.Th ta="right">Total</Table.Th>
                    <Table.Th ta="right">Balance</Table.Th>
                    <Table.Th>Status</Table.Th>
                  </Table.Tr>
                </Table.Thead>
                <Table.Tbody>
                  {d.recent_invoices.map((inv) => (
                    <Table.Tr key={inv.id} onClick={() => navigate('/portal/invoices')} style={{ cursor: 'pointer' }}>
                      <Table.Td>{inv.document_number}</Table.Td>
                      <Table.Td c="dimmed" maw={180} style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                        {(inv as any).description || '-'}
                      </Table.Td>
                      <Table.Td ta="right">{fmt(inv.total)}</Table.Td>
                      <Table.Td ta="right" fw={600} c={inv.balance > 0 ? 'red' : undefined}>
                        {fmt(inv.balance)}
                      </Table.Td>
                      <Table.Td>
                        <Badge color={statusColor[inv.status] || 'gray'} variant="light" size="sm">
                          {inv.status}
                        </Badge>
                      </Table.Td>
                    </Table.Tr>
                  ))}
                </Table.Tbody>
              </Table>
            </Paper>

            <Paper withBorder p="md">
              <Text fw={600} mb="md">Recent Payments</Text>
              <Table striped highlightOnHover>
                <Table.Thead>
                  <Table.Tr>
                    <Table.Th>Date</Table.Th>
                    <Table.Th ta="right">Amount</Table.Th>
                    <Table.Th>Method</Table.Th>
                    <Table.Th>Reference</Table.Th>
                  </Table.Tr>
                </Table.Thead>
                <Table.Tbody>
                  {d.recent_payments.map((p) => (
                    <Table.Tr key={p.id}>
                      <Table.Td>{fmtDate(p.payment_date)}</Table.Td>
                      <Table.Td ta="right" fw={600}>{fmt(p.amount)}</Table.Td>
                      <Table.Td tt="capitalize">{p.payment_method || '-'}</Table.Td>
                      <Table.Td>{p.reference || '-'}</Table.Td>
                    </Table.Tr>
                  ))}
                </Table.Tbody>
              </Table>
            </Paper>
          </SimpleGrid>

          {d.upcoming_subscriptions?.length > 0 && (
            <Paper withBorder p="md">
              <Group gap="xs" mb="md">
                <IconCalendarRepeat size={20} />
                <Text fw={600}>Subscription Schedule</Text>
              </Group>
              <Table striped highlightOnHover>
                <Table.Thead>
                  <Table.Tr>
                    <Table.Th>Service</Table.Th>
                    <Table.Th>Label</Table.Th>
                    <Table.Th>Schedule</Table.Th>
                    <Table.Th ta="right">Amount</Table.Th>
                    <Table.Th>Next Invoice</Table.Th>
                    <Table.Th ta="right">Days Left</Table.Th>
                  </Table.Tr>
                </Table.Thead>
                <Table.Tbody>
                  {d.upcoming_subscriptions.map((s: any) => {
                    const daysLeft = s.next_invoice_date
                      ? Math.ceil((new Date(s.next_invoice_date).getTime() - Date.now()) / 86400000)
                      : null;
                    return (
                      <Table.Tr key={s.id}>
                        <Table.Td>{s.service || '-'}</Table.Td>
                        <Table.Td>{s.label || '-'}</Table.Td>
                        <Table.Td>
                          <Badge variant="light" color="gray" size="sm">{s.schedule || '-'}</Badge>
                        </Table.Td>
                        <Table.Td ta="right" fw={600}>{fmt(s.price * s.quantity)}</Table.Td>
                        <Table.Td fw={600} c={s.next_invoice_date ? 'blue' : undefined}>
                          {fmtDate(s.next_invoice_date)}
                        </Table.Td>
                        <Table.Td ta="right">
                          {daysLeft !== null && (
                            <Badge
                              variant="light"
                              color={daysLeft <= 3 ? 'red' : daysLeft <= 7 ? 'orange' : 'blue'}
                              size="sm"
                            >
                              {daysLeft <= 0 ? 'Due today' : `${daysLeft} days`}
                            </Badge>
                          )}
                        </Table.Td>
                      </Table.Tr>
                    );
                  })}
                </Table.Tbody>
              </Table>
            </Paper>
          )}
        </>
      )}
    </Stack>
  );
}

function StatCard({ label, value, icon, color }: { label: string; value: string | number; icon: React.ReactNode; color: string }) {
  return (
    <Paper withBorder p="md" radius="md">
      <Group justify="space-between">
        <div>
          <Text size="xs" c="dimmed" tt="uppercase" fw={700}>{label}</Text>
          <Text fw={700} size="xl">{value}</Text>
        </div>
        <Text c={color}>{icon}</Text>
      </Group>
    </Paper>
  );
}
