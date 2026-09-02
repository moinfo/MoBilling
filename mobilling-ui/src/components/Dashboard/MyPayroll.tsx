import { Card, Group, Text, Badge, Box, Button } from '@mantine/core';
import { IconDownload } from '@tabler/icons-react';
import { useQuery } from '@tanstack/react-query';
import { useNavigate } from 'react-router-dom';
import { notifications } from '@mantine/notifications';
import dayjs from 'dayjs';
import { getMyPayslips, downloadMyPayslipPdf, Payslip } from '../../api/payroll';
import { formatCurrency } from '../../utils/formatCurrency';
import classes from './Dashboard.module.css';

/** One ruled ledger row: label left, figure right in tabular numerals. */
function Line(
  { label, value, tone, total }:
  { label: string; value: string; tone?: 'keep' | 'lost'; total?: boolean },
) {
  const c = tone === 'keep' ? 'teal.7' : tone === 'lost' ? 'red.7' : undefined;
  return (
    <dl className={`${classes.ledgerRow} ${total ? classes.ledgerTotal : ''}`}>
      <dt>{label}</dt>
      <dd><Text span inherit c={c}>{value}</Text></dd>
    </dl>
  );
}

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

/**
 * The logged-in staff member's most recent payslip, set as a payslip:
 * gross, each deduction line, then net under a rule. Self-service, no
 * permission required.
 *
 * Kept deliberately separate from the "Your month" band above it, because it
 * describes a CLOSED period (last month's pay) while that band is the running
 * one — the previous layout put the two side by side with nothing marking the
 * difference.
 */
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
  // "2026-08" is a database key, not something to show a person.
  const prettyMonth = monthLabel ? dayjs(`${monthLabel}-01`).format('MMMM YYYY') : 'this period';
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
        <Text fw={700} size="sm" tt="uppercase" c="dimmed" style={{ letterSpacing: 0.5 }}>
          {finalized ? 'Your last payslip' : 'Your payslip in progress'}
        </Text>
      </div>

      {/* A payslip is an arithmetic document, so it is set as one: ruled rows,
          right-aligned tabular figures, the total under a rule. The badges this
          replaces put gross, deductions and net in three differently-coloured
          pills that never lined up — the sum they describe was invisible. */}
      <Card withBorder radius="md" p="md" className={classes.payslip}>
        <div className={classes.paneLabel}>
          <span>Pay for {prettyMonth}</span>
          <Badge size="xs" variant="light" color={finalized ? 'teal' : 'yellow'}>
            {finalized ? 'Final' : 'Draft'}
          </Badge>
        </div>

        <div className={classes.ledger}>
          <Line label="Gross pay" value={formatCurrency(gross)} />

          {items.map((it, idx) => (
            <Line key={idx} label={it.name} value={`−${formatCurrency(it.amount)}`} tone="lost" />
          ))}

          {items.length === 0 && deductions > 0 && (
            <Line label="Deductions" value={`−${formatCurrency(deductions)}`} tone="lost" />
          )}

          <div className={classes.ledgerRule}>
            <Line total label="Net pay" value={formatCurrency(net)} tone="keep" />
          </div>
        </div>

        {!finalized && (
          <p className={classes.ledgerNote}>
            Still being prepared. These figures can change until the run is finalized.
          </p>
        )}

        <Group gap="xs" mt="md">
          <Button size="compact-xs" variant="default" onClick={() => navigate('/payroll')}>All payslips</Button>
          {finalized && (
            <Button size="compact-xs" variant="default" leftSection={<IconDownload size={14} />} onClick={download}>
              Download PDF
            </Button>
          )}
        </Group>
      </Card>
    </Box>
  );
}
