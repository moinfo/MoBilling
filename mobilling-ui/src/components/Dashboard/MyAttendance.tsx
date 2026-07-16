import { Card, Group, Text, Badge, ThemeIcon, Box, Stack } from '@mantine/core';
import { IconLogin2, IconLogout2, IconClockHour4, IconReceiptOff } from '@tabler/icons-react';
import { useQuery } from '@tanstack/react-query';
import dayjs from 'dayjs';
import { getMyAttendance } from '../../api/attendance';
import classes from './Dashboard.module.css';

const dtypeLabel: Record<string, string> = {
  absent: 'Absent', late: 'Late', left_early: 'Left early', no_checkout: 'No check-out',
};

export default function MyAttendance() {
  const { data } = useQuery({ queryKey: ['my-attendance'], queryFn: getMyAttendance });
  const a = data?.data?.data;

  if (!a) return null;
  const t = a.today;
  const s = a.settings;

  return (
    <Box>
      <div className={classes.sectionLabel} style={{ marginBottom: 12 }}>
        <Text fw={700} size="sm" tt="uppercase" c="dimmed" style={{ letterSpacing: 0.5 }}>My Attendance</Text>
      </div>

      <Card withBorder radius="md" p="md" shadow="xs" className={classes.statCard}
        style={{ ['--stat-accent' as string]: 'var(--mantine-color-blue-6)' }}>
        <Group justify="space-between" wrap="wrap" gap="md">
          <Group gap="lg" wrap="wrap">
            <div>
              <Text size="xs" c="dimmed" tt="uppercase" fw={700}>Today · {dayjs().format('ddd, D MMM')}</Text>
              <Group gap="lg" mt={4}>
                <Group gap={6}>
                  <ThemeIcon size={30} radius="md" variant="light" color={t?.check_in_at ? (t.late ? 'orange' : 'teal') : 'gray'}>
                    <IconLogin2 size={16} />
                  </ThemeIcon>
                  <div>
                    <Text size="sm" fw={700}>{t?.check_in_at ?? '—'}</Text>
                    <Text size="xs" c="dimmed">in · target {s.check_in_time}</Text>
                  </div>
                  {t?.late && <Badge size="xs" color="orange" variant="light">late</Badge>}
                </Group>
                <Group gap={6}>
                  <ThemeIcon size={30} radius="md" variant="light" color={t?.check_out_at ? (t.left_early ? 'orange' : 'teal') : 'gray'}>
                    <IconLogout2 size={16} />
                  </ThemeIcon>
                  <div>
                    <Text size="sm" fw={700}>{t?.check_out_at ?? '—'}</Text>
                    <Text size="xs" c="dimmed">out · target {s.check_out_time}</Text>
                  </div>
                  {t?.left_early && <Badge size="xs" color="orange" variant="light">early</Badge>}
                </Group>
              </Group>
            </div>

            <Badge size="lg" variant="light"
              color={!t?.check_in_at ? 'gray' : t.late ? 'orange' : 'teal'}>
              {!t?.check_in_at ? 'Not marked yet' : t.late ? 'Present (late)' : 'Present'}
            </Badge>
          </Group>

          <Stack gap={2} align="flex-end">
            <Group gap={6}>
              <IconClockHour4 size={14} />
              <Text size="sm">{a.present_days} day{a.present_days === 1 ? '' : 's'} present · {a.month_label}</Text>
            </Group>
            {s.penalties_enabled && a.deduction_total > 0 && (
              <Group gap={6}>
                <IconReceiptOff size={14} color="var(--mantine-color-red-6)" />
                <Text size="sm" c="red" fw={600}>−TZS {a.deduction_total.toLocaleString()} deducted</Text>
              </Group>
            )}
          </Stack>
        </Group>

        {s.penalties_enabled && a.deduction_total > 0 && a.deduction_by_type && (
          <Group gap={6} mt="sm">
            {(['absent', 'late', 'left_early', 'no_checkout'] as const).map((tp) =>
              a.deduction_by_type![tp] > 0 ? (
                <Badge key={tp} variant="light" color={tp === 'absent' ? 'red' : 'orange'} radius="sm">
                  {dtypeLabel[tp]}: {a.deduction_by_type![tp]}
                </Badge>
              ) : null,
            )}
          </Group>
        )}

        {/* Rules & deduction amounts — so staff know what applies */}
        <Stack gap={4} mt="sm" pt="sm" style={{ borderTop: '1px solid var(--mantine-color-default-border)' }}>
          <Text size="xs" c="dimmed">
            <b>Rules:</b> check in by <b>{s.check_in_time}</b>, check out by <b>{s.check_out_time}</b>. A missing check-in counts as absent even if you check out.
          </Text>
          {s.penalties_enabled && (
            <Group gap={6}>
              {([['absent', s.penalty_absent], ['late', s.penalty_late], ['left_early', s.penalty_left_early], ['no_checkout', s.penalty_no_checkout]] as const).map(([tp, amt]) => (
                <Badge key={tp} variant="outline" color="gray" radius="sm" size="sm">
                  {dtypeLabel[tp]} −TZS {Number(amt).toLocaleString()}
                </Badge>
              ))}
            </Group>
          )}
        </Stack>
      </Card>
    </Box>
  );
}
