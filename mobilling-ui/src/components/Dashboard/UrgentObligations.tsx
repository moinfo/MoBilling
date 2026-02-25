import { Card, Table, Text, Badge } from '@mantine/core';
import { formatCurrency } from '../../utils/formatCurrency';
import { UrgentObligation } from '../../api/dashboard';

export default function UrgentObligations({ obligations }: { obligations: UrgentObligation[] }) {
  return (
    <Card withBorder>
      <Text fw={600} mb="md">Urgent Obligations</Text>
      {obligations.length === 0 ? (
        <Text c="dimmed" size="sm">No overdue or due-soon obligations</Text>
      ) : (
        <Table.ScrollContainer minWidth={500}>
          <Table>
            <Table.Thead>
              <Table.Tr>
                <Table.Th>Obligation</Table.Th>
                <Table.Th>Amount</Table.Th>
                <Table.Th>Due Date</Table.Th>
                <Table.Th>Days</Table.Th>
                <Table.Th>Status</Table.Th>
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {obligations.map((o) => {
                const days = o.days_remaining;
                const status = days < 0 ? 'EXPIRED' : days === 0 ? 'DUE TODAY' : 'DUE SOON';
                const color = days < 0 ? 'red' : days === 0 ? 'orange' : 'yellow';
                return (
                  <Table.Tr key={o.id}>
                    <Table.Td fw={500}>{o.name}</Table.Td>
                    <Table.Td>{formatCurrency(o.amount)}</Table.Td>
                    <Table.Td>{o.next_due_date}</Table.Td>
                    <Table.Td>
                      <Text c={days < 0 ? 'red' : 'orange'} fw={600} size="sm">{days}</Text>
                    </Table.Td>
                    <Table.Td>
                      <Badge color={color} size="sm">{status}</Badge>
                    </Table.Td>
                  </Table.Tr>
                );
              })}
            </Table.Tbody>
          </Table>
        </Table.ScrollContainer>
      )}
    </Card>
  );
}
