import { useState } from 'react';
import { Title, Paper, Text, SimpleGrid, Table, Badge, Progress, SegmentedControl } from '@mantine/core';
import { useQuery } from '@tanstack/react-query';
import { getStatutorySchedule, Statutory } from '../api/statutories';
import { formatCurrency } from '../utils/formatCurrency';

type StatusFilter = 'all' | 'overdue' | 'due_soon' | 'paid' | 'upcoming';

export default function StatutorySchedule() {
  const [filter, setFilter] = useState<StatusFilter>('all');

  const { data } = useQuery({
    queryKey: ['statutory-schedule'],
    queryFn: getStatutorySchedule,
  });

  const stats = data?.data?.stats || { total: 0, overdue: 0, due_soon: 0, paid: 0 };
  const allItems: Statutory[] = data?.data?.data || [];

  const filtered = filter === 'all' ? allItems : allItems.filter((s) => s.status === filter);

  const statusColor = (status?: string) =>
    ({ overdue: 'red', due_soon: 'orange', paid: 'blue', upcoming: 'green' }[status || ''] || 'gray');

  const daysColor = (days?: number) => {
    if (days === undefined) return 'gray';
    if (days < 0) return 'red';
    if (days <= 7) return 'orange';
    return 'green';
  };


  return (
    <>
      <Title order={2} mb="md">Statutory Schedule</Title>

      <SimpleGrid cols={{ base: 2, sm: 4 }} mb="lg">
        <StatCard label="Total Active" value={stats.total} color="blue" />
        <StatCard label="Overdue" value={stats.overdue} color="red" />
        <StatCard label="Due Soon" value={stats.due_soon} color="orange" />
        <StatCard label="Paid" value={stats.paid} color="teal" />
      </SimpleGrid>

      <SegmentedControl
        value={filter}
        onChange={(v) => setFilter(v as StatusFilter)}
        data={[
          { value: 'all', label: `All (${allItems.length})` },
          { value: 'overdue', label: `Overdue (${stats.overdue})` },
          { value: 'due_soon', label: `Due Soon (${stats.due_soon})` },
          { value: 'paid', label: `Paid (${stats.paid})` },
          { value: 'upcoming', label: 'Upcoming' },
        ]}
        mb="md"
      />

      {filtered.length === 0 ? (
        <Text c="dimmed" ta="center" py="xl">No obligations match this filter</Text>
      ) : (
        <Table striped highlightOnHover>
          <Table.Thead>
            <Table.Tr>
              <Table.Th>Name</Table.Th>
              <Table.Th>Category</Table.Th>
              <Table.Th>Amount</Table.Th>
              <Table.Th>Paid</Table.Th>
              <Table.Th>Remaining</Table.Th>
              <Table.Th>Due Date</Table.Th>
              <Table.Th>Days Left</Table.Th>
              <Table.Th>Status</Table.Th>
              <Table.Th w={140}>Progress</Table.Th>
            </Table.Tr>
          </Table.Thead>
          <Table.Tbody>
            {filtered.map((s) => (
              <Table.Tr key={s.id}>
                <Table.Td fw={500}>{s.name}</Table.Td>
                <Table.Td>
                  {s.bill_category
                    ? `${s.bill_category.parent_name ? s.bill_category.parent_name + ' > ' : ''}${s.bill_category.name}`
                    : '—'}
                </Table.Td>
                <Table.Td>{formatCurrency(s.amount)}</Table.Td>
                <Table.Td>{formatCurrency(s.paid_amount ?? 0)}</Table.Td>
                <Table.Td>{formatCurrency(s.remaining_amount ?? parseFloat(s.amount))}</Table.Td>
                <Table.Td>{s.next_due_date}</Table.Td>
                <Table.Td>
                  <Text c={daysColor(s.days_remaining)} fw={600} size="sm">
                    {s.days_remaining !== undefined
                      ? s.days_remaining < 0
                        ? `${Math.abs(s.days_remaining)}d overdue`
                        : `${s.days_remaining}d`
                      : '—'}
                  </Text>
                </Table.Td>
                <Table.Td>
                  <Badge color={statusColor(s.status)} size="sm">
                    {s.status === 'due_soon' ? 'Due Soon' : s.status ? s.status.charAt(0).toUpperCase() + s.status.slice(1) : '—'}
                  </Badge>
                </Table.Td>
                <Table.Td>
                  <Progress
                    value={s.progress_percent ?? 0}
                    color={s.progress_percent === 100 ? 'teal' : 'blue'}
                    size="lg"
                    radius="xl"
                  />
                </Table.Td>
              </Table.Tr>
            ))}
          </Table.Tbody>
        </Table>
      )}
    </>
  );
}

function StatCard({ label, value, color }: { label: string; value: number; color: string }) {
  return (
    <Paper withBorder p="md" radius="md">
      <Text size="xs" c="dimmed" tt="uppercase" fw={700}>{label}</Text>
      <Text size="xl" fw={700} c={color}>{value}</Text>
    </Paper>
  );
}
