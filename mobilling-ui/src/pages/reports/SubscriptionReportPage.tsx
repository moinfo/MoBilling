import { Stack, SimpleGrid, Paper, Text, Table, Badge, LoadingOverlay } from '@mantine/core';
import { useQuery } from '@tanstack/react-query';
import { PieChart, Pie, Cell, Tooltip, Legend, ResponsiveContainer } from 'recharts';
import { IconLink, IconCash, IconCalendarRepeat, IconChartPie } from '@tabler/icons-react';
import { getSubscriptionReport } from '../../api/reports';
import ReportHeader from '../../components/Reports/ReportHeader';
import StatCard from '../../components/Reports/StatCard';
import { useState } from 'react';

const fmt = (n: number) => n.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const COLORS = ['#40c057', '#fab005', '#fa5252'];

export default function SubscriptionReportPage() {
  const [range, setRange] = useState<[Date | null, Date | null]>([null, null]);

  const { data, isLoading } = useQuery({
    queryKey: ['report-subscriptions'],
    queryFn: getSubscriptionReport,
  });

  const r = data?.data;

  const pieData = r
    ? [
        { name: 'Active', value: r.by_status.active },
        { name: 'Pending', value: r.by_status.pending },
        { name: 'Cancelled', value: r.by_status.cancelled },
      ]
    : [];

  return (
    <Stack gap="lg" pos="relative">
      <LoadingOverlay visible={isLoading} />
      <ReportHeader
        title="Subscription Report"
        dateRange={range}
        onDateChange={setRange}
        hideDateFilter
        exportData={r?.upcoming_renewals as Record<string, unknown>[] | undefined}
        exportFilename="subscriptions"
      />

      {r && (
        <>
          <SimpleGrid cols={{ base: 1, xs: 2, md: 4 }}>
            <StatCard label="Total Subscriptions" value={r.total_subscriptions} icon={<IconLink size={24} />} color="blue" />
            <StatCard label="Active" value={r.by_status.active} icon={<IconChartPie size={24} />} color="green" />
            <StatCard label="Monthly Revenue" value={fmt(r.active_monthly_revenue)} icon={<IconCash size={24} />} color="teal" />
            <StatCard label="Monthly Forecast" value={fmt(r.monthly_forecast)} icon={<IconCalendarRepeat size={24} />} color="cyan" />
          </SimpleGrid>

          <SimpleGrid cols={{ base: 1, md: 2 }}>
            <Paper withBorder p="md">
              <Text fw={600} mb="md">Status Distribution</Text>
              <ResponsiveContainer width="100%" height={300}>
                <PieChart>
                  <Pie data={pieData} dataKey="value" nameKey="name" cx="50%" cy="50%" outerRadius={100} label>
                    {pieData.map((_, i) => (
                      <Cell key={i} fill={COLORS[i]} />
                    ))}
                  </Pie>
                  <Tooltip />
                  <Legend />
                </PieChart>
              </ResponsiveContainer>
            </Paper>

            <Paper withBorder p="md">
              <Text fw={600} mb="md">Upcoming Renewals</Text>
              <Table.ScrollContainer minWidth={400}>
                <Table striped highlightOnHover>
                  <Table.Thead>
                    <Table.Tr>
                      <Table.Th>Client</Table.Th>
                      <Table.Th>Product</Table.Th>
                      <Table.Th ta="right">Price</Table.Th>
                      <Table.Th>Next Bill</Table.Th>
                      <Table.Th>In</Table.Th>
                    </Table.Tr>
                  </Table.Thead>
                  <Table.Tbody>
                    {r.upcoming_renewals.map((s, i) => (
                      <Table.Tr key={i}>
                        <Table.Td>{s.client_name}</Table.Td>
                        <Table.Td>{s.product_name}{s.label ? ` (${s.label})` : ''}</Table.Td>
                        <Table.Td ta="right">{fmt(s.price)}</Table.Td>
                        <Table.Td>{s.next_bill_date}</Table.Td>
                        <Table.Td>
                          <Badge color={s.days_until <= 7 ? 'orange' : 'blue'} variant="light">
                            {s.days_until}d
                          </Badge>
                        </Table.Td>
                      </Table.Tr>
                    ))}
                  </Table.Tbody>
                </Table>
              </Table.ScrollContainer>
            </Paper>
          </SimpleGrid>
        </>
      )}
    </Stack>
  );
}
