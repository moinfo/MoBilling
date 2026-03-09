import { useState, useMemo } from 'react';
import {
  Paper, Text, Group, Badge, Stack, SimpleGrid,
  ActionIcon, Tooltip, Box, ScrollArea, Divider,
} from '@mantine/core';
import {
  IconChevronLeft, IconChevronRight, IconPhoneCall,
  IconHeartHandshake, IconMapPin, IconFileInvoice,
  IconReceipt, IconShieldCheck,
} from '@tabler/icons-react';
import { CalendarDay, CalendarItem } from '../../api/dashboard';

interface Props {
  data: CalendarDay[];
}

const DAYS = ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'];
const MONTHS = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

const typeConfig: Record<string, { icon: typeof IconPhoneCall; color: string; label: string }> = {
  followup: { icon: IconPhoneCall, color: 'blue', label: 'Follow-up' },
  satisfaction: { icon: IconHeartHandshake, color: 'teal', label: 'Satisfaction Call' },
  appointment: { icon: IconMapPin, color: 'orange', label: 'Client Visit' },
  invoice: { icon: IconFileInvoice, color: 'red', label: 'Invoice Due' },
  bill: { icon: IconReceipt, color: 'yellow', label: 'Bill Due' },
  statutory: { icon: IconShieldCheck, color: 'violet', label: 'Statutory' },
};

function primaryColor(items: CalendarItem[]): string {
  const priority = ['appointment', 'invoice', 'bill', 'followup', 'satisfaction', 'statutory'];
  for (const t of priority) {
    if (items.some((i) => i.type === t)) return typeConfig[t].color;
  }
  return 'gray';
}

export default function ActivityCalendar({ data }: Props) {
  const today = new Date();
  const [month, setMonth] = useState(today.getMonth());
  const [year, setYear] = useState(today.getFullYear());
  const [selectedDate, setSelectedDate] = useState<string | null>(
    today.toISOString().split('T')[0]
  );

  const dayMap = useMemo(() => {
    const map: Record<string, CalendarDay> = {};
    data.forEach((d) => { map[d.date] = d; });
    return map;
  }, [data]);

  const prevMonth = () => {
    if (month === 0) { setMonth(11); setYear(year - 1); }
    else setMonth(month - 1);
  };

  const nextMonth = () => {
    if (month === 11) { setMonth(0); setYear(year + 1); }
    else setMonth(month + 1);
  };

  const goToday = () => {
    setMonth(today.getMonth());
    setYear(today.getFullYear());
    setSelectedDate(today.toISOString().split('T')[0]);
  };

  const firstDay = new Date(year, month, 1).getDay();
  const daysInMonth = new Date(year, month + 1, 0).getDate();
  const todayStr = today.toISOString().split('T')[0];

  const cells: (number | null)[] = [];
  for (let i = 0; i < firstDay; i++) cells.push(null);
  for (let d = 1; d <= daysInMonth; d++) cells.push(d);

  const selected = selectedDate ? dayMap[selectedDate] : null;

  // Group items by type for the detail panel
  const groupedItems = useMemo(() => {
    if (!selected) return {};
    const groups: Record<string, CalendarItem[]> = {};
    selected.items.forEach((item) => {
      if (!groups[item.type]) groups[item.type] = [];
      groups[item.type].push(item);
    });
    return groups;
  }, [selected]);

  return (
    <Paper withBorder p="md" radius="md">
      <Stack gap="xs">
        {/* Header */}
        <Group justify="space-between" mb={4}>
          <Group gap={6}>
            <ActionIcon variant="subtle" onClick={prevMonth} size="sm">
              <IconChevronLeft size={16} />
            </ActionIcon>
            <Text fw={700} size="md" w={160} ta="center">
              {MONTHS[month]} {year}
            </Text>
            <ActionIcon variant="subtle" onClick={nextMonth} size="sm">
              <IconChevronRight size={16} />
            </ActionIcon>
          </Group>
          <Badge
            variant="light" color="blue" size="sm"
            style={{ cursor: 'pointer' }}
            onClick={goToday}
          >
            Today
          </Badge>
        </Group>

        {/* Day headers */}
        <SimpleGrid cols={7} spacing={0}>
          {DAYS.map((d) => (
            <Text key={d} size="xs" fw={700} c="dimmed" ta="center" py={2}>{d}</Text>
          ))}
        </SimpleGrid>

        {/* Calendar grid */}
        <SimpleGrid cols={7} spacing={0}>
          {cells.map((day, i) => {
            if (day === null) return <Box key={`e-${i}`} h={36} />;

            const dateStr = `${year}-${String(month + 1).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
            const entry = dayMap[dateStr];
            const count = entry ? entry.items.length : 0;
            const isToday = dateStr === todayStr;
            const isSelected = dateStr === selectedDate;

            return (
              <Tooltip
                key={dateStr}
                label={count > 0 ? `${count} activit${count === 1 ? 'y' : 'ies'}` : undefined}
                disabled={count === 0}
                position="top"
                withArrow
              >
                <Box
                  h={36}
                  style={{
                    display: 'flex',
                    flexDirection: 'column',
                    alignItems: 'center',
                    justifyContent: 'center',
                    borderRadius: 'var(--mantine-radius-sm)',
                    cursor: 'pointer',
                    border: isSelected
                      ? '2px solid var(--mantine-color-blue-5)'
                      : isToday
                        ? '1px solid var(--mantine-color-blue-3)'
                        : '1px solid transparent',
                    background: isSelected ? 'var(--mantine-color-blue-light)' : undefined,
                    transition: 'all 0.1s',
                  }}
                  onClick={() => setSelectedDate(dateStr)}
                >
                  <Text
                    size="sm"
                    fw={isToday || isSelected ? 700 : 400}
                    c={count === 0 && !isToday ? 'dimmed' : undefined}
                    lh={1}
                  >
                    {day}
                  </Text>
                  {count > 0 && (
                    <Group gap={2} mt={2} justify="center" wrap="nowrap">
                      {[...new Set(entry!.items.map((it) => it.type))].slice(0, 3).map((t) => (
                        <Box
                          key={t}
                          w={5} h={5}
                          style={{
                            borderRadius: '50%',
                            background: `var(--mantine-color-${typeConfig[t]?.color || 'gray'}-5)`,
                          }}
                        />
                      ))}
                    </Group>
                  )}
                </Box>
              </Tooltip>
            );
          })}
        </SimpleGrid>

        <Divider />

        {/* Detail panel */}
        <Box>
          <Text size="xs" fw={700} c="dimmed" mb={4}>
            {selectedDate
              ? new Date(selectedDate + 'T12:00:00').toLocaleDateString('en-US', { weekday: 'long', month: 'short', day: 'numeric' })
              : 'Select a day'}
          </Text>

          {!selected || selected.items.length === 0 ? (
            <Text size="sm" c="dimmed" fs="italic">No activities</Text>
          ) : (
            <ScrollArea.Autosize mah={200}>
              <Stack gap={8}>
                {Object.entries(groupedItems).map(([type, items]) => {
                  const cfg = typeConfig[type];
                  if (!cfg) return null;
                  const Icon = cfg.icon;
                  return (
                    <Box key={type}>
                      <Group gap={6} mb={4}>
                        <Icon size={14} color={`var(--mantine-color-${cfg.color}-6)`} />
                        <Text size="xs" fw={700} c={cfg.color}>{cfg.label}</Text>
                        <Badge size="xs" variant="filled" color={cfg.color} circle>{items.length}</Badge>
                      </Group>
                      <Stack gap={2} pl={20}>
                        {items.map((item, idx) => (
                          <Group key={idx} gap={6} wrap="nowrap">
                            <Text size="xs" fw={500} style={{ textTransform: 'uppercase' }} lineClamp={1}>
                              {item.label}
                            </Text>
                            {item.detail && (
                              <Text size="xs" c="dimmed" lineClamp={1}>{item.detail}</Text>
                            )}
                          </Group>
                        ))}
                      </Stack>
                    </Box>
                  );
                })}
              </Stack>
            </ScrollArea.Autosize>
          )}
        </Box>

        {/* Legend */}
        <Group gap="sm" justify="center" mt={2}>
          {Object.entries(typeConfig).map(([key, cfg]) => (
            <Group key={key} gap={4} wrap="nowrap">
              <Box w={6} h={6} style={{ borderRadius: '50%', background: `var(--mantine-color-${cfg.color}-5)` }} />
              <Text size={10} c="dimmed">{cfg.label}</Text>
            </Group>
          ))}
        </Group>
      </Stack>
    </Paper>
  );
}
