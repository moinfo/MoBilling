import { Stack, SimpleGrid, Paper, Text, Table, Badge, LoadingOverlay } from '@mantine/core';
import { useQuery } from '@tanstack/react-query';
import { PieChart, Pie, Cell, Tooltip, Legend, ResponsiveContainer } from 'recharts';
import { IconShieldCheck, IconAlertTriangle, IconClock, IconPercentage } from '@tabler/icons-react';
import { getStatutoryCompliance } from '../../api/reports';
import ReportHeader from '../../components/Reports/ReportHeader';
import StatCard from '../../components/Reports/StatCard';
import { useState } from 'react';

const fmt = (n: number) => n.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const COLORS = ['#40c057', '#fab005', '#fa5252'];

const statusColor = (s: string) => (s === 'on_track' ? 'green' : s === 'due_soon' ? 'yellow' : 'red');
const statusLabel = (s: string) => (s === 'on_track' ? 'On Track' : s === 'due_soon' ? 'Due Soon' : 'Overdue');

export default function StatutoryComplianceReport() {
  const [range, setRange] = useState<[Date | null, Date | null]>([null, null]);

  const { data, isLoading } = useQuery({
    queryKey: ['report-statutory-compliance'],
    queryFn: getStatutoryCompliance,
  });

  const r = data?.data;

  const pieData = r
    ? [
        { name: 'On Track', value: r.summary.on_track },
        { name: 'Due Soon', value: r.summary.due_soon },
        { name: 'Overdue', value: r.summary.overdue },
      ]
    : [];

  return (
    <Stack gap="lg" pos="relative">
      <LoadingOverlay visible={isLoading} />
      <ReportHeader
        title="Statutory Compliance"
        dateRange={range}
        onDateChange={setRange}
        hideDateFilter
        exportData={r?.obligations as Record<string, unknown>[] | undefined}
        exportFilename="statutory-compliance"
      />

      {r && (
        <>
          <SimpleGrid cols={{ base: 1, xs: 2, md: 4 }}>
            <StatCard label="Compliance Rate" value={`${r.summary.compliance_rate}%`} icon={<IconPercentage size={24} />} color={r.summary.compliance_rate >= 80 ? 'green' : 'red'} />
            <StatCard label="On Track" value={r.summary.on_track} icon={<IconShieldCheck size={24} />} color="green" />
            <StatCard label="Due Soon" value={r.summary.due_soon} icon={<IconClock size={24} />} color="yellow" />
            <StatCard label="Overdue" value={r.summary.overdue} icon={<IconAlertTriangle size={24} />} color="red" />
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
              <Text fw={600} mb="md">Obligations</Text>
              <Table.ScrollContainer minWidth={400}>
                <Table striped highlightOnHover>
                  <Table.Thead>
                    <Table.Tr>
                      <Table.Th>Name</Table.Th>
                      <Table.Th>Cycle</Table.Th>
                      <Table.Th ta="right">Amount</Table.Th>
                      <Table.Th>Due Date</Table.Th>
                      <Table.Th>Status</Table.Th>
                    </Table.Tr>
                  </Table.Thead>
                  <Table.Tbody>
                    {r.obligations.map((o) => (
                      <Table.Tr key={o.id}>
                        <Table.Td>{o.name}</Table.Td>
                        <Table.Td tt="capitalize">{o.cycle.replace('_', ' ')}</Table.Td>
                        <Table.Td ta="right">{fmt(o.amount)}</Table.Td>
                        <Table.Td>{o.next_due_date}</Table.Td>
                        <Table.Td>
                          <Badge color={statusColor(o.status)} variant="light">{statusLabel(o.status)}</Badge>
                        </Table.Td>
                      </Table.Tr>
                    ))}
                  </Table.Tbody>
                </Table>
              </Table.ScrollContainer>
            </Paper>
          </SimpleGrid>

          <Paper withBorder p="md">
            <Text fw={600} mb="md">Payment History Summary</Text>
            <Table.ScrollContainer minWidth={500}>
              <Table striped highlightOnHover>
                <Table.Thead>
                  <Table.Tr>
                    <Table.Th>Obligation</Table.Th>
                    <Table.Th>Category</Table.Th>
                    <Table.Th ta="right">Paid On Time</Table.Th>
                    <Table.Th ta="right">Paid Late</Table.Th>
                    <Table.Th ta="right">Unpaid</Table.Th>
                  </Table.Tr>
                </Table.Thead>
                <Table.Tbody>
                  {r.obligations.map((o) => (
                    <Table.Tr key={o.id}>
                      <Table.Td>{o.name}</Table.Td>
                      <Table.Td>{o.category}</Table.Td>
                      <Table.Td ta="right" c="green">{o.paid_on_time}</Table.Td>
                      <Table.Td ta="right" c="orange">{o.paid_late}</Table.Td>
                      <Table.Td ta="right" c="red">{o.unpaid}</Table.Td>
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
