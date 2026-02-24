import { Card, Table, Text, Badge } from '@mantine/core';
import type { UpcomingRenewal } from '../../api/dashboard';
import { formatCurrency } from '../../utils/formatCurrency';
import { formatDate } from '../../utils/formatDate';

interface Props {
  data: UpcomingRenewal[];
}

export default function UpcomingRenewals({ data }: Props) {
  return (
    <Card withBorder padding="lg" radius="md">
      <Text fw={600} mb="md">Upcoming Renewals</Text>
      {data.length === 0 ? (
        <Text c="dimmed" size="sm">No upcoming renewals</Text>
      ) : (
        <Table>
          <Table.Thead>
            <Table.Tr>
              <Table.Th>Client</Table.Th>
              <Table.Th>Product</Table.Th>
              <Table.Th>Next Bill</Table.Th>
              <Table.Th>Price</Table.Th>
            </Table.Tr>
          </Table.Thead>
          <Table.Tbody>
            {data.map((item, i) => (
              <Table.Tr key={i}>
                <Table.Td fw={500}>{item.client_name}</Table.Td>
                <Table.Td>
                  {item.product_name}
                  {item.label && <Badge ml="xs" variant="light" size="xs">{item.label}</Badge>}
                </Table.Td>
                <Table.Td>{formatDate(item.next_bill_date)}</Table.Td>
                <Table.Td>{formatCurrency(item.price)}</Table.Td>
              </Table.Tr>
            ))}
          </Table.Tbody>
        </Table>
      )}
    </Card>
  );
}
