import { Stack, Paper, Title, Table, Badge, LoadingOverlay } from '@mantine/core';
import { useQuery } from '@tanstack/react-query';
import { getPortalSubscriptions } from '../../api/portal';

const fmt = (n: number) => n.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 });

const statusColor: Record<string, string> = {
  active: 'green', paused: 'yellow', cancelled: 'red',
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
        <Table striped highlightOnHover>
          <Table.Thead>
            <Table.Tr>
              <Table.Th>Service</Table.Th>
              <Table.Th>Label</Table.Th>
              <Table.Th ta="right">Qty</Table.Th>
              <Table.Th ta="right">Price</Table.Th>
              <Table.Th>Start Date</Table.Th>
              <Table.Th>Status</Table.Th>
            </Table.Tr>
          </Table.Thead>
          <Table.Tbody>
            {subs.map((s: any) => (
              <Table.Tr key={s.id}>
                <Table.Td>{s.product_service?.name || '-'}</Table.Td>
                <Table.Td>{s.label || '-'}</Table.Td>
                <Table.Td ta="right">{s.quantity}</Table.Td>
                <Table.Td ta="right">{s.product_service?.price ? fmt(s.product_service.price) : '-'}</Table.Td>
                <Table.Td>{s.start_date}</Table.Td>
                <Table.Td>
                  <Badge color={statusColor[s.status] || 'gray'} variant="light" size="sm">
                    {s.status}
                  </Badge>
                </Table.Td>
              </Table.Tr>
            ))}
            {subs.length === 0 && (
              <Table.Tr>
                <Table.Td colSpan={6} ta="center" c="dimmed">No subscriptions found</Table.Td>
              </Table.Tr>
            )}
          </Table.Tbody>
        </Table>
      </Paper>
    </Stack>
  );
}
