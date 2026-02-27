import { Button } from '@mantine/core';
import { IconDownload } from '@tabler/icons-react';

interface Props {
  data: Record<string, unknown>[];
  filename?: string;
}

function toCsv(data: Record<string, unknown>[]): string {
  if (data.length === 0) return '';
  const headers = Object.keys(data[0]);
  const rows = data.map((row) =>
    headers.map((h) => {
      const val = row[h];
      const str = val === null || val === undefined ? '' : String(val);
      return str.includes(',') || str.includes('"') || str.includes('\n')
        ? `"${str.replace(/"/g, '""')}"`
        : str;
    }).join(',')
  );
  return [headers.join(','), ...rows].join('\n');
}

export default function ExportButton({ data, filename = 'report' }: Props) {
  const handleExport = () => {
    const csv = toCsv(data);
    const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `${filename}.csv`;
    a.click();
    URL.revokeObjectURL(url);
  };

  return (
    <Button
      variant="light"
      size="sm"
      leftSection={<IconDownload size={16} />}
      onClick={handleExport}
    >
      Export CSV
    </Button>
  );
}
