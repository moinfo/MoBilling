import { Title, Table, Text, Badge, Group } from '@mantine/core';
import { useQuery } from '@tanstack/react-query';
import { getNextBills, NextBillItem } from '../api/documents';
import { formatCurrency } from '../utils/formatCurrency';
import { formatDate } from '../utils/formatDate';

const cycleLabels: Record<string, string> = {
  monthly: 'Monthly',
  quarterly: 'Quarterly',
  half_yearly: 'Semi-Annual',
  yearly: 'Annually',
};

export default function NextBills() {
  const { data } = useQuery({
    queryKey: ['next-bills'],
    queryFn: getNextBills,
  });

  const items: NextBillItem[] = data?.data?.data || [];

  return (
    <>
      <Group justify="space-between" mb="md">
        <Title order={2}>Next Bills</Title>
      </Group>

      {items.length === 0 ? (
        <Text c="dimmed" ta="center" py="xl">No active subscriptions with recurring billing found. Create an active subscription to see upcoming bills here.</Text>
      ) : (
        <Table.ScrollContainer minWidth={700}>
          <Table striped highlightOnHover>
            <Table.Thead>
              <Table.Tr>
                <Table.Th>Client</Table.Th>
                <Table.Th>Product / Service</Table.Th>
                <Table.Th>Cycle</Table.Th>
                <Table.Th>Qty</Table.Th>
                <Table.Th>Price</Table.Th>
                <Table.Th>Last Billed</Table.Th>
                <Table.Th>Next Due Date</Table.Th>
                <Table.Th>Status</Table.Th>
              </Table.Tr>
            </Table.Thead>
          <Table.Tbody>
            {items.map((item) => (
              <Table.Tr key={item.subscription_id}>
                <Table.Td>
                  <Text fw={500} size="sm">{item.client_name}</Text>
                  {item.client_email && <Text size="xs" c="dimmed">{item.client_email}</Text>}
                </Table.Td>
                <Table.Td>{item.product_service_name}</Table.Td>
                <Table.Td>
                  <Badge variant="light" size="sm">
                    {cycleLabels[item.billing_cycle] || item.billing_cycle}
                  </Badge>
                </Table.Td>
                <Table.Td>{item.quantity}</Table.Td>
                <Table.Td>{formatCurrency(item.price)}</Table.Td>
                <Table.Td>{item.last_billed ? formatDate(item.last_billed) : <Text size="sm" c="dimmed">Never</Text>}</Table.Td>
                <Table.Td fw={500}>{item.next_bill ? formatDate(item.next_bill) : '—'}</Table.Td>
                <Table.Td>
                  {item.is_overdue ? (
                    <Badge color="red" size="sm">Overdue</Badge>
                  ) : (
                    <Badge color="green" size="sm">Upcoming</Badge>
                  )}
                </Table.Td>
              </Table.Tr>
            ))}
            </Table.Tbody>
          </Table>
        </Table.ScrollContainer>
      )}
    </>
  );
}
