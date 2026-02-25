import { Card, Text, useMantineTheme, useComputedColorScheme } from '@mantine/core';
import {
  AreaChart, Area, XAxis, YAxis, CartesianGrid, Tooltip,
  ResponsiveContainer, Legend,
} from 'recharts';
import type { MonthlyRevenue } from '../../api/dashboard';
import { formatCurrency } from '../../utils/formatCurrency';
import { chartTooltipStyle, chartTickStyle } from './chartTheme';

interface Props {
  data: MonthlyRevenue[];
}

export default function RevenueChart({ data }: Props) {
  const theme = useMantineTheme();
  const dark = useComputedColorScheme('light') === 'dark';
  const invoicedColor = theme.colors.blue[6];
  const collectedColor = theme.colors.green[6];
  const tick = chartTickStyle(dark);

  return (
    <Card withBorder padding="lg" radius="md">
      <Text fw={600} mb="md">Revenue Overview</Text>
      <ResponsiveContainer width="100%" height={300}>
        <AreaChart data={data} margin={{ top: 5, right: 20, bottom: 5, left: 10 }}>
          <defs>
            <linearGradient id="gradInvoiced" x1="0" y1="0" x2="0" y2="1">
              <stop offset="5%" stopColor={invoicedColor} stopOpacity={0.3} />
              <stop offset="95%" stopColor={invoicedColor} stopOpacity={0} />
            </linearGradient>
            <linearGradient id="gradCollected" x1="0" y1="0" x2="0" y2="1">
              <stop offset="5%" stopColor={collectedColor} stopOpacity={0.3} />
              <stop offset="95%" stopColor={collectedColor} stopOpacity={0} />
            </linearGradient>
          </defs>
          <CartesianGrid strokeDasharray="3 3" stroke={dark ? '#404040' : '#e9ecef'} />
          <XAxis dataKey="month" tick={tick} />
          <YAxis tick={tick} tickFormatter={(v) => `${(v / 1000).toFixed(0)}k`} />
          <Tooltip
            formatter={((value: any, name: any) => [formatCurrency(value ?? 0), name]) as any}
            contentStyle={chartTooltipStyle(dark)}
          />
          <Legend wrapperStyle={{ color: dark ? '#c1c2c5' : '#495057' }} />
          <Area
            type="monotone"
            dataKey="invoiced"
            name="Invoiced"
            stroke={invoicedColor}
            fillOpacity={1}
            fill="url(#gradInvoiced)"
            strokeWidth={2}
          />
          <Area
            type="monotone"
            dataKey="collected"
            name="Collected"
            stroke={collectedColor}
            fillOpacity={1}
            fill="url(#gradCollected)"
            strokeWidth={2}
          />
        </AreaChart>
      </ResponsiveContainer>
    </Card>
  );
}
