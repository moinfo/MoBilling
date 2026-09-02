import { useState } from 'react';
import { useQuery, keepPreviousData } from '@tanstack/react-query';
import { Card, Group, Text, Badge, Table, ThemeIcon, Box, Button, Modal, Loader } from '@mantine/core';
import { MonthPickerInput } from '@mantine/dates';
import { IconReceiptOff, IconCircleCheck, IconReportAnalytics } from '@tabler/icons-react';
import dayjs from 'dayjs';
import type { StaffPenaltiesSummary } from '../../api/dashboard';
import { getMyPenalties } from '../../api/dashboard';
import { formatCurrency } from '../../utils/formatCurrency';
import classes from './Dashboard.module.css';

const typeLabel = (penalty: string, report: string) =>
  `${penalty === 'late' ? 'Late' : 'Missing'} ${report} report`;

export default function StaffPenalties({ data }: { data: StaffPenaltiesSummary }) {
  const none = data.count_this_month === 0 && data.items.length === 0;
  const [open, setOpen] = useState(false);
  const [selectedMonth, setSelectedMonth] = useState<Date>(new Date());

  const safeDate = selectedMonth instanceof Date && !isNaN(selectedMonth.getTime()) ? selectedMonth : new Date();
  const reportMonth = safeDate.getMonth() + 1;
  const reportYear = safeDate.getFullYear();

  const { data: monthResp, isFetching } = useQuery({
    queryKey: ['my-penalties', reportMonth, reportYear],
    queryFn: () => getMyPenalties(reportMonth, reportYear),
    enabled: open,
    placeholderData: keepPreviousData,
  });
  const report = monthResp?.data;

  return (
    <Box>
      <div className={classes.sectionLabel} style={{ marginBottom: 12 }}>
        <Text fw={700} size="sm" tt="uppercase" c="dimmed" style={{ letterSpacing: 0.5 }}>My Report Deductions</Text>
      </div>

      <Card withBorder radius="md" p="md" shadow="xs" className={classes.statCard}
        style={{ ['--stat-accent' as string]: `var(--mantine-color-${none ? 'teal' : 'red'}-6)` }}>
        <Group justify="space-between" wrap="wrap">
          <Group gap="sm" wrap="nowrap">
            <ThemeIcon size={44} radius="md" variant="light" color={none ? 'teal' : 'red'}>
              {none ? <IconCircleCheck size={24} /> : <IconReceiptOff size={24} />}
            </ThemeIcon>
            <div>
              <Text size="xl" fw={800} lh={1.1} c={none ? 'teal' : 'red'}>
                {formatCurrency(data.month_total)}
              </Text>
              <Text size="xs" c="dimmed">
                Deducted in {data.month_label} · {data.count_this_month} report{data.count_this_month === 1 ? '' : 's'}
              </Text>
            </div>
          </Group>
          {!none && data.items.length > 0 && (
            <Button size="compact-xs" variant="light" color="red" leftSection={<IconReportAnalytics size={14} />}
              onClick={() => setOpen(true)}>
              Full report
            </Button>
          )}
        </Group>

        {/* Per-type breakdown so daily / weekly / monthly are all visible */}
        {(data.by_type?.length ?? 0) > 0 && (
          <Group gap="xs" mt="sm">
            {data.by_type!.map((t) => (
              <Badge key={t.report_type} variant="light" radius="sm"
                color={t.count > 0 ? 'red' : 'gray'} tt="capitalize">
                {t.report_type}: {t.count > 0 ? `${t.count} · ${formatCurrency(t.total)}` : 'none'}
              </Badge>
            ))}
          </Group>
        )}

        {none && (
          <Text size="sm" c="dimmed" mt="xs">
            Great — no missing or late reports this month. Submit each report before its deadline to avoid deductions.
          </Text>
        )}
      </Card>

      <Modal opened={open} onClose={() => setOpen(false)} size="lg"
        title={`Report deductions · ${report?.month_label ?? data.month_label}`}>
        <Group justify="space-between" align="center" mb="sm">
          <Text size="sm" c="dimmed">
            {report ? `${report.count_this_month} deduction${report.count_this_month === 1 ? '' : 's'} · ${formatCurrency(report.month_total)}` : ' '}
          </Text>
          <MonthPickerInput
            value={selectedMonth}
            onChange={(val) => {
              if (!val) return;
              try {
                const d = new Date(val as any);
                if (!isNaN(d.getTime())) setSelectedMonth(d);
              } catch { /* ignore */ }
            }}
            maxDate={new Date()}
            maxLevel="decade"
            w={160}
            size="sm"
          />
        </Group>
        <Table.ScrollContainer minWidth={420}>
          <Table verticalSpacing={6} highlightOnHover>
            <Table.Thead>
              <Table.Tr>
                <Table.Th>Date</Table.Th>
                <Table.Th>Reason</Table.Th>
                <Table.Th ta="right">Amount</Table.Th>
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {(report?.items ?? []).map((p) => (
                <Table.Tr key={p.id}>
                  <Table.Td>{dayjs(p.period_date).format('D MMM YYYY')}</Table.Td>
                  <Table.Td>
                    <Group gap={6} wrap="nowrap">
                      <Badge size="xs" variant="light" color={p.penalty_type === 'late' ? 'orange' : 'red'}>
                        {p.penalty_type}
                      </Badge>
                      <Text size="sm">{p.notes ?? typeLabel(p.penalty_type, p.report_type)}</Text>
                    </Group>
                  </Table.Td>
                  <Table.Td ta="right" fw={600} c="red">−{formatCurrency(p.amount)}</Table.Td>
                </Table.Tr>
              ))}
              {isFetching && (
                <Table.Tr>
                  <Table.Td colSpan={3}><Group justify="center" py="sm"><Loader size="xs" /></Group></Table.Td>
                </Table.Tr>
              )}
              {!isFetching && report && report.items.length === 0 && (
                <Table.Tr>
                  <Table.Td colSpan={3}>
                    <Text size="sm" c="dimmed" ta="center" py="sm">No deductions for {report.month_label}.</Text>
                  </Table.Td>
                </Table.Tr>
              )}
            </Table.Tbody>
          </Table>
        </Table.ScrollContainer>
      </Modal>
    </Box>
  );
}
