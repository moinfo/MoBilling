import { Stack, Paper, Title, Table, Badge, LoadingOverlay } from '@mantine/core';
import { useQuery } from '@tanstack/react-query';
import { getPortalSubscriptions } from '../../api/portal';

const fmt = (n: number) => n.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const fmtDate = (d: string | null) => d ? new Date(d).toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric' }) : '-';

const statusColor: Record<string, string> = {
  active: 'green', paused: 'yellow', cancelled: 'red',
};

const cycleLabel: Record<string, string> = {
  once: 'One-time',
  monthly: 'Monthly',
  quarterly: 'Quarterly',
  half_yearly: 'Half Yearly',
  yearly: 'Yearly',
};

export default function PortalSubscriptions() {
  const { data, isLoading } = useQuery({
    queryKey: ['portal-subscriptions'],
    queryFn: () => getPortalSubscriptions(),
  });

  const subs = data?.data?.data || [];

  return (
    <Stack gap="lg" pos="relative">
      <LoadingOverlay visible={isLoading} />
      <Title order={3}>Subscriptions</Title>

      <Paper withBorder p="md">
        <Table.ScrollContainer minWidth={700}>
          <Table striped highlightOnHover>
            <Table.Thead>
              <Table.Tr>
                <Table.Th>Service</Table.Th>
                <Table.Th>Label</Table.Th>
                <Table.Th ta="right">Qty</Table.Th>
                <Table.Th ta="right">Price</Table.Th>
                <Table.Th>Schedule</Table.Th>
                <Table.Th>Start Date</Table.Th>
                <Table.Th>Next Invoice</Table.Th>
                <Table.Th ta="right">Days Left</Table.Th>
                <Table.Th>Status</Table.Th>
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {subs.map((s: any) => {
                const daysLeft = s.status === 'active' && s.next_invoice_date
                  ? Math.ceil((new Date(s.next_invoice_date).getTime() - Date.now()) / 86400000)
                  : null;
                return (
                  <Table.Tr key={s.id}>
                    <Table.Td>{s.product_service?.name || '-'}</Table.Td>
                    <Table.Td>{s.label || '-'}</Table.Td>
                    <Table.Td ta="right">{s.quantity}</Table.Td>
                    <Table.Td ta="right">{s.product_service?.price ? fmt(s.product_service.price) : '-'}</Table.Td>
                    <Table.Td>
                      <Badge variant="light" color="gray" size="sm">
                        {cycleLabel[s.billing_cycle] || s.billing_cycle || '-'}
                      </Badge>
                    </Table.Td>
                    <Table.Td>{fmtDate(s.start_date)}</Table.Td>
                    <Table.Td>{s.status === 'active' ? fmtDate(s.next_invoice_date) : '-'}</Table.Td>
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
                    <Table.Td>
                      <Badge color={statusColor[s.status] || 'gray'} variant="light" size="sm">
                        {s.status}
                      </Badge>
                    </Table.Td>
                  </Table.Tr>
                );
              })}
              {subs.length === 0 && (
                <Table.Tr>
                  <Table.Td colSpan={9} ta="center" c="dimmed">No subscriptions found</Table.Td>
                </Table.Tr>
              )}
            </Table.Tbody>
          </Table>
        </Table.ScrollContainer>
      </Paper>
    </Stack>
  );
}
