import { Stack, SimpleGrid, Paper, Text, Table, Badge, LoadingOverlay } from '@mantine/core';
import { useQuery } from '@tanstack/react-query';
import { PieChart, Pie, Cell, Tooltip, Legend, ResponsiveContainer } from 'recharts';
import { IconAlertTriangle, IconFileInvoice, IconClock, IconCash } from '@tabler/icons-react';
import { getOutstandingAging, AgingInvoice } from '../../api/reports';
import ReportHeader from '../../components/Reports/ReportHeader';
import StatCard from '../../components/Reports/StatCard';
import { useState } from 'react';

const fmt = (n: number) => n.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 });

const BAND_LABELS: Record<string, string> = {
  current: 'Current (Not Due)',
  '1_30': '1–30 Days',
  '31_60': '31–60 Days',
  '61_90': '61–90 Days',
  '90_plus': '90+ Days',
};
const COLORS = ['#40c057', '#228be6', '#fab005', '#fd7e14', '#fa5252'];

export default function OutstandingAging() {
  const [range, setRange] = useState<[Date | null, Date | null]>([null, null]);

  const { data, isLoading } = useQuery({
    queryKey: ['report-aging'],
    queryFn: getOutstandingAging,
  });

  const r = data?.data;

  const pieData = r
    ? Object.entries(r.band_totals).map(([key, value]) => ({
        name: BAND_LABELS[key],
        value: value,
      }))
    : [];

  const allInvoices: AgingInvoice[] = r
    ? Object.values(r.bands).flat()
    : [];

  return (
    <Stack gap="lg" pos="relative">
      <LoadingOverlay visible={isLoading} />
      <ReportHeader
        title="Outstanding & Aging"
        dateRange={range}
        onDateChange={setRange}
        hideDateFilter
        exportData={allInvoices as unknown as Record<string, unknown>[]}
        exportFilename="outstanding-aging"
      />

      {r && (
        <>
          <SimpleGrid cols={{ base: 1, xs: 2, md: 4 }}>
            <StatCard label="Total Outstanding" value={fmt(r.total_outstanding)} icon={<IconAlertTriangle size={24} />} color="red" />
            <StatCard label="Total Invoices" value={r.total_invoices} icon={<IconFileInvoice size={24} />} color="blue" />
            <StatCard label="Overdue (90+)" value={fmt(r.band_totals['90_plus'] || 0)} icon={<IconClock size={24} />} color="orange" />
            <StatCard label="Current" value={fmt(r.band_totals['current'] || 0)} icon={<IconCash size={24} />} color="green" />
          </SimpleGrid>

          <SimpleGrid cols={{ base: 1, md: 2 }}>
            <Paper withBorder p="md">
              <Text fw={600} mb="md">Aging Distribution</Text>
              <ResponsiveContainer width="100%" height={300}>
                <PieChart>
                  <Pie data={pieData} cx="50%" cy="50%" outerRadius={100} dataKey="value" label={({ name, value }) => `${name}: ${fmt(value)}`}>
                    {pieData.map((_, i) => (
                      <Cell key={i} fill={COLORS[i % COLORS.length]} />
                    ))}
                  </Pie>
                  <Tooltip formatter={(v) => fmt(Number(v))} />
                  <Legend />
                </PieChart>
              </ResponsiveContainer>
            </Paper>

            <Paper withBorder p="md">
              <Text fw={600} mb="md">Band Totals</Text>
              <Table striped highlightOnHover>
                <Table.Thead>
                  <Table.Tr>
                    <Table.Th>Band</Table.Th>
                    <Table.Th ta="right">Amount</Table.Th>
                    <Table.Th ta="right">Invoices</Table.Th>
                  </Table.Tr>
                </Table.Thead>
                <Table.Tbody>
                  {Object.entries(BAND_LABELS).map(([key, label]) => (
                    <Table.Tr key={key}>
                      <Table.Td>{label}</Table.Td>
                      <Table.Td ta="right">{fmt(r.band_totals[key] || 0)}</Table.Td>
                      <Table.Td ta="right">{r.bands[key]?.length || 0}</Table.Td>
                    </Table.Tr>
                  ))}
                </Table.Tbody>
              </Table>
            </Paper>
          </SimpleGrid>

          <Paper withBorder p="md">
            <Text fw={600} mb="md">Overdue Invoices</Text>
            <Table.ScrollContainer minWidth={700}>
              <Table striped highlightOnHover>
                <Table.Thead>
                  <Table.Tr>
                    <Table.Th>Invoice #</Table.Th>
                    <Table.Th>Client</Table.Th>
                    <Table.Th ta="right">Total</Table.Th>
                    <Table.Th ta="right">Paid</Table.Th>
                    <Table.Th ta="right">Balance</Table.Th>
                    <Table.Th>Due Date</Table.Th>
                    <Table.Th>Age</Table.Th>
                  </Table.Tr>
                </Table.Thead>
                <Table.Tbody>
                  {allInvoices
                    .filter((inv) => inv.days_overdue > 0)
                    .sort((a, b) => b.days_overdue - a.days_overdue)
                    .map((inv) => (
                      <Table.Tr key={inv.id}>
                        <Table.Td>{inv.document_number}</Table.Td>
                        <Table.Td>{inv.client_name}</Table.Td>
                        <Table.Td ta="right">{fmt(inv.total)}</Table.Td>
                        <Table.Td ta="right">{fmt(inv.paid)}</Table.Td>
                        <Table.Td ta="right" fw={600} c="red">{fmt(inv.balance)}</Table.Td>
                        <Table.Td>{inv.due_date}</Table.Td>
                        <Table.Td>
                          <Badge color={inv.days_overdue > 90 ? 'red' : inv.days_overdue > 60 ? 'orange' : 'yellow'} variant="light">
                            {inv.days_overdue}d
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
