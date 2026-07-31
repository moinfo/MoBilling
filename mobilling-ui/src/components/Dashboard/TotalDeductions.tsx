import { Card, Group, Text, Badge, ThemeIcon, Box } from '@mantine/core';
import { IconCoins } from '@tabler/icons-react';
import { useQuery } from '@tanstack/react-query';
import { getMyAttendance } from '../../api/attendance';
import type { StaffPenaltiesSummary } from '../../api/dashboard';
import { formatCurrency } from '../../utils/formatCurrency';
import classes from './Dashboard.module.css';

/**
 * One headline number: everything deducted from the logged-in staff member
 * this month — attendance charges + report charges combined.
 */
export default function TotalDeductions({ reportPenalties }: { reportPenalties?: StaffPenaltiesSummary | null }) {
  const { data } = useQuery({ queryKey: ['my-attendance'], queryFn: getMyAttendance });
  const a = data?.data?.data;

  const attendanceTotal = Number(a?.deduction_total ?? 0);
  const reportTotal = Number(reportPenalties?.month_total ?? 0);
  const total = attendanceTotal + reportTotal;
  const none = total <= 0;

  return (
    <Box>
      <div className={classes.sectionLabel} style={{ marginBottom: 12 }}>
        <Text fw={700} size="sm" tt="uppercase" c="dimmed" style={{ letterSpacing: 0.5 }}>My Total Deductions</Text>
      </div>

      <Card withBorder radius="md" p="md" shadow="xs" className={classes.statCard}
        style={{ ['--stat-accent' as string]: `var(--mantine-color-${none ? 'teal' : 'red'}-6)` }}>
        <Group justify="space-between" wrap="wrap">
          <Group gap="sm" wrap="nowrap">
            <ThemeIcon size={44} radius="md" variant="light" color={none ? 'teal' : 'red'}>
              <IconCoins size={24} />
            </ThemeIcon>
            <div>
              <Text size="xl" fw={800} lh={1.1} c={none ? 'teal' : 'red'}>
                {formatCurrency(total)}
              </Text>
              <Text size="xs" c="dimmed">
                Attendance + reports · {a?.month_label ?? reportPenalties?.month_label ?? 'this month'}
              </Text>
            </div>
          </Group>
          <Group gap="xs" wrap="wrap">
            <Badge variant="light" radius="sm" color={attendanceTotal > 0 ? 'red' : 'gray'}>
              Attendance: {formatCurrency(attendanceTotal)}
            </Badge>
            <Badge variant="light" radius="sm" color={reportTotal > 0 ? 'red' : 'gray'}>
              Reports: {formatCurrency(reportTotal)}
            </Badge>
          </Group>
        </Group>
      </Card>
    </Box>
  );
}
