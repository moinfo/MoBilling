import { Card, Text, Center, useComputedColorScheme } from '@mantine/core';
import { PieChart, Pie, Cell, Tooltip, ResponsiveContainer, Legend } from 'recharts';
import type { InvoiceStatusItem } from '../../api/dashboard';
import { chartTooltipStyle } from './chartTheme';

const STATUS_COLORS: Record<string, string> = {
  paid: '#40c057',
  sent: '#339af0',
  draft: '#868e96',
  partial: '#fab005',
  overdue: '#fa5252',
};

interface Props {
  data: InvoiceStatusItem[];
}

export default function InvoiceStatusChart({ data }: Props) {
  const dark = useComputedColorScheme('light') === 'dark';

  const chartData = data.map((item) => ({
    name: item.status.charAt(0).toUpperCase() + item.status.slice(1),
    value: item.count,
    color: STATUS_COLORS[item.status] || '#868e96',
  }));

  return (
    <Card withBorder padding="lg" radius="md" h="100%">
      <Text fw={600} mb="md">Invoice Status</Text>
      {chartData.length === 0 ? (
        <Center h={250}><Text c="dimmed" size="sm">No invoices yet</Text></Center>
      ) : (
        <ResponsiveContainer width="100%" height={250}>
          <PieChart>
            <Pie
              data={chartData}
              cx="50%"
              cy="50%"
              innerRadius={60}
              outerRadius={90}
              paddingAngle={3}
              dataKey="value"
            >
              {chartData.map((entry, index) => (
                <Cell key={index} fill={entry.color} />
              ))}
            </Pie>
            <Tooltip
              formatter={((value: any) => [value ?? 0, 'Invoices']) as any}
              contentStyle={chartTooltipStyle(dark)}
            />
            <Legend wrapperStyle={{ color: dark ? '#c1c2c5' : '#495057' }} />
          </PieChart>
        </ResponsiveContainer>
      )}
    </Card>
  );
}
