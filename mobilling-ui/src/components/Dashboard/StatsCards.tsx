import { SimpleGrid, Card, Text, Group } from '@mantine/core';
import { IconCash, IconReceipt, IconAlertTriangle, IconUsers, IconFileText, IconMessage, IconCalendarDue, IconWallet } from '@tabler/icons-react';
import { formatCurrency } from '../../utils/formatCurrency';
import { usePermissions } from '../../hooks/usePermissions';

interface Props {
  totalExpenses: number;
  totalReceivable: number;
  totalReceived: number;
  outstanding: number;
  overdueInvoices: number;
  overdueBills: number;
  totalClients: number;
  totalDocuments: number;
  smsBalance?: number | null;
  smsEnabled?: boolean;
  statutoryOverdue?: number;
  statutoryDueSoon?: number;
  periodLabel?: string;
}

export default function StatsCards(props: Props) {
  const { can } = usePermissions();

  const cards = [
    { title: `Total Receivable (${props.periodLabel ?? 'This Month'})`, value: formatCurrency(props.totalReceivable), icon: IconReceipt, color: 'blue', permission: 'dashboard.total_receivable' },
    { title: `Total Received (${props.periodLabel ?? 'This Month'})`, value: formatCurrency(props.totalReceived), icon: IconCash, color: 'green', permission: 'dashboard.total_received' },
    { title: `Outstanding (${props.periodLabel ?? 'This Month'})`, value: formatCurrency(props.outstanding), icon: IconAlertTriangle, color: 'orange', permission: 'dashboard.outstanding' },
    { title: `Expenses (${props.periodLabel ?? 'This Month'})`, value: formatCurrency(props.totalExpenses), icon: IconWallet, color: 'grape', permission: 'dashboard.expenses' },
    { title: 'Overdue Invoices', value: String(props.overdueInvoices), icon: IconAlertTriangle, color: 'red', permission: 'dashboard.overdue_invoices' },
    { title: 'Overdue Bills', value: String(props.overdueBills), icon: IconAlertTriangle, color: 'red', permission: 'dashboard.overdue_bills' },
    { title: 'Total Clients', value: String(props.totalClients), icon: IconUsers, color: 'teal', permission: 'dashboard.total_clients' },
    { title: 'Total Documents', value: String(props.totalDocuments), icon: IconFileText, color: 'violet', permission: 'dashboard.total_documents' },
    { title: 'Overdue Obligations', value: String(props.statutoryOverdue ?? 0), icon: IconCalendarDue, color: 'red', permission: 'dashboard.overdue_obligations' },
    { title: 'Due Soon Obligations', value: String(props.statutoryDueSoon ?? 0), icon: IconCalendarDue, color: 'orange', permission: 'dashboard.due_soon_obligations' },
    ...(props.smsEnabled ? [{ title: 'SMS Balance', value: props.smsBalance != null ? props.smsBalance.toLocaleString() : '—', icon: IconMessage, color: 'cyan', permission: 'dashboard.sms_balance' }] : []),
  ];

  const visibleCards = cards.filter((card) => can(card.permission));

  return (
    <SimpleGrid cols={{ base: 2, sm: 3, lg: 4 }}>
      {visibleCards.map((card) => (
        <Card key={card.title} withBorder padding="md" radius="md">
          <Group justify="space-between" wrap="nowrap" gap="xs">
            <div style={{ minWidth: 0 }}>
              <Text size="xs" c="dimmed" tt="uppercase" fw={700} truncate>{card.title}</Text>
              <Text fw={700} size="lg" mt={4} truncate>{card.value}</Text>
            </div>
            <card.icon size={24} color={`var(--mantine-color-${card.color}-6)`} style={{ flexShrink: 0 }} />
          </Group>
        </Card>
      ))}
    </SimpleGrid>
  );
}
