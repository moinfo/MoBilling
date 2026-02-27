import { useState } from 'react';
import { Stack, SimpleGrid, Paper, Text, Table, Badge, LoadingOverlay } from '@mantine/core';
import { useQuery } from '@tanstack/react-query';
import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer } from 'recharts';
import { IconCash, IconReceipt, IconPercentage, IconTrendingUp } from '@tabler/icons-react';
import dayjs from 'dayjs';
import { getRevenueSummary } from '../../api/reports';
import ReportHeader from '../../components/Reports/ReportHeader';
import StatCard from '../../components/Reports/StatCard';

const fmt = (n: number) => n.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 });

export default function RevenueSummary() {
  const [range, setRange] = useState<[Date | null, Date | null]>([
    dayjs().startOf('year').toDate(),
    dayjs().endOf('month').toDate(),
  ]);

  const params = {
    start_date: range[0] ? dayjs(range[0]).format('YYYY-MM-DD') : dayjs().startOf('month').format('YYYY-MM-DD'),
    end_date: range[1] ? dayjs(range[1]).format('YYYY-MM-DD') : dayjs().endOf('month').format('YYYY-MM-DD'),
  };

  const { data, isLoading } = useQuery({
    queryKey: ['report-revenue', params.start_date, params.end_date],
    queryFn: () => getRevenueSummary(params),
  });

  const r = data?.data;

  return (
    <Stack gap="lg" pos="relative">
      <LoadingOverlay visible={isLoading} />
      <ReportHeader
        title="Revenue Summary"
        dateRange={range}
        onDateChange={setRange}
        exportData={r?.invoices as unknown as Record<string, unknown>[]}
        exportFilename="revenue-summary"
      />

      {r && (
        <>
          <SimpleGrid cols={{ base: 1, xs: 2, md: 4 }}>
            <StatCard label="Total Invoiced" value={fmt(r.total_invoiced)} icon={<IconCash size={24} />} color="blue" />
            <StatCard label="Total Collected" value={fmt(r.total_collected)} icon={<IconReceipt size={24} />} color="green" />
            <StatCard label="Collection Rate" value={`${r.collection_rate}%`} icon={<IconPercentage size={24} />} color="cyan" />
            <StatCard
              label="Revenue Growth"
              value={r.revenue_growth !== null ? `${r.revenue_growth > 0 ? '+' : ''}${r.revenue_growth}%` : 'N/A'}
              icon={<IconTrendingUp size={24} />}
              color={r.revenue_growth !== null && r.revenue_growth >= 0 ? 'teal' : 'red'}
              subtitle="vs prior period"
            />
          </SimpleGrid>

          <Paper withBorder p="md">
            <Text fw={600} mb="md">Invoiced vs Collected</Text>
            <ResponsiveContainer width="100%" height={350}>
              <BarChart data={r.months}>
                <CartesianGrid strokeDasharray="3 3" />
                <XAxis dataKey="month" />
                <YAxis />
                <Tooltip formatter={(v) => fmt(Number(v))} />
                <Legend />
                <Bar dataKey="invoiced" fill="#228be6" name="Invoiced" radius={[4, 4, 0, 0]} />
                <Bar dataKey="collected" fill="#40c057" name="Collected" radius={[4, 4, 0, 0]} />
              </BarChart>
            </ResponsiveContainer>
          </Paper>

          <Paper withBorder p="md">
            <Text fw={600} mb="md">Invoices</Text>
            <Table.ScrollContainer minWidth={700}>
              <Table striped highlightOnHover>
                <Table.Thead>
                  <Table.Tr>
                    <Table.Th>Invoice #</Table.Th>
                    <Table.Th>Client</Table.Th>
                    <Table.Th>Date</Table.Th>
                    <Table.Th ta="right">Total</Table.Th>
                    <Table.Th ta="right">Paid</Table.Th>
                    <Table.Th ta="right">Balance</Table.Th>
                    <Table.Th>Status</Table.Th>
                  </Table.Tr>
                </Table.Thead>
                <Table.Tbody>
                  {r.invoices.map((inv) => (
                    <Table.Tr key={inv.id}>
                      <Table.Td>{inv.document_number}</Table.Td>
                      <Table.Td>{inv.client_name}</Table.Td>
                      <Table.Td>{inv.date}</Table.Td>
                      <Table.Td ta="right">{fmt(inv.total)}</Table.Td>
                      <Table.Td ta="right">{fmt(inv.paid)}</Table.Td>
                      <Table.Td ta="right" fw={600} c={inv.balance > 0 ? 'orange' : 'green'}>{fmt(inv.balance)}</Table.Td>
                      <Table.Td>
                        <Badge color={inv.status === 'paid' ? 'green' : inv.status === 'sent' ? 'blue' : 'gray'} variant="light" tt="capitalize">
                          {inv.status}
                        </Badge>
                      </Table.Td>
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
