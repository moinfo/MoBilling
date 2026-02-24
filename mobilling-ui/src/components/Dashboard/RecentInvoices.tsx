import { Card, Table, Text, Badge } from '@mantine/core';
import { formatCurrency } from '../../utils/formatCurrency';


interface Invoice {
  id: string;
  document_number: string;
  client_name: string;
  total: string;
  status: string;
  date: string;
}

const statusColors: Record<string, string> = {
  draft: 'gray', sent: 'blue', paid: 'green', partial: 'yellow', overdue: 'orange',
};

export default function RecentInvoices({ invoices }: { invoices: Invoice[] }) {
  return (
    <Card withBorder>
      <Text fw={600} mb="md">Recent Invoices</Text>
      {invoices.length === 0 ? (
        <Text c="dimmed" size="sm">No invoices yet</Text>
      ) : (
        <Table>
          <Table.Thead>
            <Table.Tr>
              <Table.Th>Number</Table.Th>
              <Table.Th>Client</Table.Th>
              <Table.Th>Total</Table.Th>
              <Table.Th>Status</Table.Th>
            </Table.Tr>
          </Table.Thead>
          <Table.Tbody>
            {invoices.map((inv) => (
              <Table.Tr key={inv.id}>
                <Table.Td>{inv.document_number}</Table.Td>
                <Table.Td>{inv.client_name}</Table.Td>
                <Table.Td>{formatCurrency(inv.total)}</Table.Td>
                <Table.Td>
                  <Badge color={statusColors[inv.status] || 'gray'} size="sm">{inv.status}</Badge>
                </Table.Td>
              </Table.Tr>
            ))}
          </Table.Tbody>
        </Table>
      )}
    </Card>
  );
}
