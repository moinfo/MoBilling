import { Title, Stack, SimpleGrid, LoadingOverlay } from '@mantine/core';
import { useQuery } from '@tanstack/react-query';
import { getDashboardSummary } from '../api/dashboard';
import StatsCards from '../components/Dashboard/StatsCards';
import RevenueChart from '../components/Dashboard/RevenueChart';
import InvoiceStatusChart from '../components/Dashboard/InvoiceStatusChart';
import PaymentMethodChart from '../components/Dashboard/PaymentMethodChart';
import TopClientsChart from '../components/Dashboard/TopClientsChart';
import SubscriptionStats from '../components/Dashboard/SubscriptionStats';
import RecentInvoices from '../components/Dashboard/RecentInvoices';
import UpcomingBills from '../components/Dashboard/UpcomingBills';
import UrgentObligations from '../components/Dashboard/UrgentObligations';
import UpcomingRenewals from '../components/Dashboard/UpcomingRenewals';

export default function Dashboard() {
  const { data, isLoading } = useQuery({
    queryKey: ['dashboard'],
    queryFn: getDashboardSummary,
  });

  const summary = data?.data;

  if (isLoading) return <LoadingOverlay visible />;

  return (
    <Stack>
      <Title order={2}>Dashboard</Title>

      {summary && (
        <>
          <StatsCards
            totalExpenses={summary.total_expenses}
            totalReceivable={summary.total_receivable}
            totalReceived={summary.total_received}
            outstanding={summary.outstanding}
            overdueInvoices={summary.overdue_invoices}
            overdueBills={summary.overdue_bills}
            statutoryOverdue={summary.statutory_stats?.overdue}
            statutoryDueSoon={summary.statutory_stats?.due_soon}
            totalClients={summary.total_clients}
            totalDocuments={summary.total_documents}
            smsBalance={summary.sms_balance}
            smsEnabled={summary.sms_enabled}
          />

          <RevenueChart data={summary.monthly_revenue} />

          <SimpleGrid cols={{ base: 1, md: 2 }}>
            <InvoiceStatusChart data={summary.invoice_status_breakdown} />
            <PaymentMethodChart data={summary.payment_method_breakdown} />
          </SimpleGrid>

          <SimpleGrid cols={{ base: 1, md: 2 }}>
            <TopClientsChart data={summary.top_clients} />
            <SubscriptionStats data={summary.subscription_stats} />
          </SimpleGrid>

          <SimpleGrid cols={{ base: 1, md: 2 }}>
            <RecentInvoices invoices={summary.recent_invoices} />
            <UpcomingBills bills={summary.upcoming_bills} />
          </SimpleGrid>

          <SimpleGrid cols={{ base: 1, md: 2 }}>
            <UrgentObligations obligations={summary.urgent_obligations || []} />
            <UpcomingRenewals data={summary.upcoming_renewals} />
          </SimpleGrid>
        </>
      )}
    </Stack>
  );
}
