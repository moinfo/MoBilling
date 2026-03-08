import { useState } from 'react';
import { Stack, SimpleGrid, Paper, Text, Table, Badge, LoadingOverlay, Rating } from '@mantine/core';
import { useQuery } from '@tanstack/react-query';
import {
  Bar, XAxis, YAxis, CartesianGrid, Tooltip, Legend,
  ResponsiveContainer, Line, ComposedChart,
} from 'recharts';
import { IconHeartHandshake, IconStar, IconMoodHappy, IconAlertTriangle, IconMapPin } from '@tabler/icons-react';
import dayjs from 'dayjs';
import { getSatisfactionReport } from '../../api/reports';
import ReportHeader from '../../components/Reports/ReportHeader';
import StatCard from '../../components/Reports/StatCard';

const outcomeColors: Record<string, string> = {
  satisfied: 'green',
  needs_improvement: 'orange',
  complaint: 'red',
  suggestion: 'blue',
  no_answer: 'gray',
  unreachable: 'dark',
};

const outcomeLabels: Record<string, string> = {
  satisfied: 'Satisfied',
  needs_improvement: 'Needs Improvement',
  complaint: 'Complaint',
  suggestion: 'Suggestion',
  no_answer: 'No Answer',
  unreachable: 'Unreachable',
};

const statusColors: Record<string, string> = {
  scheduled: 'blue',
  completed: 'green',
  missed: 'red',
  cancelled: 'gray',
};

export default function SatisfactionReportPage() {
  const [range, setRange] = useState<[Date | null, Date | null]>([
    dayjs().subtract(3, 'month').startOf('month').toDate(),
    dayjs().endOf('month').toDate(),
  ]);

  const params = {
    start_date: range[0] ? dayjs(range[0]).format('YYYY-MM-DD') : dayjs().startOf('month').format('YYYY-MM-DD'),
    end_date: range[1] ? dayjs(range[1]).format('YYYY-MM-DD') : dayjs().endOf('month').format('YYYY-MM-DD'),
  };

  const { data, isLoading } = useQuery({
    queryKey: ['report-satisfaction', params.start_date, params.end_date],
    queryFn: () => getSatisfactionReport(params),
  });

  const r = data?.data;

  return (
    <Stack gap="lg" pos="relative">
      <LoadingOverlay visible={isLoading} />
      <ReportHeader
        title="Satisfaction Report"
        dateRange={range}
        onDateChange={setRange}
        exportData={r?.calls as unknown as Record<string, unknown>[] | undefined}
        exportFilename="satisfaction-report"
      />

      {r && (
        <>
          <SimpleGrid cols={{ base: 1, xs: 2, md: 5 }}>
            <StatCard
              label="Total Calls"
              value={`${r.stats.total_completed}/${r.stats.total_scheduled}`}
              icon={<IconHeartHandshake size={24} />}
              color="blue"
              subtitle={`${r.stats.completion_rate}% completed`}
            />
            <StatCard
              label="Avg Rating"
              value={r.stats.avg_rating ? `${r.stats.avg_rating}/5` : '—'}
              icon={<IconStar size={24} />}
              color="yellow"
            />
            <StatCard
              label="Satisfaction Rate"
              value={`${r.stats.satisfaction_rate}%`}
              icon={<IconMoodHappy size={24} />}
              color={r.stats.satisfaction_rate >= 70 ? 'green' : 'orange'}
            />
            <StatCard
              label="Complaint Rate"
              value={`${r.stats.complaint_rate}%`}
              icon={<IconAlertTriangle size={24} />}
              color={r.stats.complaint_rate <= 10 ? 'green' : 'red'}
            />
            <StatCard
              label="Visit Appointments"
              value={String(r.stats.appointments_total || 0)}
              icon={<IconMapPin size={24} />}
              color="orange"
              subtitle={r.stats.appointments_pending ? `${r.stats.appointments_pending} pending` : undefined}
            />
          </SimpleGrid>

          {/* Monthly Trend Chart — Dual Y-axis: calls + avg rating */}
          {r.monthly.length > 0 && (
            <Paper withBorder p="md" radius="md">
              <Text fw={600} mb="md">Monthly Trend</Text>
              <ResponsiveContainer width="100%" height={300}>
                <ComposedChart data={r.monthly}>
                  <CartesianGrid strokeDasharray="3 3" />
                  <XAxis dataKey="month" tick={{ fontSize: 12 }} />
                  <YAxis yAxisId="left" tick={{ fontSize: 12 }} label={{ value: 'Calls', angle: -90, position: 'insideLeft' }} />
                  <YAxis yAxisId="right" orientation="right" domain={[0, 5]} tick={{ fontSize: 12 }} label={{ value: 'Rating', angle: 90, position: 'insideRight' }} />
                  <Tooltip />
                  <Legend />
                  <Bar yAxisId="left" dataKey="calls_made" name="Completed" fill="#228be6" radius={[4, 4, 0, 0]} />
                  <Bar yAxisId="left" dataKey="total_scheduled" name="Scheduled" fill="#dee2e6" radius={[4, 4, 0, 0]} />
                  <Line yAxisId="right" type="monotone" dataKey="avg_rating" name="Avg Rating" stroke="#fab005" strokeWidth={2} dot={{ r: 4 }} />
                </ComposedChart>
              </ResponsiveContainer>
            </Paper>
          )}

          {/* Outcome Distribution */}
          {r.by_outcome.length > 0 && (
            <Paper withBorder p="md" radius="md">
              <Text fw={600} mb="md">Outcome Distribution</Text>
              <Table striped highlightOnHover>
                <Table.Thead>
                  <Table.Tr>
                    <Table.Th>Outcome</Table.Th>
                    <Table.Th>Count</Table.Th>
                    <Table.Th>Avg Rating</Table.Th>
                    <Table.Th>% of Total</Table.Th>
                  </Table.Tr>
                </Table.Thead>
                <Table.Tbody>
                  {r.by_outcome.map((o) => (
                    <Table.Tr key={o.outcome}>
                      <Table.Td>
                        <Badge color={outcomeColors[o.outcome] || 'gray'} variant="light" size="sm">
                          {outcomeLabels[o.outcome] || o.outcome}
                        </Badge>
                      </Table.Td>
                      <Table.Td fw={600}>{o.count}</Table.Td>
                      <Table.Td>
                        {o.avg_rating ? <Rating value={o.avg_rating} readOnly size="xs" fractions={2} /> : '—'}
                      </Table.Td>
                      <Table.Td>
                        {r.stats.total_completed > 0
                          ? `${Math.round((o.count / r.stats.total_completed) * 100)}%`
                          : '—'}
                      </Table.Td>
                    </Table.Tr>
                  ))}
                </Table.Tbody>
              </Table>
            </Paper>
          )}

          {/* Detail Table */}
          <Paper withBorder p="md" radius="md">
            <Text fw={600} mb="md">Call Details</Text>
            {r.calls.length === 0 ? (
              <Text c="dimmed" size="sm">No satisfaction calls in this period.</Text>
            ) : (
              <Table.ScrollContainer minWidth={800}>
                <Table striped highlightOnHover>
                  <Table.Thead>
                    <Table.Tr>
                      <Table.Th>Date</Table.Th>
                      <Table.Th>Client</Table.Th>
                      <Table.Th>Assigned To</Table.Th>
                      <Table.Th>Outcome</Table.Th>
                      <Table.Th>Rating</Table.Th>
                      <Table.Th>Feedback</Table.Th>
                      <Table.Th>Appointment</Table.Th>
                      <Table.Th>Status</Table.Th>
                    </Table.Tr>
                  </Table.Thead>
                  <Table.Tbody>
                    {r.calls.map((c) => (
                      <Table.Tr key={c.id}>
                        <Table.Td>{new Date(c.scheduled_date).toLocaleDateString()}</Table.Td>
                        <Table.Td fw={500}>{c.client_name || '—'}</Table.Td>
                        <Table.Td>{c.assigned_to || '—'}</Table.Td>
                        <Table.Td>
                          {c.outcome ? (
                            <Badge color={outcomeColors[c.outcome] || 'gray'} size="sm" variant="light">
                              {outcomeLabels[c.outcome] || c.outcome}
                            </Badge>
                          ) : '—'}
                        </Table.Td>
                        <Table.Td>
                          {c.rating ? <Rating value={c.rating} readOnly size="xs" /> : '—'}
                        </Table.Td>
                        <Table.Td>
                          <Text size="xs" truncate maw={200}>{c.feedback || '—'}</Text>
                        </Table.Td>
                        <Table.Td>
                          {c.appointment_requested ? (
                            <Badge size="sm" variant="light" color={
                              c.appointment_status === 'completed' ? 'green'
                              : c.appointment_status === 'cancelled' ? 'gray'
                              : 'orange'
                            } leftSection={<IconMapPin size={10} />}>
                              {c.appointment_date ? new Date(c.appointment_date).toLocaleDateString() : 'TBD'}
                            </Badge>
                          ) : (
                            <Text size="xs" c="dimmed">—</Text>
                          )}
                        </Table.Td>
                        <Table.Td>
                          <Badge color={statusColors[c.status] || 'gray'} size="sm">{c.status}</Badge>
                        </Table.Td>
                      </Table.Tr>
                    ))}
                  </Table.Tbody>
                </Table>
              </Table.ScrollContainer>
            )}
          </Paper>
        </>
      )}
    </Stack>
  );
}
