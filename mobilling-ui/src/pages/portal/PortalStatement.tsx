import { useState } from 'react';
import { Stack, Paper, Title, Table, Group, LoadingOverlay, Text, Badge } from '@mantine/core';
import { DatePickerInput } from '@mantine/dates';
import { useQuery } from '@tanstack/react-query';
import dayjs from 'dayjs';
import { getPortalStatement } from '../../api/portal';

const fmt = (n: number) => n.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const fmtDate = (d: string | null) => d ? new Date(d).toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric' }) : '-';

export default function PortalStatement() {
  const [range, setRange] = useState<[string | null, string | null]>([
    dayjs().startOf('year').format('YYYY-MM-DD'),
    dayjs().endOf('month').format('YYYY-MM-DD'),
  ]);

  const params = {
    start_date: range[0] || undefined,
    end_date: range[1] || undefined,
  };

  const { data, isLoading } = useQuery({
    queryKey: ['portal-statement', params.start_date, params.end_date],
    queryFn: () => getPortalStatement(params),
  });

  const r = data?.data;

  return (
    <Stack gap="lg" pos="relative">
      <LoadingOverlay visible={isLoading} />
      <Group justify="space-between" align="flex-end">
        <Title order={3}>Account Statement</Title>
        <DatePickerInput
          type="range"
          label="Date Range"
          value={range}
          onChange={setRange}
          w={300}
        />
      </Group>

      {r && (
        <>
          <Group gap="xl">
            <Paper withBorder p="sm" radius="md">
              <Text size="xs" c="dimmed">Total Debits</Text>
              <Text fw={700} size="lg">{fmt(r.total_debits)}</Text>
            </Paper>
            <Paper withBorder p="sm" radius="md">
              <Text size="xs" c="dimmed">Total Credits</Text>
              <Text fw={700} size="lg" c="green">{fmt(r.total_credits)}</Text>
            </Paper>
            <Paper withBorder p="sm" radius="md">
              <Text size="xs" c="dimmed">Closing Balance</Text>
              <Text fw={700} size="lg" c={r.closing_balance > 0 ? 'red' : 'green'}>
                {fmt(r.closing_balance)}
              </Text>
            </Paper>
          </Group>

          <Paper withBorder p="md">
            <Table.ScrollContainer minWidth={700}>
              <Table striped highlightOnHover>
                <Table.Thead>
                  <Table.Tr>
                    <Table.Th>Date</Table.Th>
                    <Table.Th>Description</Table.Th>
                    <Table.Th>Reference</Table.Th>
                    <Table.Th ta="right">Debit</Table.Th>
                    <Table.Th ta="right">Credit</Table.Th>
                    <Table.Th ta="right">Balance</Table.Th>
                  </Table.Tr>
                </Table.Thead>
                <Table.Tbody>
                  {r.entries.map((entry, i) => (
                    <Table.Tr key={i}>
                      <Table.Td>{fmtDate(entry.date)}</Table.Td>
                      <Table.Td>
                        <Group gap="xs">
                          <Badge
                            size="xs"
                            color={entry.type === 'invoice' ? 'blue' : 'green'}
                            variant="light"
                          >
                            {entry.type}
                          </Badge>
                          {entry.description}
                        </Group>
                      </Table.Td>
                      <Table.Td>{entry.reference}</Table.Td>
                      <Table.Td ta="right">{entry.debit > 0 ? fmt(entry.debit) : '-'}</Table.Td>
                      <Table.Td ta="right" c="green">{entry.credit > 0 ? fmt(entry.credit) : '-'}</Table.Td>
                      <Table.Td ta="right" fw={600} c={entry.balance > 0 ? 'red' : 'green'}>
                        {fmt(entry.balance)}
                      </Table.Td>
                    </Table.Tr>
                  ))}
                  {r.entries.length === 0 && (
                    <Table.Tr>
                      <Table.Td colSpan={6} ta="center" c="dimmed">No entries found</Table.Td>
                    </Table.Tr>
                  )}
                </Table.Tbody>
              </Table>
            </Table.ScrollContainer>
          </Paper>
        </>
      )}
    </Stack>
  );
}
