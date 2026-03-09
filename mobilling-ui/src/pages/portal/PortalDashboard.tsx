import { Stack, SimpleGrid, Paper, Text, Table, Badge, LoadingOverlay, Group, Title } from '@mantine/core';
import { useQuery } from '@tanstack/react-query';
import { IconFileInvoice, IconCash, IconAlertTriangle, IconClock } from '@tabler/icons-react';
import { getPortalDashboard } from '../../api/portal';
import { useAuth } from '../../context/AuthContext';

const fmt = (n: number) => n.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 });

const statusColor: Record<string, string> = {
  sent: 'blue', viewed: 'cyan', partial: 'orange', paid: 'green', overdue: 'red',
};

export default function PortalDashboard() {
  const { user } = useAuth();
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
                    <Table.Th ta="right">Total</Table.Th>
                    <Table.Th ta="right">Balance</Table.Th>
                    <Table.Th>Status</Table.Th>
                  </Table.Tr>
                </Table.Thead>
                <Table.Tbody>
                  {d.recent_invoices.map((inv) => (
                    <Table.Tr key={inv.id}>
                      <Table.Td>{inv.document_number}</Table.Td>
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
                      <Table.Td>{p.payment_date}</Table.Td>
                      <Table.Td ta="right" fw={600}>{fmt(p.amount)}</Table.Td>
                      <Table.Td tt="capitalize">{p.payment_method || '-'}</Table.Td>
                      <Table.Td>{p.reference || '-'}</Table.Td>
                    </Table.Tr>
                  ))}
                </Table.Tbody>
              </Table>
            </Paper>
          </SimpleGrid>
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
