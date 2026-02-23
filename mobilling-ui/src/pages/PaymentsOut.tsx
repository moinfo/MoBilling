import { Title, Table, Text, Group, Pagination, Badge } from '@mantine/core';
import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { getPaymentsOut, PaymentOut } from '../api/bills';
import { formatCurrency } from '../utils/formatCurrency';
import { formatDate } from '../utils/formatDate';

export default function PaymentsOut() {
  const [page, setPage] = useState(1);

  const { data } = useQuery({
    queryKey: ['payments-out', page],
    queryFn: () => getPaymentsOut({ page }),
  });

  const payments: PaymentOut[] = data?.data?.data || [];
  const meta = data?.data?.meta;

  return (
    <>
      <Title order={2} mb="md">Payment History</Title>

      {payments.length === 0 ? (
        <Text c="dimmed" ta="center" py="xl">No payment history</Text>
      ) : (
        <Table striped highlightOnHover>
          <Table.Thead>
            <Table.Tr>
              <Table.Th>Date</Table.Th>
              <Table.Th>Bill</Table.Th>
              <Table.Th>Amount</Table.Th>
              <Table.Th>Method</Table.Th>
              <Table.Th>Reference</Table.Th>
            </Table.Tr>
          </Table.Thead>
          <Table.Tbody>
            {payments.map((p) => (
              <Table.Tr key={p.id}>
                <Table.Td>{formatDate(p.payment_date)}</Table.Td>
                <Table.Td fw={500}>{p.bill?.name || '—'}</Table.Td>
                <Table.Td>{formatCurrency(p.amount)}</Table.Td>
                <Table.Td>
                  <Badge variant="light" size="sm">{p.payment_method}</Badge>
                </Table.Td>
                <Table.Td>{p.reference || '—'}</Table.Td>
              </Table.Tr>
            ))}
          </Table.Tbody>
        </Table>
      )}

      {meta && meta.last_page > 1 && (
        <Group justify="center" mt="md">
          <Pagination total={meta.last_page} value={page} onChange={setPage} />
        </Group>
      )}
    </>
  );
}
