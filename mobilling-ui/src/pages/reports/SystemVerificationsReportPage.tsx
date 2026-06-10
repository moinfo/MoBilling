import { useState, useMemo } from 'react';
import {
  Stack, SimpleGrid, Paper, Text, Table, LoadingOverlay, Group, Box, Badge, ThemeIcon, Progress, Card, Divider,
} from '@mantine/core';
import { useQuery } from '@tanstack/react-query';
import { IconShieldCheck, IconUsers, IconClock, IconAlertTriangle } from '@tabler/icons-react';
import dayjs from 'dayjs';
import { getSystemVerificationsReport } from '../../api/reports';
import ReportHeader from '../../components/Reports/ReportHeader';
import StatCard from '../../components/Reports/StatCard';

const fmtDate = (iso: string) => dayjs(iso).format('DD MMM YYYY');

export default function SystemVerificationsReportPage() {
  const [range, setRange] = useState<[Date | null, Date | null]>([
    dayjs().startOf('month').toDate(),
    dayjs().endOf('month').toDate(),
  ]);

  const params = {
    start_date: range[0] ? dayjs(range[0]).format('YYYY-MM-DD') : dayjs().startOf('month').format('YYYY-MM-DD'),
    end_date: range[1] ? dayjs(range[1]).format('YYYY-MM-DD') : dayjs().endOf('month').format('YYYY-MM-DD'),
  };

  const { data, isLoading } = useQuery({
    queryKey: ['report-system-verifications', params.start_date, params.end_date],
    queryFn: () => getSystemVerificationsReport(params),
  });

  const r = data?.data;

  // Flat export rows
  const exportRows = useMemo(() => {
    if (!r) return [];
    return r.systems.map((s) => ({
      system: s.system_name,
      domain: s.domain_name || '',
      assigned_staff: s.assigned_user?.name || '(unassigned)',
      total_days: s.total_days,
      completed_days: s.completed_days,
      ok_count: s.ok_count,
      issue_count: s.issue_count,
      missed_days: s.missed_days,
      submission_rate_pct: s.submission_rate,
    }));
  }, [r]);

  const totalIssues = r?.systems.reduce((a, s) => a + s.issue_count, 0) ?? 0;
  const totalMissed = r?.systems.reduce((a, s) => a + s.missed_days, 0) ?? 0;
  const totalCompleted = r?.systems.reduce((a, s) => a + s.completed_days, 0) ?? 0;
  const totalPossible = r?.systems.reduce((a, s) => a + s.total_days, 0) ?? 0;
  const overallRate = totalPossible > 0 ? Math.round((totalCompleted / totalPossible) * 1000) / 10 : 0;

  const colorForRate = (rate: number) => rate >= 90 ? 'green' : rate >= 70 ? 'yellow' : 'red';

  return (
    <Stack gap="lg" pos="relative">
      <LoadingOverlay visible={isLoading} />
      <ReportHeader
        title="System Verifications Report"
        dateRange={range}
        onDateChange={setRange}
        exportData={exportRows}
        exportFilename="system-verifications-report"
      />

      {r && (
        <>
          <SimpleGrid cols={{ base: 1, xs: 2, md: 4 }}>
            <StatCard
              label="Overall Submission Rate"
              value={`${overallRate}%`}
              icon={<IconShieldCheck size={24} />}
              color={colorForRate(overallRate)}
              subtitle={`${totalCompleted} / ${totalPossible} possible`}
            />
            <StatCard
              label="Systems Tracked"
              value={r.systems.length}
              icon={<IconUsers size={24} />}
              color="blue"
              subtitle={`${r.by_staff.length} staff assigned`}
            />
            <StatCard
              label="Days Missed"
              value={totalMissed}
              icon={<IconClock size={24} />}
              color="orange"
              subtitle={`across ${r.total_days} day${r.total_days === 1 ? '' : 's'} in range`}
            />
            <StatCard
              label="Issues Reported"
              value={totalIssues}
              icon={<IconAlertTriangle size={24} />}
              color="red"
            />
          </SimpleGrid>

          {/* Per-staff summary */}
          <Card withBorder padding="lg" radius="md">
            <Group justify="space-between" mb="md">
              <Group gap="sm">
                <ThemeIcon size="lg" variant="light" color="blue" radius="md">
                  <IconUsers size={18} />
                </ThemeIcon>
                <Text fw={700}>Per-Staff Completion</Text>
              </Group>
              <Text size="xs" c="dimmed" tt="uppercase" fw={600}>
                {fmtDate(r.period_start)} — {fmtDate(r.period_end)}
              </Text>
            </Group>
            <Divider mb="sm" />

            {r.by_staff.length === 0 ? (
              <Text c="dimmed" size="sm">No staff assigned to any active system in this period.</Text>
            ) : (
              <Stack gap="md">
                {r.by_staff.map((s) => (
                  <Box key={s.staff_name}>
                    <Group justify="space-between" mb={6}>
                      <Group gap="xs">
                        <Text fw={600}>{s.staff_name}</Text>
                        <Text size="xs" c="dimmed">{s.systems_assigned} system{s.systems_assigned === 1 ? '' : 's'}</Text>
                        {s.issue_count > 0 && (
                          <Badge color="red" variant="light" size="sm">{s.issue_count} issue{s.issue_count === 1 ? '' : 's'}</Badge>
                        )}
                      </Group>
                      <Group gap="xs">
                        <Text size="sm" fw={500}>{s.completed_days} / {s.total_days_possible}</Text>
                        <Badge color={colorForRate(s.submission_rate)} variant="light">
                          {s.submission_rate.toFixed(1)}%
                        </Badge>
                      </Group>
                    </Group>
                    <Progress value={s.submission_rate} size="xs" color={colorForRate(s.submission_rate)} radius="xl" />
                    {s.missed_days > 0 && (
                      <Text size="xs" c="orange.7" mt={4}>
                        ⚠ {s.missed_days} day{s.missed_days === 1 ? '' : 's'} missed
                      </Text>
                    )}
                  </Box>
                ))}
              </Stack>
            )}
          </Card>

          {/* Detailed per-system table */}
          <Paper withBorder p="md" radius="md">
            <Text fw={700} mb="md">Per-System Detail</Text>
            <Table striped highlightOnHover>
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>System</Table.Th>
                  <Table.Th>Assigned Staff</Table.Th>
                  <Table.Th style={{ textAlign: 'right' }}>Total Days</Table.Th>
                  <Table.Th style={{ textAlign: 'right' }}>Completed</Table.Th>
                  <Table.Th style={{ textAlign: 'right' }}>OK</Table.Th>
                  <Table.Th style={{ textAlign: 'right' }}>Issues</Table.Th>
                  <Table.Th style={{ textAlign: 'right' }}>Missed</Table.Th>
                  <Table.Th style={{ textAlign: 'right' }}>Rate</Table.Th>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {r.systems.map((s) => (
                  <Table.Tr key={s.system_id}>
                    <Table.Td>
                      <Text fw={500} size="sm">{s.system_name}</Text>
                      {s.domain_name && <Text size="xs" c="dimmed" ff="monospace">{s.domain_name}</Text>}
                    </Table.Td>
                    <Table.Td>
                      {s.assigned_user ? s.assigned_user.name : <Text size="xs" c="dimmed">unassigned</Text>}
                    </Table.Td>
                    <Table.Td style={{ textAlign: 'right' }}>{s.total_days}</Table.Td>
                    <Table.Td style={{ textAlign: 'right' }} fw={600}>{s.completed_days}</Table.Td>
                    <Table.Td style={{ textAlign: 'right' }}>
                      <Text size="sm" c="green.7">{s.ok_count}</Text>
                    </Table.Td>
                    <Table.Td style={{ textAlign: 'right' }}>
                      {s.issue_count > 0 ? (
                        <Text size="sm" c="red.7" fw={600}>{s.issue_count}</Text>
                      ) : <Text size="sm" c="dimmed">0</Text>}
                    </Table.Td>
                    <Table.Td style={{ textAlign: 'right' }}>
                      {s.missed_days > 0 ? (
                        <Text size="sm" c="orange.7" fw={600}>{s.missed_days}</Text>
                      ) : <Text size="sm" c="dimmed">0</Text>}
                    </Table.Td>
                    <Table.Td style={{ textAlign: 'right' }}>
                      <Badge color={colorForRate(s.submission_rate)} variant="light">
                        {s.submission_rate.toFixed(1)}%
                      </Badge>
                    </Table.Td>
                  </Table.Tr>
                ))}
              </Table.Tbody>
            </Table>
          </Paper>
        </>
      )}
    </Stack>
  );
}
