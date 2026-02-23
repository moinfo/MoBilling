import { SimpleGrid, Card, Text, Group } from '@mantine/core';
import { IconCash, IconReceipt, IconAlertTriangle, IconUsers, IconFileText } from '@tabler/icons-react';
import { formatCurrency } from '../../utils/formatCurrency';

interface Props {
  totalReceivable: number;
  totalReceived: number;
  outstanding: number;
  overdueInvoices: number;
  overdueBills: number;
  totalClients: number;
  totalDocuments: number;
}

export default function StatsCards(props: Props) {
  const cards = [
    { title: 'Total Receivable', value: formatCurrency(props.totalReceivable), icon: IconReceipt, color: 'blue' },
    { title: 'Total Received', value: formatCurrency(props.totalReceived), icon: IconCash, color: 'green' },
    { title: 'Outstanding', value: formatCurrency(props.outstanding), icon: IconAlertTriangle, color: 'orange' },
    { title: 'Overdue Invoices', value: String(props.overdueInvoices), icon: IconAlertTriangle, color: 'red' },
    { title: 'Overdue Bills', value: String(props.overdueBills), icon: IconAlertTriangle, color: 'red' },
    { title: 'Total Clients', value: String(props.totalClients), icon: IconUsers, color: 'teal' },
    { title: 'Total Documents', value: String(props.totalDocuments), icon: IconFileText, color: 'violet' },
  ];

  return (
    <SimpleGrid cols={{ base: 2, sm: 3, lg: 4 }}>
      {cards.map((card) => (
        <Card key={card.title} withBorder padding="lg" radius="md">
          <Group justify="space-between">
            <div>
              <Text size="xs" c="dimmed" tt="uppercase" fw={700}>{card.title}</Text>
              <Text fw={700} size="xl" mt={4}>{card.value}</Text>
            </div>
            <card.icon size={28} color={`var(--mantine-color-${card.color}-6)`} />
          </Group>
        </Card>
      ))}
    </SimpleGrid>
  );
}
