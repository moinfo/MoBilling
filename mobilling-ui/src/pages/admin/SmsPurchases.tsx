import { useState } from 'react';
import {
  Title, Table, Badge, Select, Text, Loader, Center, Paper, Group, Pagination,
} from '@mantine/core';
import { useQuery } from '@tanstack/react-query';
import { getAdminSmsPurchases, SmsPurchase } from '../../api/admin';

const statusColors: Record<string, string> = {
  pending: 'yellow',
  completed: 'green',
  failed: 'red',
};

export default function SmsPurchases() {
  const [page, setPage] = useState(1);
  const [statusFilter, setStatusFilter] = useState<string | null>(null);

  const { data, isLoading } = useQuery({
    queryKey: ['admin-sms-purchases', page, statusFilter],
    queryFn: () => getAdminSmsPurchases({
      page,
      status: statusFilter || undefined,
    }),
  });

  const purchases: SmsPurchase[] = data?.data?.data || [];
  const lastPage: number = data?.data?.last_page || 1;

  return (
    <>
      <Title order={2} mb="md">SMS Purchases</Title>
      <Text c="dimmed" mb="lg">View all SMS credit purchases across tenants.</Text>

      <Group mb="md">
        <Select
          placeholder="Filter by status"
          clearable
          value={statusFilter}
          onChange={setStatusFilter}
          data={[
            { value: 'pending', label: 'Pending' },
            { value: 'completed', label: 'Completed' },
            { value: 'failed', label: 'Failed' },
          ]}
          w={200}
        />
      </Group>

      {isLoading ? (
        <Center py="xl"><Loader /></Center>
      ) : (
        <Paper withBorder>
          <Table striped highlightOnHover>
            <Table.Thead>
              <Table.Tr>
                <Table.Th>Tenant</Table.Th>
                <Table.Th>User</Table.Th>
                <Table.Th>Package</Table.Th>
                <Table.Th>Quantity</Table.Th>
                <Table.Th>Amount (TZS)</Table.Th>
                <Table.Th>Status</Table.Th>
                <Table.Th>Date</Table.Th>
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {purchases.map((p) => (
                <Table.Tr key={p.id}>
                  <Table.Td fw={500}>{p.tenant?.name || '—'}</Table.Td>
                  <Table.Td>{p.user?.name || '—'}</Table.Td>
                  <Table.Td>{p.package_name}</Table.Td>
                  <Table.Td>{p.sms_quantity.toLocaleString()}</Table.Td>
                  <Table.Td>{Number(p.total_amount).toLocaleString()}</Table.Td>
                  <Table.Td>
                    <Badge color={statusColors[p.status]} variant="light">
                      {p.status}
                    </Badge>
                  </Table.Td>
                  <Table.Td>{new Date(p.created_at).toLocaleDateString()}</Table.Td>
                </Table.Tr>
              ))}
              {purchases.length === 0 && (
                <Table.Tr>
                  <Table.Td colSpan={7}>
                    <Text ta="center" c="dimmed" py="md">No purchases found</Text>
                  </Table.Td>
                </Table.Tr>
              )}
            </Table.Tbody>
          </Table>
        </Paper>
      )}

      {lastPage > 1 && (
        <Group justify="center" mt="md">
          <Pagination total={lastPage} value={page} onChange={setPage} />
        </Group>
      )}
    </>
  );
}
