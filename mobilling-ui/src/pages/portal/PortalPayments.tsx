import { useState } from 'react';
import { Stack, Paper, Title, Table, TextInput, Group, Pagination, LoadingOverlay } from '@mantine/core';
import { useQuery } from '@tanstack/react-query';
import { IconSearch } from '@tabler/icons-react';
import { getPortalPayments } from '../../api/portal';

const fmt = (n: number) => n.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 });

export default function PortalPayments() {
  const [page, setPage] = useState(1);
  const [search, setSearch] = useState('');

  const { data, isLoading } = useQuery({
    queryKey: ['portal-payments', page, search],
    queryFn: () => getPortalPayments({ page, search: search || undefined }),
  });

  const payments = data?.data?.data || [];
  const lastPage = data?.data?.last_page || 1;

  return (
    <Stack gap="lg" pos="relative">
      <LoadingOverlay visible={isLoading} />
      <Group justify="space-between">
        <Title order={3}>Payments</Title>
        <TextInput
          placeholder="Search..."
          leftSection={<IconSearch size={16} />}
          value={search}
          onChange={(e) => { setSearch(e.currentTarget.value); setPage(1); }}
          w={250}
        />
      </Group>

      <Paper withBorder p="md">
        <Table.ScrollContainer minWidth={600}>
          <Table striped highlightOnHover>
            <Table.Thead>
              <Table.Tr>
                <Table.Th>Date</Table.Th>
                <Table.Th>Invoice</Table.Th>
                <Table.Th ta="right">Amount</Table.Th>
                <Table.Th>Method</Table.Th>
                <Table.Th>Reference</Table.Th>
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {payments.map((p: any) => (
                <Table.Tr key={p.id}>
                  <Table.Td>{p.payment_date}</Table.Td>
                  <Table.Td>{p.document?.document_number || '-'}</Table.Td>
                  <Table.Td ta="right" fw={600}>{fmt(p.amount)}</Table.Td>
                  <Table.Td tt="capitalize">{p.payment_method || '-'}</Table.Td>
                  <Table.Td>{p.reference || '-'}</Table.Td>
                </Table.Tr>
              ))}
              {payments.length === 0 && (
                <Table.Tr>
                  <Table.Td colSpan={5} ta="center" c="dimmed">No payments found</Table.Td>
                </Table.Tr>
              )}
            </Table.Tbody>
          </Table>
        </Table.ScrollContainer>
        {lastPage > 1 && (
          <Group justify="center" mt="md">
            <Pagination value={page} onChange={setPage} total={lastPage} />
          </Group>
        )}
      </Paper>
    </Stack>
  );
}
