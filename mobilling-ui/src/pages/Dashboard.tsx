import { Title, Stack, SimpleGrid, LoadingOverlay, Group, Loader } from '@mantine/core';
import { MonthPickerInput } from '@mantine/dates';
import { useState } from 'react';
import { useQuery, keepPreviousData } from '@tanstack/react-query';
import { getDashboardSummary } from '../api/dashboard';
import { usePermissions } from '../hooks/usePermissions';
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
import ActivityCalendar from '../components/Dashboard/ActivityCalendar';

export default function Dashboard() {
  const { can } = usePermissions();
  const [selectedMonth, setSelectedMonth] = useState<Date>(new Date());

  const safeDate = selectedMonth instanceof Date && !isNaN(selectedMonth.getTime()) ? selectedMonth : new Date();
  const month = safeDate.getMonth() + 1;
  const year = safeDate.getFullYear();
  const periodLabel = safeDate.toLocaleString('default', { month: 'short', year: 'numeric' });

  const { data, isFetching } = useQuery({
    queryKey: ['dashboard', month, year],
    queryFn: () => getDashboardSummary(month, year),
    placeholderData: keepPreviousData,
  });

  const summary = data?.data;

  return (
    <Stack pos="relative">
      <LoadingOverlay visible={isFetching && !summary} />
      <Group justify="space-between" align="center">
        <Group gap="sm">
          <Title order={2}>Dashboard</Title>
          {isFetching && !!summary && <Loader size="xs" />}
        </Group>
        <MonthPickerInput
          value={selectedMonth}
          onChange={(val) => {
            if (!val) return;
            const d = val instanceof Date ? val : new Date(val as string);
            if (!isNaN(d.getTime())) setSelectedMonth(d);
          }}
          maxDate={new Date()}
          maxLevel="decade"
          w={160}
          size="sm"
        />
      </Group>

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
            periodLabel={periodLabel}
          />

          {(can('dashboard.revenue_chart') || can('dashboard.activity_calendar')) && (
            <SimpleGrid cols={{ base: 1, md: 2 }}>
              {can('dashboard.revenue_chart') && <RevenueChart data={summary.monthly_revenue} />}
              {can('dashboard.activity_calendar') && <ActivityCalendar data={summary.calendar} />}
            </SimpleGrid>
          )}

          {(can('dashboard.invoice_status_chart') || can('dashboard.payment_method_chart')) && (
            <SimpleGrid cols={{ base: 1, md: 2 }}>
              {can('dashboard.invoice_status_chart') && <InvoiceStatusChart data={summary.invoice_status_breakdown} />}
              {can('dashboard.payment_method_chart') && <PaymentMethodChart data={summary.payment_method_breakdown} />}
            </SimpleGrid>
          )}

          {(can('dashboard.top_clients') || can('dashboard.subscription_stats')) && (
            <SimpleGrid cols={{ base: 1, md: 2 }}>
              {can('dashboard.top_clients') && <TopClientsChart data={summary.top_clients} />}
              {can('dashboard.subscription_stats') && <SubscriptionStats data={summary.subscription_stats} />}
            </SimpleGrid>
          )}

          {(can('dashboard.recent_invoices') || can('dashboard.upcoming_bills')) && (
            <SimpleGrid cols={{ base: 1, md: 2 }}>
              {can('dashboard.recent_invoices') && <RecentInvoices invoices={summary.recent_invoices} />}
              {can('dashboard.upcoming_bills') && <UpcomingBills bills={summary.upcoming_bills} />}
            </SimpleGrid>
          )}

          {(can('dashboard.urgent_obligations') || can('dashboard.upcoming_renewals')) && (
            <SimpleGrid cols={{ base: 1, md: 2 }}>
              {can('dashboard.urgent_obligations') && <UrgentObligations obligations={summary.urgent_obligations || []} />}
              {can('dashboard.upcoming_renewals') && <UpcomingRenewals data={summary.upcoming_renewals} />}
            </SimpleGrid>
          )}
        </>
      )}
    </Stack>
  );
}
