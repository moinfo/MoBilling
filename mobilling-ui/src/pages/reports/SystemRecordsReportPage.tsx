import { useState, useMemo } from 'react';
import { Stack, SimpleGrid, Paper, Text, Table, LoadingOverlay, Group, Box, Badge, ThemeIcon, Card, Divider } from '@mantine/core';
import { useQuery } from '@tanstack/react-query';
import { IconCalendar, IconStack2, IconChartBar, IconDatabase } from '@tabler/icons-react';
import dayjs from 'dayjs';
import { getSystemRecordsReport } from '../../api/reports';
import ReportHeader from '../../components/Reports/ReportHeader';
import StatCard from '../../components/Reports/StatCard';
import { formatCurrency } from '../../utils/formatCurrency';

const fmtDate = (iso: string) => dayjs(iso).format('ddd, DD MMM YYYY');

export default function SystemRecordsReportPage() {
  // Default = current month (matches the user's "current monthly" request)
  const [range, setRange] = useState<[Date | null, Date | null]>([
    dayjs().startOf('month').toDate(),
    dayjs().endOf('month').toDate(),
  ]);

  const params = {
    start_date: range[0] ? dayjs(range[0]).format('YYYY-MM-DD') : dayjs().startOf('month').format('YYYY-MM-DD'),
    end_date: range[1] ? dayjs(range[1]).format('YYYY-MM-DD') : dayjs().endOf('month').format('YYYY-MM-DD'),
  };

  const { data, isLoading } = useQuery({
    queryKey: ['report-system-records', params.start_date, params.end_date],
    queryFn: () => getSystemRecordsReport(params),
  });

  const r = data?.data;

  // Flat export rows (CSV-friendly) — one row per (date, system, property)
  const exportRows = useMemo(() => {
    if (!r) return [];
    const out: Record<string, unknown>[] = [];
    r.days.forEach((d) => {
      d.systems.forEach((s) => {
        s.properties.forEach((p) => {
          out.push({
            date: d.date,
            system: s.name,
            system_property: p.name,
            amount: p.total,
            system_subtotal: s.subtotal,
            day_total: d.day_total,
          });
        });
      });
    });
    return out;
  }, [r]);

  const topSystem = r?.system_totals?.[0];
  const dayCount = r?.days?.length ?? 0;

  return (
    <Stack gap="lg" pos="relative">
      <LoadingOverlay visible={isLoading} />
      <ReportHeader
        title="System Records Report"
        dateRange={range}
        onDateChange={setRange}
        exportData={exportRows}
        exportFilename="system-records-report"
      />

      {r && (
        <>
          {/* Stat cards */}
          <SimpleGrid cols={{ base: 1, xs: 2, md: 4 }}>
            <StatCard
              label="Grand Total"
              value={formatCurrency(r.grand_total)}
              icon={<IconDatabase size={24} />}
              color="blue"
            />
            <StatCard
              label="Days With Records"
              value={dayCount}
              icon={<IconCalendar size={24} />}
              color="teal"
              subtitle={`of ${dayjs(r.period_end).diff(dayjs(r.period_start), 'day') + 1} days in range`}
            />
            <StatCard
              label="Systems"
              value={r.system_totals.length}
              icon={<IconStack2 size={24} />}
              color="violet"
            />
            <StatCard
              label="Top System"
              value={topSystem?.name || '—'}
              icon={<IconChartBar size={24} />}
              color="orange"
              subtitle={topSystem ? formatCurrency(topSystem.total) : undefined}
            />
          </SimpleGrid>

          {/* Per-system totals across the whole period */}
          <Card withBorder padding="lg" radius="md">
            <Group justify="space-between" mb="md">
              <Group gap="sm">
                <ThemeIcon size="lg" variant="light" color="blue" radius="md">
                  <IconStack2 size={18} />
                </ThemeIcon>
                <Text fw={700}>Per-System Totals</Text>
              </Group>
              <Text size="xs" c="dimmed" tt="uppercase" fw={600}>
                {fmtDate(r.period_start)} — {fmtDate(r.period_end)}
              </Text>
            </Group>
            <Divider mb="sm" />
            <Stack gap="xs">
              {r.system_totals.length === 0 ? (
                <Text c="dimmed" size="sm">No records in this period.</Text>
              ) : (
                r.system_totals.map((s) => {
                  const pct = r.grand_total > 0 ? (s.total / r.grand_total) * 100 : 0;
                  return (
                    <Group key={s.name} justify="space-between" wrap="nowrap">
                      <Group gap="xs">
                        <Badge variant="filled" color="blue" radius="sm">{s.name}</Badge>
                        <Text size="xs" c="dimmed">{pct.toFixed(1)}%</Text>
                      </Group>
                      <Text fw={700}>{formatCurrency(s.total)}</Text>
                    </Group>
                  );
                })
              )}
              <Divider my="xs" />
              <Group justify="space-between">
                <Text fw={700} tt="uppercase" size="sm" c="dimmed">Grand total</Text>
                <Text fw={800} size="lg" c="blue.7">{formatCurrency(r.grand_total)}</Text>
              </Group>
            </Stack>
          </Card>

          {/* Daily breakdown — date → systems → properties */}
          <Paper withBorder p="md" radius="md">
            <Group justify="space-between" mb="md">
              <Group gap="sm">
                <ThemeIcon size="lg" variant="light" color="teal" radius="md">
                  <IconCalendar size={18} />
                </ThemeIcon>
                <Text fw={700}>Daily Breakdown</Text>
              </Group>
              <Text size="xs" c="dimmed">{dayCount} day{dayCount === 1 ? '' : 's'} with records</Text>
            </Group>
            <Divider mb="md" />

            {r.days.length === 0 ? (
              <Box ta="center" py="xl">
                <Text c="dimmed" size="sm">No records to report for the selected period.</Text>
              </Box>
            ) : (
              <Table striped highlightOnHover withRowBorders={false}>
                <Table.Thead>
                  <Table.Tr>
                    <Table.Th>Date</Table.Th>
                    <Table.Th>System</Table.Th>
                    <Table.Th>Property</Table.Th>
                    <Table.Th style={{ textAlign: 'right' }}>Amount</Table.Th>
                    <Table.Th style={{ textAlign: 'right' }}>System Subtotal</Table.Th>
                    <Table.Th style={{ textAlign: 'right' }}>Day Total</Table.Th>
                  </Table.Tr>
                </Table.Thead>
                <Table.Tbody>
                  {r.days.flatMap((d) => {
                    const dayRowSpan = d.systems.reduce((acc, s) => acc + s.properties.length, 0);
                    let firstDayCell = true;
                    return d.systems.flatMap((s) => {
                      let firstSysCell = true;
                      return s.properties.map((p) => {
                        const row = (
                          <Table.Tr key={`${d.date}-${s.name}-${p.name}`}>
                            {firstDayCell && (
                              <Table.Td rowSpan={dayRowSpan} fw={600} valign="top">
                                {fmtDate(d.date)}
                              </Table.Td>
                            )}
                            {firstSysCell && (
                              <Table.Td rowSpan={s.properties.length} valign="top">
                                <Badge variant="light" color="blue" radius="sm">{s.name}</Badge>
                              </Table.Td>
                            )}
                            <Table.Td>{p.name}</Table.Td>
                            <Table.Td style={{ textAlign: 'right' }}>{formatCurrency(p.total)}</Table.Td>
                            {firstSysCell && (
                              <Table.Td rowSpan={s.properties.length} style={{ textAlign: 'right' }} valign="top" fw={600}>
                                {formatCurrency(s.subtotal)}
                              </Table.Td>
                            )}
                            {firstDayCell && (
                              <Table.Td rowSpan={dayRowSpan} style={{ textAlign: 'right' }} valign="top" fw={700} c="blue.7">
                                {formatCurrency(d.day_total)}
                              </Table.Td>
                            )}
                          </Table.Tr>
                        );
                        firstSysCell = false;
                        firstDayCell = false;
                        return row;
                      });
                    });
                  })}
                </Table.Tbody>
                <Table.Tfoot>
                  <Table.Tr>
                    <Table.Th colSpan={5} style={{ textAlign: 'right' }}>Grand total</Table.Th>
                    <Table.Th style={{ textAlign: 'right' }}>
                      <Text fw={800} c="blue.7" size="md">{formatCurrency(r.grand_total)}</Text>
                    </Table.Th>
                  </Table.Tr>
                </Table.Tfoot>
              </Table>
            )}
          </Paper>
        </>
      )}
    </Stack>
  );
}
