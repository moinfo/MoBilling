import { Group, Title, Stack } from '@mantine/core';
import DateRangeFilter from './DateRangeFilter';
import ExportButton from './ExportButton';
import { ReactNode } from 'react';

interface Props {
  title: string;
  dateRange: [Date | null, Date | null];
  onDateChange: (range: [Date | null, Date | null]) => void;
  exportData?: Record<string, unknown>[];
  exportFilename?: string;
  extra?: ReactNode;
  hideDateFilter?: boolean;
}

export default function ReportHeader({ title, dateRange, onDateChange, exportData, exportFilename, extra, hideDateFilter }: Props) {
  return (
    <Stack gap="xs">
      <Group justify="space-between" wrap="wrap">
        <Title order={2}>{title}</Title>
        <Group gap="sm" wrap="wrap">
          {!hideDateFilter && <DateRangeFilter value={dateRange} onChange={onDateChange} />}
          {extra}
          {exportData && exportData.length > 0 && (
            <ExportButton data={exportData} filename={exportFilename || 'report'} />
          )}
        </Group>
      </Group>
    </Stack>
  );
}
