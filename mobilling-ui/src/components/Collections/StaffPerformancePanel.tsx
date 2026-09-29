import { useState } from 'react';
import { Paper, Group, Title, Table, Badge, Text, Center, Loader } from '@mantine/core';
import { DateInput } from '@mantine/dates';
import { useQuery } from '@tanstack/react-query';
import dayjs from 'dayjs';
import { getStaffPerformance } from '../../api/followups';

/** On-time vs late follow-up call logging, per staff member (FollowupController::staffPerformance). */
export default function StaffPerformancePanel() {
  const [dateFrom, setDateFrom] = useState<string>('');
  const [dateTo, setDateTo] = useState<string>('');

  const { data, isLoading } = useQuery({
    queryKey: ['staff-performance', dateFrom, dateTo],
    queryFn: () => getStaffPerformance({ date_from: dateFrom || undefined, date_to: dateTo || undefined }),
  });
  const rows = data?.data?.data ?? [];

  return (
    <Paper withBorder p="md" radius="md">
      <Group justify="space-between" mb="sm">
        <Title order={4}>Staff Performance — on-time vs late follow-up calls</Title>
        <Group gap="sm">
          <DateInput
            label="From" size="xs" w={140} clearable
            value={dateFrom ? new Date(dateFrom) : null}
            onChange={(v) => setDateFrom(v ? dayjs(v).format('YYYY-MM-DD') : '')}
          />
          <DateInput
            label="To" size="xs" w={140} clearable
            value={dateTo ? new Date(dateTo) : null}
            onChange={(v) => setDateTo(v ? dayjs(v).format('YYYY-MM-DD') : '')}
          />
        </Group>
      </Group>

      {isLoading ? (
        <Center py="md"><Loader size="sm" /></Center>
      ) : !rows.length ? (
        <Text c="dimmed" size="sm">No logged calls in this period.</Text>
      ) : (
        <Table.ScrollContainer minWidth={600}>
          <Table striped highlightOnHover>
            <Table.Thead>
              <Table.Tr>
                <Table.Th>Staff</Table.Th>
                <Table.Th>Calls Logged</Table.Th>
                <Table.Th>On Time</Table.Th>
                <Table.Th>Late</Table.Th>
                <Table.Th>Avg Days Late</Table.Th>
                <Table.Th>Still Overdue</Table.Th>
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {rows.map((r) => (
                <Table.Tr key={r.user_id}>
                  <Table.Td fw={500}>{r.user_name || '—'}</Table.Td>
                  <Table.Td>{r.calls_logged}</Table.Td>
                  <Table.Td>
                    <Badge color="green" variant="light" size="sm">
                      {r.on_time} {r.on_time_pct !== null ? `(${r.on_time_pct}%)` : ''}
                    </Badge>
                  </Table.Td>
                  <Table.Td>
                    {r.late > 0 ? (
                      <Badge color="red" variant="light" size="sm">{r.late}</Badge>
                    ) : '—'}
                  </Table.Td>
                  <Table.Td>{r.avg_days_late !== null ? `${r.avg_days_late}d` : '—'}</Table.Td>
                  <Table.Td>
                    {r.still_overdue > 0 ? (
                      <Badge color="orange" variant="light" size="sm">{r.still_overdue}</Badge>
                    ) : '—'}
                  </Table.Td>
                </Table.Tr>
              ))}
            </Table.Tbody>
          </Table>
        </Table.ScrollContainer>
      )}
    </Paper>
  );
}
