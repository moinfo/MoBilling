import { useState } from 'react';
import { Stack, SimpleGrid, Paper, Text, Table, LoadingOverlay } from '@mantine/core';
import { useQuery } from '@tanstack/react-query';
import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer } from 'recharts';
import { IconWallet, IconCategory, IconChartBar, IconReceipt2 } from '@tabler/icons-react';
import dayjs from 'dayjs';
import { getExpenseReport } from '../../api/reports';
import ReportHeader from '../../components/Reports/ReportHeader';
import StatCard from '../../components/Reports/StatCard';

const fmt = (n: number) => n.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 });

export default function ExpenseReportPage() {
  const [range, setRange] = useState<[Date | null, Date | null]>([
    dayjs().startOf('year').toDate(),
    dayjs().endOf('month').toDate(),
  ]);

  const params = {
    start_date: range[0] ? dayjs(range[0]).format('YYYY-MM-DD') : dayjs().startOf('year').format('YYYY-MM-DD'),
    end_date: range[1] ? dayjs(range[1]).format('YYYY-MM-DD') : dayjs().endOf('month').format('YYYY-MM-DD'),
  };

  const { data, isLoading } = useQuery({
    queryKey: ['report-expenses', params.start_date, params.end_date],
    queryFn: () => getExpenseReport(params),
  });

  const r = data?.data;
  const topCategory = r?.by_category?.length ? r.by_category.reduce((a, b) => (a.total > b.total ? a : b)) : null;

  return (
    <Stack gap="lg" pos="relative">
      <LoadingOverlay visible={isLoading} />
      <ReportHeader
        title="Expense Report"
        dateRange={range}
        onDateChange={setRange}
        exportData={r?.expenses as unknown as Record<string, unknown>[] | undefined}
        exportFilename="expense-report"
      />

      {r && (
        <>
          <SimpleGrid cols={{ base: 1, xs: 2, md: 4 }}>
            <StatCard label="Total Expenses" value={fmt(r.total_expenses)} icon={<IconWallet size={24} />} color="red" />
            <StatCard label="Categories" value={r.by_category.length} icon={<IconCategory size={24} />} color="blue" />
            <StatCard label="Top Category" value={topCategory?.category || 'N/A'} icon={<IconChartBar size={24} />} color="violet" subtitle={topCategory ? fmt(topCategory.total) : undefined} />
            <StatCard label="Monthly Avg" value={fmt(r.monthly_trend.length > 0 ? r.total_expenses / r.monthly_trend.length : 0)} icon={<IconReceipt2 size={24} />} color="orange" />
          </SimpleGrid>

          <Paper withBorder p="md">
            <Text fw={600} mb="md">Monthly Expense Trend</Text>
            <ResponsiveContainer width="100%" height={300}>
              <BarChart data={r.monthly_trend}>
                <CartesianGrid strokeDasharray="3 3" />
                <XAxis dataKey="month" />
                <YAxis />
                <Tooltip formatter={(v) => fmt(Number(v))} />
                <Bar dataKey="total" fill="#fa5252" name="Expenses" radius={[4, 4, 0, 0]} />
              </BarChart>
            </ResponsiveContainer>
          </Paper>

          <Paper withBorder p="md">
            <Text fw={600} mb="md">By Category</Text>
            <Table.ScrollContainer minWidth={500}>
              <Table striped highlightOnHover>
                <Table.Thead>
                  <Table.Tr>
                    <Table.Th>Category</Table.Th>
                    <Table.Th>Sub-Category</Table.Th>
                    <Table.Th ta="right">Count</Table.Th>
                    <Table.Th ta="right">Amount</Table.Th>
                  </Table.Tr>
                </Table.Thead>
                <Table.Tbody>
                  {r.by_category.map((cat) =>
                    cat.sub_categories.map((sub, si) => (
                      <Table.Tr key={`${cat.category}-${si}`}>
                        {si === 0 ? (
                          <Table.Td rowSpan={cat.sub_categories.length} fw={600}>{cat.category}</Table.Td>
                        ) : null}
                        <Table.Td>{sub.name}</Table.Td>
                        <Table.Td ta="right">{sub.count}</Table.Td>
                        <Table.Td ta="right">{fmt(sub.total)}</Table.Td>
                      </Table.Tr>
                    ))
                  )}
                </Table.Tbody>
                <Table.Tfoot>
                  <Table.Tr fw={700}>
                    <Table.Td colSpan={3}>Total</Table.Td>
                    <Table.Td ta="right">{fmt(r.total_expenses)}</Table.Td>
                  </Table.Tr>
                </Table.Tfoot>
              </Table>
            </Table.ScrollContainer>
          </Paper>

          <Paper withBorder p="md">
            <Text fw={600} mb="md">Expense Details</Text>
            <Table.ScrollContainer minWidth={700}>
              <Table striped highlightOnHover>
                <Table.Thead>
                  <Table.Tr>
                    <Table.Th>Date</Table.Th>
                    <Table.Th>Description</Table.Th>
                    <Table.Th>Category</Table.Th>
                    <Table.Th>Sub-Category</Table.Th>
                    <Table.Th ta="right">Amount</Table.Th>
                    <Table.Th>Method</Table.Th>
                    <Table.Th>Reference</Table.Th>
                  </Table.Tr>
                </Table.Thead>
                <Table.Tbody>
                  {r.expenses.map((e) => (
                    <Table.Tr key={e.id}>
                      <Table.Td>{e.expense_date}</Table.Td>
                      <Table.Td>{e.description || '-'}</Table.Td>
                      <Table.Td>{e.category || '-'}</Table.Td>
                      <Table.Td>{e.sub_category || '-'}</Table.Td>
                      <Table.Td ta="right" fw={600}>{fmt(e.amount)}</Table.Td>
                      <Table.Td tt="capitalize">{e.payment_method || '-'}</Table.Td>
                      <Table.Td>{e.reference || '-'}</Table.Td>
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
