import { Group, Button, Menu } from '@mantine/core';
import { DatePickerInput, DatesRangeValue } from '@mantine/dates';
import { IconCalendar, IconChevronDown } from '@tabler/icons-react';
import dayjs from 'dayjs';

interface Props {
  value: [Date | null, Date | null];
  onChange: (range: [Date | null, Date | null]) => void;
}

function quarterStart(d: dayjs.Dayjs): dayjs.Dayjs {
  const q = Math.floor(d.month() / 3) * 3;
  return d.month(q).startOf('month');
}

function quarterEnd(d: dayjs.Dayjs): dayjs.Dayjs {
  const q = Math.floor(d.month() / 3) * 3 + 2;
  return d.month(q).endOf('month');
}

const presets: { label: string; range: () => [Date, Date] }[] = [
  { label: 'This Month', range: () => [dayjs().startOf('month').toDate(), dayjs().endOf('month').toDate()] },
  { label: 'Last Month', range: () => [dayjs().subtract(1, 'month').startOf('month').toDate(), dayjs().subtract(1, 'month').endOf('month').toDate()] },
  { label: 'This Quarter', range: () => [quarterStart(dayjs()).toDate(), quarterEnd(dayjs()).toDate()] },
  { label: 'Last Quarter', range: () => {
    const prev = dayjs().subtract(3, 'month');
    return [quarterStart(prev).toDate(), quarterEnd(prev).toDate()];
  }},
  { label: 'This Year', range: () => [dayjs().startOf('year').toDate(), dayjs().endOf('year').toDate()] },
  { label: 'Last 6 Months', range: () => [dayjs().subtract(6, 'month').startOf('month').toDate(), dayjs().endOf('month').toDate()] },
];

export default function DateRangeFilter({ value, onChange }: Props) {
  const handleChange = (val: DatesRangeValue) => {
    onChange(val as [Date | null, Date | null]);
  };

  return (
    <Group gap="sm">
      <DatePickerInput
        type="range"
        value={value}
        onChange={handleChange}
        leftSection={<IconCalendar size={16} />}
        placeholder="Select date range"
        size="sm"
        clearable
        maxDate={new Date()}
        style={{ minWidth: 260 }}
      />
      <Menu shadow="md" width={160}>
        <Menu.Target>
          <Button variant="light" size="sm" rightSection={<IconChevronDown size={14} />}>
            Presets
          </Button>
        </Menu.Target>
        <Menu.Dropdown>
          {presets.map((p) => (
            <Menu.Item key={p.label} onClick={() => onChange(p.range())}>
              {p.label}
            </Menu.Item>
          ))}
        </Menu.Dropdown>
      </Menu>
    </Group>
  );
}
