import { useState } from 'react';
import { Stack, SimpleGrid, Paper, Text, Table, Badge, LoadingOverlay } from '@mantine/core';
import { useQuery } from '@tanstack/react-query';
import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer } from 'recharts';
import { IconMail, IconCheck, IconX, IconPercentage } from '@tabler/icons-react';
import dayjs from 'dayjs';
import { getCommunicationLog } from '../../api/reports';
import ReportHeader from '../../components/Reports/ReportHeader';
import StatCard from '../../components/Reports/StatCard';

export default function CommunicationLogReport() {
  const [range, setRange] = useState<[Date | null, Date | null]>([
    dayjs().startOf('month').toDate(),
    dayjs().endOf('month').toDate(),
  ]);

  const params = {
    start_date: range[0] ? dayjs(range[0]).format('YYYY-MM-DD') : dayjs().startOf('month').format('YYYY-MM-DD'),
    end_date: range[1] ? dayjs(range[1]).format('YYYY-MM-DD') : dayjs().endOf('month').format('YYYY-MM-DD'),
  };

  const { data, isLoading } = useQuery({
    queryKey: ['report-communication-log', params.start_date, params.end_date],
    queryFn: () => getCommunicationLog(params),
  });

  const r = data?.data;

  return (
    <Stack gap="lg" pos="relative">
      <LoadingOverlay visible={isLoading} />
      <ReportHeader
        title="Communication Log"
        dateRange={range}
        onDateChange={setRange}
        exportData={r?.messages as unknown as Record<string, unknown>[] | undefined}
        exportFilename="communication-log"
      />

      {r && (
        <>
          <SimpleGrid cols={{ base: 1, xs: 2, md: 4 }}>
            <StatCard label="Total Messages" value={r.total} icon={<IconMail size={24} />} color="blue" />
            <StatCard label="Delivered" value={r.total_sent} icon={<IconCheck size={24} />} color="green" />
            <StatCard label="Failed" value={r.total_failed} icon={<IconX size={24} />} color="red" />
            <StatCard label="Delivery Rate" value={`${r.overall_delivery_rate}%`} icon={<IconPercentage size={24} />} color={r.overall_delivery_rate >= 90 ? 'teal' : 'orange'} />
          </SimpleGrid>

          <Paper withBorder p="md">
            <Text fw={600} mb="md">Daily Volume</Text>
            <ResponsiveContainer width="100%" height={300}>
              <BarChart data={r.daily_volume}>
                <CartesianGrid strokeDasharray="3 3" />
                <XAxis dataKey="day" tickFormatter={(d) => dayjs(d).format('D MMM')} />
                <YAxis />
                <Tooltip labelFormatter={(d) => dayjs(d).format('D MMM YYYY')} />
                <Legend />
                <Bar dataKey="sent" fill="#40c057" name="Sent" stackId="a" />
                <Bar dataKey="failed" fill="#fa5252" name="Failed" stackId="a" />
              </BarChart>
            </ResponsiveContainer>
          </Paper>

          <SimpleGrid cols={{ base: 1, md: 2 }}>
            <Paper withBorder p="md">
              <Text fw={600} mb="md">By Channel</Text>
              <Table striped highlightOnHover>
                <Table.Thead>
                  <Table.Tr>
                    <Table.Th>Channel</Table.Th>
                    <Table.Th ta="right">Total</Table.Th>
                    <Table.Th ta="right">Sent</Table.Th>
                    <Table.Th ta="right">Failed</Table.Th>
                    <Table.Th ta="right">Rate</Table.Th>
                  </Table.Tr>
                </Table.Thead>
                <Table.Tbody>
                  {r.by_channel.map((ch) => (
                    <Table.Tr key={ch.channel}>
                      <Table.Td tt="capitalize">{ch.channel}</Table.Td>
                      <Table.Td ta="right">{ch.total}</Table.Td>
                      <Table.Td ta="right" c="green">{ch.sent}</Table.Td>
                      <Table.Td ta="right" c="red">{ch.failed}</Table.Td>
                      <Table.Td ta="right">{ch.delivery_rate}%</Table.Td>
                    </Table.Tr>
                  ))}
                </Table.Tbody>
              </Table>
            </Paper>

            <Paper withBorder p="md">
              <Text fw={600} mb="md">By Type</Text>
              <Table striped highlightOnHover>
                <Table.Thead>
                  <Table.Tr>
                    <Table.Th>Type</Table.Th>
                    <Table.Th ta="right">Total</Table.Th>
                    <Table.Th ta="right">Sent</Table.Th>
                    <Table.Th ta="right">Failed</Table.Th>
                  </Table.Tr>
                </Table.Thead>
                <Table.Tbody>
                  {r.by_type.map((t) => (
                    <Table.Tr key={t.type}>
                      <Table.Td tt="capitalize">{t.type.replace('_', ' ')}</Table.Td>
                      <Table.Td ta="right">{t.total}</Table.Td>
                      <Table.Td ta="right" c="green">{t.sent}</Table.Td>
                      <Table.Td ta="right" c="red">{t.failed}</Table.Td>
                    </Table.Tr>
                  ))}
                </Table.Tbody>
              </Table>
            </Paper>
          </SimpleGrid>

          <Paper withBorder p="md">
            <Text fw={600} mb="md">Message Details</Text>
            <Table.ScrollContainer minWidth={800}>
              <Table striped highlightOnHover>
                <Table.Thead>
                  <Table.Tr>
                    <Table.Th>Date</Table.Th>
                    <Table.Th>Channel</Table.Th>
                    <Table.Th>Type</Table.Th>
                    <Table.Th>Recipient</Table.Th>
                    <Table.Th>Client</Table.Th>
                    <Table.Th>Subject</Table.Th>
                    <Table.Th>Status</Table.Th>
                    <Table.Th>Error</Table.Th>
                  </Table.Tr>
                </Table.Thead>
                <Table.Tbody>
                  {r.messages.map((m) => (
                    <Table.Tr key={m.id}>
                      <Table.Td>{m.created_at}</Table.Td>
                      <Table.Td tt="capitalize">{m.channel}</Table.Td>
                      <Table.Td tt="capitalize">{m.type?.replace('_', ' ')}</Table.Td>
                      <Table.Td>{m.recipient}</Table.Td>
                      <Table.Td>{m.client_name || '-'}</Table.Td>
                      <Table.Td maw={200} style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{m.subject || '-'}</Table.Td>
                      <Table.Td>
                        <Badge color={m.status === 'sent' ? 'green' : 'red'} variant="light" tt="capitalize">
                          {m.status}
                        </Badge>
                      </Table.Td>
                      <Table.Td maw={150} style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }} c="red">
                        {m.error || '-'}
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
