import { useState } from 'react';
import { Stack, SimpleGrid, Paper, Text, Table, Badge, LoadingOverlay } from '@mantine/core';
import { useQuery } from '@tanstack/react-query';
import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer, ReferenceLine } from 'recharts';
import { IconCash, IconReceipt, IconTrendingUp, IconPercentage } from '@tabler/icons-react';
import dayjs from 'dayjs';
import { getProfitLoss } from '../../api/reports';
import ReportHeader from '../../components/Reports/ReportHeader';
import StatCard from '../../components/Reports/StatCard';

const fmt = (n: number) => n.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 });

export default function ProfitLossReport() {
  const [range, setRange] = useState<[Date | null, Date | null]>([
    dayjs().startOf('year').toDate(),
    dayjs().endOf('month').toDate(),
  ]);

  const params = {
    start_date: range[0] ? dayjs(range[0]).format('YYYY-MM-DD') : dayjs().startOf('year').format('YYYY-MM-DD'),
    end_date: range[1] ? dayjs(range[1]).format('YYYY-MM-DD') : dayjs().endOf('month').format('YYYY-MM-DD'),
  };

  const { data, isLoading } = useQuery({
    queryKey: ['report-profit-loss', params.start_date, params.end_date],
    queryFn: () => getProfitLoss(params),
  });

  const r = data?.data;

  return (
    <Stack gap="lg" pos="relative">
      <LoadingOverlay visible={isLoading} />
      <ReportHeader
        title="Profit & Loss"
        dateRange={range}
        onDateChange={setRange}
        exportData={r?.entries as unknown as Record<string, unknown>[] | undefined}
        exportFilename="profit-loss"
      />

      {r && (
        <>
          <SimpleGrid cols={{ base: 1, xs: 2, md: 4 }}>
            <StatCard label="Revenue" value={fmt(r.revenue)} icon={<IconCash size={24} />} color="green" />
            <StatCard label="Total Costs" value={fmt(r.total_costs)} icon={<IconReceipt size={24} />} color="red" subtitle={`Bills: ${fmt(r.bill_payments)} + Expenses: ${fmt(r.expenses)}`} />
            <StatCard
              label="Net Profit"
              value={fmt(r.net_profit)}
              icon={<IconTrendingUp size={24} />}
              color={r.net_profit >= 0 ? 'teal' : 'red'}
            />
            <StatCard label="Profit Margin" value={`${r.profit_margin}%`} icon={<IconPercentage size={24} />} color={r.profit_margin >= 0 ? 'cyan' : 'red'} />
          </SimpleGrid>

          <Paper withBorder p="md">
            <Text fw={600} mb="md">Monthly Profit & Loss</Text>
            <ResponsiveContainer width="100%" height={350}>
              <BarChart data={r.months}>
                <CartesianGrid strokeDasharray="3 3" />
                <XAxis dataKey="month" />
                <YAxis />
                <Tooltip formatter={(v) => fmt(Number(v))} />
                <Legend />
                <ReferenceLine y={0} stroke="#000" />
                <Bar dataKey="revenue" fill="#40c057" name="Revenue" radius={[4, 4, 0, 0]} />
                <Bar dataKey="bill_payments" fill="#fd7e14" name="Bills" radius={[4, 4, 0, 0]} />
                <Bar dataKey="expenses" fill="#fa5252" name="Expenses" radius={[4, 4, 0, 0]} />
                <Bar dataKey="net_profit" fill="#228be6" name="Net Profit" radius={[4, 4, 0, 0]} />
              </BarChart>
            </ResponsiveContainer>
          </Paper>

          <Paper withBorder p="md">
            <Text fw={600} mb="md">Monthly Breakdown</Text>
            <Table.ScrollContainer minWidth={600}>
              <Table striped highlightOnHover>
                <Table.Thead>
                  <Table.Tr>
                    <Table.Th>Month</Table.Th>
                    <Table.Th ta="right">Revenue</Table.Th>
                    <Table.Th ta="right">Bills</Table.Th>
                    <Table.Th ta="right">Expenses</Table.Th>
                    <Table.Th ta="right">Net Profit</Table.Th>
                  </Table.Tr>
                </Table.Thead>
                <Table.Tbody>
                  {r.months.map((m) => (
                    <Table.Tr key={m.month}>
                      <Table.Td>{m.month}</Table.Td>
                      <Table.Td ta="right" c="green">{fmt(m.revenue)}</Table.Td>
                      <Table.Td ta="right">{fmt(m.bill_payments)}</Table.Td>
                      <Table.Td ta="right">{fmt(m.expenses)}</Table.Td>
                      <Table.Td ta="right" fw={600} c={m.net_profit >= 0 ? 'teal' : 'red'}>{fmt(m.net_profit)}</Table.Td>
                    </Table.Tr>
                  ))}
                </Table.Tbody>
                <Table.Tfoot>
                  <Table.Tr fw={700}>
                    <Table.Td>Total</Table.Td>
                    <Table.Td ta="right">{fmt(r.revenue)}</Table.Td>
                    <Table.Td ta="right">{fmt(r.bill_payments)}</Table.Td>
                    <Table.Td ta="right">{fmt(r.expenses)}</Table.Td>
                    <Table.Td ta="right" c={r.net_profit >= 0 ? 'teal' : 'red'}>{fmt(r.net_profit)}</Table.Td>
                  </Table.Tr>
                </Table.Tfoot>
              </Table>
            </Table.ScrollContainer>
          </Paper>

          <Paper withBorder p="md">
            <Text fw={600} mb="md">Transaction Details</Text>
            <Table.ScrollContainer minWidth={700}>
              <Table striped highlightOnHover>
                <Table.Thead>
                  <Table.Tr>
                    <Table.Th>Date</Table.Th>
                    <Table.Th>Type</Table.Th>
                    <Table.Th>Description</Table.Th>
                    <Table.Th>Client</Table.Th>
                    <Table.Th ta="right">Amount</Table.Th>
                  </Table.Tr>
                </Table.Thead>
                <Table.Tbody>
                  {r.entries.map((e, i) => (
                    <Table.Tr key={i}>
                      <Table.Td>{e.date}</Table.Td>
                      <Table.Td>
                        <Badge
                          color={e.type === 'revenue' ? 'green' : e.type === 'bill_payment' ? 'orange' : 'red'}
                          variant="light"
                          size="sm"
                        >
                          {e.type === 'revenue' ? 'Revenue' : e.type === 'bill_payment' ? 'Bill' : 'Expense'}
                        </Badge>
                      </Table.Td>
                      <Table.Td>{e.description}</Table.Td>
                      <Table.Td>{e.client || '-'}</Table.Td>
                      <Table.Td ta="right" fw={600} c={e.type === 'revenue' ? 'green' : 'red'}>
                        {e.type === 'revenue' ? '+' : '-'}{fmt(e.amount)}
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
