import { SimpleGrid, Card, Text, Group, ThemeIcon } from '@mantine/core';
import { IconCash, IconReceipt, IconAlertTriangle, IconUsers, IconFileText, IconMessage, IconCalendarDue, IconWallet, IconBrandWhatsapp, IconMapPin } from '@tabler/icons-react';
import { formatCurrency } from '../../utils/formatCurrency';
import { usePermissions } from '../../hooks/usePermissions';
import classes from './Dashboard.module.css';

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
  totalWhatsappContacts?: number;
  totalFieldVisits?: number;
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
    { title: 'WhatsApp Contacts', value: String(props.totalWhatsappContacts ?? 0), icon: IconBrandWhatsapp, color: 'green',  permission: 'dashboard.whatsapp_contacts' },
    { title: 'Field Prospects',   value: String(props.totalFieldVisits ?? 0),      icon: IconMapPin,         color: 'orange', permission: 'dashboard.field_visits'      },
  ];

  const visibleCards = cards.filter((card) => can(card.permission));

  return (
    <SimpleGrid cols={{ base: 2, sm: 3, lg: 4 }} spacing="md">
      {visibleCards.map((card) => (
        <Card key={card.title} withBorder padding="md" radius="md" shadow="xs"
          className={classes.statCard}
          style={{ ['--stat-accent' as string]: `var(--mantine-color-${card.color}-6)` }}>
          <Group justify="space-between" wrap="nowrap" gap="sm" align="flex-start">
            <div style={{ minWidth: 0 }}>
              <Text size="xs" c="dimmed" tt="uppercase" fw={700} truncate>{card.title}</Text>
              <Text fw={800} mt={6} lh={1.1} truncate style={{ fontSize: 'clamp(1.2rem, 2.2vw, 1.55rem)' }}>
                {card.value}
              </Text>
            </div>
            <ThemeIcon variant="light" color={card.color} size={44} radius="md" style={{ flexShrink: 0 }}>
              <card.icon size={23} />
            </ThemeIcon>
          </Group>
        </Card>
      ))}
    </SimpleGrid>
  );
}
