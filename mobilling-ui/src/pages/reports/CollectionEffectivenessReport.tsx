import { useState } from 'react';
import { Stack, SimpleGrid, Paper, Text, Table, Badge, LoadingOverlay } from '@mantine/core';
import { useQuery } from '@tanstack/react-query';
import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer } from 'recharts';
import { IconPhoneCall, IconHandStop, IconCheck, IconPercentage } from '@tabler/icons-react';
import dayjs from 'dayjs';
import { getCollectionEffectiveness } from '../../api/reports';
import ReportHeader from '../../components/Reports/ReportHeader';
import StatCard from '../../components/Reports/StatCard';

export default function CollectionEffectivenessReport() {
  const [range, setRange] = useState<[Date | null, Date | null]>([
    dayjs().subtract(3, 'month').startOf('month').toDate(),
    dayjs().endOf('month').toDate(),
  ]);

  const params = {
    start_date: range[0] ? dayjs(range[0]).format('YYYY-MM-DD') : dayjs().startOf('month').format('YYYY-MM-DD'),
    end_date: range[1] ? dayjs(range[1]).format('YYYY-MM-DD') : dayjs().endOf('month').format('YYYY-MM-DD'),
  };

  const { data, isLoading } = useQuery({
    queryKey: ['report-collection-effectiveness', params.start_date, params.end_date],
    queryFn: () => getCollectionEffectiveness(params),
  });

  const r = data?.data;

  const outcomeRows = r
    ? Object.entries(r.by_outcome).map(([outcome, count]) => ({ outcome, count: count as number }))
    : [];

  return (
    <Stack gap="lg" pos="relative">
      <LoadingOverlay visible={isLoading} />
      <ReportHeader
        title="Collection Effectiveness"
        dateRange={range}
        onDateChange={setRange}
        exportData={r?.followups as unknown as Record<string, unknown>[] | undefined}
        exportFilename="collection-effectiveness"
      />

      {r && (
        <>
          <SimpleGrid cols={{ base: 1, xs: 2, md: 4 }}>
            <StatCard label="Total Follow-ups" value={r.total_followups} icon={<IconPhoneCall size={24} />} color="blue" />
            <StatCard label="Promises Made" value={r.promise_count} icon={<IconHandStop size={24} />} color="orange" />
            <StatCard label="Promises Fulfilled" value={r.promises_fulfilled} icon={<IconCheck size={24} />} color="green" />
            <StatCard label="Fulfillment Rate" value={`${r.fulfillment_rate}%`} icon={<IconPercentage size={24} />} color={r.fulfillment_rate >= 50 ? 'teal' : 'red'} />
          </SimpleGrid>

          <SimpleGrid cols={{ base: 1, md: 2 }}>
            <Paper withBorder p="md">
              <Text fw={600} mb="md">Monthly Follow-up Trend</Text>
              <ResponsiveContainer width="100%" height={300}>
                <BarChart data={r.monthly_trend}>
                  <CartesianGrid strokeDasharray="3 3" />
                  <XAxis dataKey="month" />
                  <YAxis />
                  <Tooltip />
                  <Legend />
                  <Bar dataKey="total" fill="#228be6" name="Total" radius={[4, 4, 0, 0]} />
                  <Bar dataKey="promised" fill="#fd7e14" name="Promised" radius={[4, 4, 0, 0]} />
                  <Bar dataKey="paid" fill="#40c057" name="Paid" radius={[4, 4, 0, 0]} />
                </BarChart>
              </ResponsiveContainer>
            </Paper>

            <Paper withBorder p="md">
              <Text fw={600} mb="md">Outcome Breakdown</Text>
              <Table striped highlightOnHover>
                <Table.Thead>
                  <Table.Tr>
                    <Table.Th>Outcome</Table.Th>
                    <Table.Th ta="right">Count</Table.Th>
                    <Table.Th ta="right">% of Total</Table.Th>
                  </Table.Tr>
                </Table.Thead>
                <Table.Tbody>
                  {outcomeRows
                    .sort((a, b) => b.count - a.count)
                    .map((row) => (
                      <Table.Tr key={row.outcome}>
                        <Table.Td tt="capitalize">{row.outcome.replace('_', ' ')}</Table.Td>
                        <Table.Td ta="right">{row.count}</Table.Td>
                        <Table.Td ta="right">
                          {r.total_followups > 0 ? ((row.count / r.total_followups) * 100).toFixed(1) : 0}%
                        </Table.Td>
                      </Table.Tr>
                    ))}
                </Table.Tbody>
              </Table>
            </Paper>
          </SimpleGrid>

          <Paper withBorder p="md">
            <Text fw={600} mb="md">Follow-up Details</Text>
            <Table.ScrollContainer minWidth={800}>
              <Table striped highlightOnHover>
                <Table.Thead>
                  <Table.Tr>
                    <Table.Th>Date</Table.Th>
                    <Table.Th>Client</Table.Th>
                    <Table.Th>Invoice #</Table.Th>
                    <Table.Th>Outcome</Table.Th>
                    <Table.Th>Promise Date</Table.Th>
                    <Table.Th ta="right">Promise Amt</Table.Th>
                    <Table.Th>Agent</Table.Th>
                    <Table.Th>Notes</Table.Th>
                  </Table.Tr>
                </Table.Thead>
                <Table.Tbody>
                  {r.followups.map((f) => (
                    <Table.Tr key={f.id}>
                      <Table.Td>{f.call_date}</Table.Td>
                      <Table.Td>{f.client_name || '-'}</Table.Td>
                      <Table.Td>{f.document_number || '-'}</Table.Td>
                      <Table.Td>
                        <Badge
                          color={f.outcome === 'paid' ? 'green' : f.outcome === 'promised' ? 'orange' : f.outcome === 'no_answer' ? 'gray' : 'blue'}
                          variant="light"
                          tt="capitalize"
                        >
                          {f.outcome?.replace('_', ' ')}
                        </Badge>
                      </Table.Td>
                      <Table.Td>{f.promise_date || '-'}</Table.Td>
                      <Table.Td ta="right">{f.promise_amount ? f.promise_amount.toLocaleString(undefined, { minimumFractionDigits: 2 }) : '-'}</Table.Td>
                      <Table.Td>{f.agent || '-'}</Table.Td>
                      <Table.Td maw={200} style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{f.notes || '-'}</Table.Td>
                    </Table.Tr>
                  ))}
                </Table.Tbody>
              </Table>
            </Table.ScrollContainer>
          </Paper>
        </>
      )}
    </Stack>
  );
}
