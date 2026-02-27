import { useState } from 'react';
import { Stack, SimpleGrid, Paper, Text, Table, LoadingOverlay } from '@mantine/core';
import { useQuery } from '@tanstack/react-query';
import {
  BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, Legend,
  PieChart, Pie, Cell,
} from 'recharts';
import { IconCash, IconReceipt, IconChartBar, IconCreditCard } from '@tabler/icons-react';
import dayjs from 'dayjs';
import { getPaymentCollection } from '../../api/reports';
import ReportHeader from '../../components/Reports/ReportHeader';
import StatCard from '../../components/Reports/StatCard';

const fmt = (n: number) => n.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const COLORS = ['#228be6', '#40c057', '#fab005', '#7950f2', '#fd7e14', '#fa5252'];

export default function PaymentCollectionReport() {
  const [range, setRange] = useState<[Date | null, Date | null]>([
    dayjs().startOf('month').toDate(),
    dayjs().endOf('month').toDate(),
  ]);

  const params = {
    start_date: range[0] ? dayjs(range[0]).format('YYYY-MM-DD') : dayjs().startOf('month').format('YYYY-MM-DD'),
    end_date: range[1] ? dayjs(range[1]).format('YYYY-MM-DD') : dayjs().endOf('month').format('YYYY-MM-DD'),
  };

  const { data, isLoading } = useQuery({
    queryKey: ['report-payment-collection', params.start_date, params.end_date],
    queryFn: () => getPaymentCollection(params),
  });

  const r = data?.data;
  const topMethod = r?.by_method?.length ? r.by_method.reduce((a, b) => (a.total > b.total ? a : b)) : null;

  return (
    <Stack gap="lg" pos="relative">
      <LoadingOverlay visible={isLoading} />
      <ReportHeader
        title="Payment Collection"
        dateRange={range}
        onDateChange={setRange}
        exportData={r?.payments as unknown as Record<string, unknown>[] | undefined}
        exportFilename="payment-collection"
      />

      {r && (
        <>
          <SimpleGrid cols={{ base: 1, xs: 2, md: 4 }}>
            <StatCard label="Total Collected" value={fmt(r.total_collected)} icon={<IconCash size={24} />} color="green" />
            <StatCard label="Transactions" value={r.total_transactions} icon={<IconReceipt size={24} />} color="blue" />
            <StatCard label="Payment Methods" value={r.by_method.length} icon={<IconCreditCard size={24} />} color="violet" />
            <StatCard label="Top Method" value={topMethod?.method || 'N/A'} icon={<IconChartBar size={24} />} color="cyan" subtitle={topMethod ? fmt(topMethod.total) : undefined} />
          </SimpleGrid>

          <SimpleGrid cols={{ base: 1, md: 2 }}>
            <Paper withBorder p="md">
              <Text fw={600} mb="md">By Payment Method</Text>
              <ResponsiveContainer width="100%" height={300}>
                <PieChart>
                  <Pie data={r.by_method} dataKey="total" nameKey="method" cx="50%" cy="50%" outerRadius={100} label={({ name, value }) => `${name}: ${fmt(Number(value))}`}>
                    {r.by_method.map((_, i) => (
                      <Cell key={i} fill={COLORS[i % COLORS.length]} />
                    ))}
                  </Pie>
                  <Tooltip formatter={(v) => fmt(Number(v))} />
                  <Legend />
                </PieChart>
              </ResponsiveContainer>
            </Paper>

            <Paper withBorder p="md">
              <Text fw={600} mb="md">Daily Collection Trend</Text>
              <ResponsiveContainer width="100%" height={300}>
                <BarChart data={r.daily_trend}>
                  <CartesianGrid strokeDasharray="3 3" />
                  <XAxis dataKey="day" tickFormatter={(d) => dayjs(d).format('D MMM')} />
                  <YAxis />
                  <Tooltip formatter={(v) => fmt(Number(v))} labelFormatter={(d) => dayjs(d).format('D MMM YYYY')} />
                  <Bar dataKey="total" fill="#40c057" name="Collected" radius={[4, 4, 0, 0]} />
                </BarChart>
              </ResponsiveContainer>
            </Paper>
          </SimpleGrid>

          <Paper withBorder p="md">
            <Text fw={600} mb="md">Payment Details</Text>
            <Table.ScrollContainer minWidth={700}>
              <Table striped highlightOnHover>
                <Table.Thead>
                  <Table.Tr>
                    <Table.Th>Date</Table.Th>
                    <Table.Th>Client</Table.Th>
                    <Table.Th>Invoice #</Table.Th>
                    <Table.Th ta="right">Amount</Table.Th>
                    <Table.Th>Method</Table.Th>
                    <Table.Th>Reference</Table.Th>
                  </Table.Tr>
                </Table.Thead>
                <Table.Tbody>
                  {r.payments.map((p) => (
                    <Table.Tr key={p.id}>
                      <Table.Td>{p.payment_date}</Table.Td>
                      <Table.Td>{p.client_name || '-'}</Table.Td>
                      <Table.Td>{p.document_number || '-'}</Table.Td>
                      <Table.Td ta="right" fw={600}>{fmt(p.amount)}</Table.Td>
                      <Table.Td tt="capitalize">{p.payment_method || '-'}</Table.Td>
                      <Table.Td>{p.reference || '-'}</Table.Td>
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
