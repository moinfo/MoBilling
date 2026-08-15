import { Card, Group, Text, Badge, ThemeIcon, Box, Button } from '@mantine/core';
import { IconMoneybag, IconDownload } from '@tabler/icons-react';
import { useQuery } from '@tanstack/react-query';
import { useNavigate } from 'react-router-dom';
import { notifications } from '@mantine/notifications';
import { getMyPayslips, downloadMyPayslipPdf, Payslip } from '../../api/payroll';
import { formatCurrency } from '../../utils/formatCurrency';
import classes from './Dashboard.module.css';

function num(v: number | string | null | undefined): number {
  const n = typeof v === 'string' ? parseFloat(v) : v;
  return Number.isFinite(n as number) ? (n as number) : 0;
}

/** Every line that reduces net pay, itemized: PAYE + each statutory rate + each other deduction (catalog, penalties, loan, advance). */
function deductionItems(p: Payslip): { name: string; amount: number }[] {
  const items: { name: string; amount: number }[] = [];
  if (num(p.paye_amount) > 0) items.push({ name: 'PAYE', amount: num(p.paye_amount) });
  for (const b of p.statutory_employee_breakdown ?? []) items.push({ name: b.name, amount: num(b.amount) });
  for (const b of p.deductions_breakdown ?? []) items.push({ name: b.name, amount: num(b.amount) });
  return items;
}

function downloadBlob(data: BlobPart, filename: string) {
  const url = window.URL.createObjectURL(new Blob([data]));
  const a = window.document.createElement('a');
  a.href = url;
  a.download = filename;
  a.click();
  window.URL.revokeObjectURL(url);
}

/** The logged-in staff member's most recent finalized payslip — self-service, no permission required (mirrors MyAttendance/TotalDeductions). */
export default function MyPayroll() {
  const navigate = useNavigate();
  const { data } = useQuery({ queryKey: ['my-payslips'], queryFn: getMyPayslips });
  const payslips = data?.data?.data ?? [];
  const p = payslips[0];

  if (!p) return null;

  const gross = num(p.gross_pay);
  const net = num(p.net_pay);
  const deductions = Math.max(0, gross - net);
  const monthLabel = p.payroll_run?.month_key ?? '';
  const finalized = p.payroll_run?.status === 'finalized';
  const items = deductionItems(p);

  const download = async () => {
    try {
      const res = await downloadMyPayslipPdf(p.id);
      downloadBlob(res.data, `payslip-${monthLabel}.pdf`);
    } catch {
      notifications.show({ message: 'Failed to download payslip', color: 'red' });
    }
  };

  return (
    <Box>
      <div className={classes.sectionLabel} style={{ marginBottom: 12 }}>
        <Text fw={700} size="sm" tt="uppercase" c="dimmed" style={{ letterSpacing: 0.5 }}>My Payroll</Text>
      </div>

      <Card withBorder radius="md" p="md" shadow="xs" className={classes.statCard}
        style={{ ['--stat-accent' as string]: 'var(--mantine-color-teal-6)' }}>
        <Group justify="space-between" wrap="wrap">
          <Group gap="sm" wrap="nowrap">
            <ThemeIcon size={44} radius="md" variant="light" color="teal">
              <IconMoneybag size={24} />
            </ThemeIcon>
            <div>
              <Group gap={6} align="baseline">
                <Text size="xl" fw={800} lh={1.1} c="teal">{formatCurrency(net)}</Text>
                <Badge size="xs" color={finalized ? 'green' : 'yellow'}>{finalized ? 'Finalized' : 'Draft'}</Badge>
              </Group>
              <Text size="xs" c="dimmed">Net pay · {monthLabel}</Text>
            </div>
          </Group>
          <Group gap="xs" wrap="wrap">
            <Badge variant="light" radius="sm" color="blue">Gross: {formatCurrency(gross)}</Badge>
            <Badge variant="light" radius="sm" color={deductions > 0 ? 'red' : 'gray'}>Deductions: {formatCurrency(deductions)}</Badge>
          </Group>
        </Group>

        {items.length > 0 && (
          <Group gap={6} mt="sm">
            {items.map((it, idx) => (
              <Badge key={idx} size="xs" variant="light" color="orange" radius="sm">
                {it.name}: {formatCurrency(it.amount)}
              </Badge>
            ))}
          </Group>
        )}

        {!finalized && (
          <Text size="xs" c="dimmed" mt="xs">This period is still being prepared — deductions shown are current but may still change until finalized.</Text>
        )}

        <Group justify="flex-end" gap="xs" mt="sm">
          <Button size="compact-xs" variant="light" onClick={() => navigate('/payroll')}>View all</Button>
          {finalized && (
            <Button size="compact-xs" variant="light" leftSection={<IconDownload size={14} />} onClick={download}>Download</Button>
          )}
        </Group>
      </Card>
    </Box>
  );
}
