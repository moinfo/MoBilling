import { Card, Table, Text, Badge } from '@mantine/core';
import { formatCurrency } from '../../utils/formatCurrency';
import { formatDate } from '../../utils/formatDate';

interface BillSummary {
  id: string;
  name: string;
  amount: string;
  due_date: string;
  category: string;
}

export default function UpcomingBills({ bills }: { bills: BillSummary[] }) {
  return (
    <Card withBorder>
      <Text fw={600} mb="md">Upcoming Bills</Text>
      {bills.length === 0 ? (
        <Text c="dimmed" size="sm">No upcoming bills</Text>
      ) : (
        <Table.ScrollContainer minWidth={450}>
          <Table>
            <Table.Thead>
              <Table.Tr>
                <Table.Th>Bill</Table.Th>
                <Table.Th>Category</Table.Th>
                <Table.Th>Amount</Table.Th>
                <Table.Th>Due Date</Table.Th>
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {bills.map((bill) => (
                <Table.Tr key={bill.id}>
                  <Table.Td fw={500}>{bill.name}</Table.Td>
                  <Table.Td><Badge variant="light" size="sm">{bill.category}</Badge></Table.Td>
                  <Table.Td>{formatCurrency(bill.amount)}</Table.Td>
                  <Table.Td>{formatDate(bill.due_date)}</Table.Td>
                </Table.Tr>
              ))}
            </Table.Tbody>
          </Table>
        </Table.ScrollContainer>
      )}
    </Card>
  );
}
