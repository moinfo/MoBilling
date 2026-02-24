import { Card, Text, Center } from '@mantine/core';
import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer } from 'recharts';
import type { PaymentMethodItem } from '../../api/dashboard';
import { formatCurrency } from '../../utils/formatCurrency';

const METHOD_LABELS: Record<string, string> = {
  mpesa: 'M-Pesa',
  bank: 'Bank',
  cash: 'Cash',
  card: 'Card',
  cheque: 'Cheque',
};

interface Props {
  data: PaymentMethodItem[];
}

export default function PaymentMethodChart({ data }: Props) {
  const chartData = data.map((item) => ({
    name: METHOD_LABELS[item.method] || item.method,
    amount: item.amount,
  }));

  return (
    <Card withBorder padding="lg" radius="md" h="100%">
      <Text fw={600} mb="md">Payments by Method</Text>
      {chartData.length === 0 ? (
        <Center h={250}><Text c="dimmed" size="sm">No payments yet</Text></Center>
      ) : (
        <ResponsiveContainer width="100%" height={250}>
          <BarChart data={chartData} margin={{ top: 5, right: 20, bottom: 5, left: 10 }}>
            <CartesianGrid strokeDasharray="3 3" stroke="var(--mantine-color-default-border)" />
            <XAxis dataKey="name" tick={{ fontSize: 12 }} />
            <YAxis tick={{ fontSize: 12 }} tickFormatter={(v) => `${(v / 1000).toFixed(0)}k`} />
            <Tooltip formatter={(value: number) => [formatCurrency(value), 'Amount']} />
            <Bar dataKey="amount" fill="#7c3aed" radius={[6, 6, 0, 0]} barSize={40} />
          </BarChart>
        </ResponsiveContainer>
      )}
    </Card>
  );
}
