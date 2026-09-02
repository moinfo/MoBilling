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
  const [open, setOpen] = useState(false);
  const [selectedMonth, setSelectedMonth] = useState<Date>(new Date());

  const safeDate = selectedMonth instanceof Date && !isNaN(selectedMonth.getTime()) ? selectedMonth : new Date();
  const month = safeDate.getMonth() + 1;
  const year = safeDate.getFullYear();
  const now = new Date();
  const isCurrentMonth = month === now.getMonth() + 1 && year === now.getFullYear();

  const { data: monthResp, isFetching } = useQuery({
    queryKey: ['my-penalties', month, year],
    queryFn: () => getMyPenalties(month, year),
    placeholderData: keepPreviousData,
  });
  // The dashboard's own payload already has the current month, so use it
  // as an instant first paint instead of waiting on this card's own fetch.
  const report = monthResp?.data ?? (isCurrentMonth ? data : undefined);
  const none = (report?.count_this_month ?? 0) === 0 && (report?.items.length ?? 0) === 0;

  return (
    <Box>
      <Group justify="space-between" align="center" mb={12}>
        <div className={classes.sectionLabel}>
          <Text fw={700} size="sm" tt="uppercase" c="dimmed" style={{ letterSpacing: 0.5 }}>My Report Deductions</Text>
        </div>
        <MonthPickerInput
          value={selectedMonth}
          onChange={(val) => {
            if (!val) return;
            try {
              const d = new Date(val as any);
              if (!isNaN(d.getTime())) setSelectedMonth(d);
            } catch { /* ignore */ }
          }}
          maxDate={now}
          maxLevel="decade"
          w={150}
          size="xs"
        />
      </Group>

      <Card withBorder radius="md" p="md" shadow="xs" className={classes.statCard}
        style={{ ['--stat-accent' as string]: `var(--mantine-color-${none ? 'teal' : 'red'}-6)` }}>
        <Group justify="space-between" wrap="wrap">
          <Group gap="sm" wrap="nowrap">
            <ThemeIcon size={44} radius="md" variant="light" color={none ? 'teal' : 'red'}>
              {none ? <IconCircleCheck size={24} /> : <IconReceiptOff size={24} />}
            </ThemeIcon>
            <div>
              <Text size="xl" fw={800} lh={1.1} c={none ? 'teal' : 'red'}>
                {report ? formatCurrency(report.month_total) : <Loader size="sm" />}
              </Text>
              <Text size="xs" c="dimmed">
                Deducted in {report?.month_label ?? dayjs(safeDate).format('MMM YYYY')}
                {report ? ` · ${report.count_this_month} report${report.count_this_month === 1 ? '' : 's'}` : ''}
              </Text>
            </div>
          </Group>
          {!none && (report?.items.length ?? 0) > 0 && (
            <Button size="compact-xs" variant="light" color="red" leftSection={<IconReportAnalytics size={14} />}
              onClick={() => setOpen(true)}>
              Full report
            </Button>
          )}
        </Group>

        {/* Per-type breakdown so daily / weekly / monthly are all visible */}
        {(report?.by_type?.length ?? 0) > 0 && (
          <Group gap="xs" mt="sm">
            {report!.by_type!.map((t) => (
              <Badge key={t.report_type} variant="light" radius="sm"
                color={t.count > 0 ? 'red' : 'gray'} tt="capitalize">
                {t.report_type}: {t.count > 0 ? `${t.count} · ${formatCurrency(t.total)}` : 'none'}
              </Badge>
            ))}
          </Group>
        )}

        {none && (
          <Text size="sm" c="dimmed" mt="xs">
            {isCurrentMonth
              ? 'Great — no missing or late reports this month. Submit each report before its deadline to avoid deductions.'
              : `No missing or late reports for ${report?.month_label ?? dayjs(safeDate).format('MMM YYYY')}.`}
          </Text>
        )}
      </Card>

      <Modal opened={open} onClose={() => setOpen(false)} size="lg"
        title={`Report deductions · ${report?.month_label ?? dayjs(safeDate).format('MMM YYYY')}`}>
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
            </Table.Tbody>
          </Table>
        </Table.ScrollContainer>
      </Modal>
    </Box>
  );
}
