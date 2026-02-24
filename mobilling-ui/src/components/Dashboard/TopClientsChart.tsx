import { Card, Text, Center } from '@mantine/core';
import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, Legend } from 'recharts';
import type { TopClient } from '../../api/dashboard';
import { formatCurrency } from '../../utils/formatCurrency';

interface Props {
  data: TopClient[];
}

export default function TopClientsChart({ data }: Props) {
  return (
    <Card withBorder padding="lg" radius="md" h="100%">
      <Text fw={600} mb="md">Top Clients</Text>
      {data.length === 0 ? (
        <Center h={250}><Text c="dimmed" size="sm">No client data yet</Text></Center>
      ) : (
        <ResponsiveContainer width="100%" height={250}>
          <BarChart data={data} layout="vertical" margin={{ top: 5, right: 20, bottom: 5, left: 60 }}>
            <CartesianGrid strokeDasharray="3 3" stroke="var(--mantine-color-default-border)" />
            <XAxis type="number" tick={{ fontSize: 12 }} tickFormatter={(v) => `${(v / 1000).toFixed(0)}k`} />
            <YAxis type="category" dataKey="name" tick={{ fontSize: 12 }} width={80} />
            <Tooltip formatter={(value: number, name: string) => [formatCurrency(value), name === 'total' ? 'Invoiced' : 'Paid']} />
            <Legend />
            <Bar dataKey="total" name="Invoiced" fill="#339af0" radius={[0, 4, 4, 0]} barSize={14} />
            <Bar dataKey="paid" name="Paid" fill="#40c057" radius={[0, 4, 4, 0]} barSize={14} />
          </BarChart>
        </ResponsiveContainer>
      )}
    </Card>
  );
}
