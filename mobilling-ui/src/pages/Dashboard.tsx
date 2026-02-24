import { Title, Stack, SimpleGrid, LoadingOverlay } from '@mantine/core';
import { useQuery } from '@tanstack/react-query';
import { getDashboardSummary } from '../api/dashboard';
import StatsCards from '../components/Dashboard/StatsCards';
import RecentInvoices from '../components/Dashboard/RecentInvoices';
import UpcomingBills from '../components/Dashboard/UpcomingBills';

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
            totalReceivable={summary.total_receivable}
            totalReceived={summary.total_received}
            outstanding={summary.outstanding}
            overdueInvoices={summary.overdue_invoices}
            overdueBills={summary.overdue_bills}
            totalClients={summary.total_clients}
            totalDocuments={summary.total_documents}
            smsBalance={summary.sms_balance}
            smsEnabled={summary.sms_enabled}
          />

          <SimpleGrid cols={{ base: 1, md: 2 }}>
            <RecentInvoices invoices={summary.recent_invoices} />
            <UpcomingBills bills={summary.upcoming_bills} />
          </SimpleGrid>
        </>
      )}
    </Stack>
  );
}
