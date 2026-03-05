import { Stack, SimpleGrid, Paper, Text, Table, Badge, LoadingOverlay, Accordion, Group, Select, ThemeIcon } from '@mantine/core';
import { useQuery } from '@tanstack/react-query';
import { PieChart, Pie, Cell, Tooltip, Legend, ResponsiveContainer, BarChart, Bar, XAxis, YAxis, CartesianGrid } from 'recharts';
import { IconLink, IconCash, IconCalendarRepeat, IconChartPie, IconPlayerPause, IconCalendar } from '@tabler/icons-react';
import { getSubscriptionReport, ProductBreakdown, SubscriptionReport } from '../../api/reports';
import ReportHeader from '../../components/Reports/ReportHeader';
import StatCard from '../../components/Reports/StatCard';
import { formatCurrency } from '../../utils/formatCurrency';
import { useMemo, useState } from 'react';
import dayjs from 'dayjs';

const fmt = (n: number) => n.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const COLORS = ['#40c057', '#fd7e14', '#fab005', '#fa5252'];

const STATUS_COLOR: Record<string, string> = {
  active: 'green',
  suspended: 'orange',
  pending: 'yellow',
  cancelled: 'red',
};

function cycleBadge(cycle: string) {
  const labels: Record<string, string> = {
    weekly: 'Weekly',
    monthly: 'Monthly',
    quarterly: 'Quarterly',
    semi_annual: 'Semi-Annual',
    annual: 'Annual',
    yearly: 'Yearly',
  };
  return labels[cycle] || cycle;
}

function buildExportData(byProduct: ProductBreakdown[]) {
  return byProduct.flatMap((p) =>
    p.clients.map((c) => ({
      product: p.product_name,
      billing_cycle: p.billing_cycle,
      unit_price: p.unit_price,
      client: c.client_name,
      label: c.label ?? '',
      quantity: c.quantity,
      status: c.status,
      start_date: c.start_date ?? '',
      line_total: c.line_total,
    })),
  );
}

/** Apply client-side filters to the by_product data and recompute summary stats */
function applyFilters(
  report: SubscriptionReport,
  productFilter: string | null,
  clientFilter: string | null,
  dateRange: [Date | null, Date | null],
) {
  const [startDate, endDate] = dateRange;

  // Filter by_product → filter clients inside each product → drop empty products
  let filtered = report.by_product.map((p) => {
    let clients = p.clients;

    if (clientFilter) {
      clients = clients.filter((c) => c.client_name === clientFilter);
    }
    if (startDate) {
      const s = dayjs(startDate).format('YYYY-MM-DD');
      clients = clients.filter((c) => c.start_date && c.start_date >= s);
    }
    if (endDate) {
      const e = dayjs(endDate).format('YYYY-MM-DD');
      clients = clients.filter((c) => c.start_date && c.start_date <= e);
    }

    return { ...p, clients };
  });

  if (productFilter) {
    filtered = filtered.filter((p) => p.product_name === productFilter);
  }

  // Drop products with no matching clients
  filtered = filtered.filter((p) => p.clients.length > 0);

  // Recompute counts from filtered clients
  const allClients = filtered.flatMap((p) => p.clients);
  const byStatus = {
    active: allClients.filter((c) => c.status === 'active').length,
    suspended: allClients.filter((c) => c.status === 'suspended').length,
    pending: allClients.filter((c) => c.status === 'pending').length,
    cancelled: allClients.filter((c) => c.status === 'cancelled').length,
  };
  const totalSubs = allClients.length;
  const activeRevenue = allClients.filter((c) => c.status === 'active').reduce((s, c) => s + c.line_total, 0);

  // Recompute per-product aggregates
  const byProduct: ProductBreakdown[] = filtered.map((p) => ({
    ...p,
    total_subscriptions: p.clients.length,
    active_count: p.clients.filter((c) => c.status === 'active').length,
    suspended_count: p.clients.filter((c) => c.status === 'suspended').length,
    pending_count: p.clients.filter((c) => c.status === 'pending').length,
    total_revenue: p.clients.reduce((s, c) => s + c.line_total, 0),
  }));

  return { byStatus, totalSubs, activeRevenue, byProduct };
}

export default function SubscriptionReportPage() {
  const [range, setRange] = useState<[Date | null, Date | null]>([null, null]);
  const [productFilter, setProductFilter] = useState<string | null>(null);
  const [clientFilter, setClientFilter] = useState<string | null>(null);

  const { data, isLoading } = useQuery({
    queryKey: ['report-subscriptions'],
    queryFn: getSubscriptionReport,
  });

  const r = data?.data;

  // Build filter options from loaded data
  const productOptions = useMemo(() => {
    if (!r?.by_product) return [];
    return r.by_product.map((p) => ({ value: p.product_name, label: p.product_name }));
  }, [r]);

  const clientOptions = useMemo(() => {
    if (!r?.by_product) return [];
    const names = new Set<string>();
    r.by_product.forEach((p) => p.clients.forEach((c) => names.add(c.client_name)));
    return [...names].sort().map((n) => ({ value: n, label: n }));
  }, [r]);

  const hasFilters = !!productFilter || !!clientFilter || !!range[0] || !!range[1];

  // Apply filters
  const view = useMemo(() => {
    if (!r) return null;
    if (!hasFilters) return null; // use raw data
    return applyFilters(r, productFilter, clientFilter, range);
  }, [r, productFilter, clientFilter, range, hasFilters]);

  // Choose between raw and filtered values
  const byStatus = view ? view.byStatus : r?.by_status;
  const totalSubs = view ? view.totalSubs : r?.total_subscriptions;
  const activeRevenue = view ? view.activeRevenue : r?.active_monthly_revenue;
  const byProduct = view ? view.byProduct : r?.by_product;

  const pieData = byStatus
    ? [
        { name: 'Active', value: byStatus.active },
        { name: 'Suspended', value: byStatus.suspended },
        { name: 'Pending', value: byStatus.pending },
        { name: 'Cancelled', value: byStatus.cancelled },
      ]
    : [];

  const exportRows = byProduct ? buildExportData(byProduct) : undefined;

  return (
    <Stack gap="lg" pos="relative">
      <LoadingOverlay visible={isLoading} />
      <ReportHeader
        title="Subscription Report"
        dateRange={range}
        onDateChange={setRange}
        exportData={exportRows as Record<string, unknown>[] | undefined}
        exportFilename="subscriptions"
        extra={
          <Group gap="sm">
            <Select
              placeholder="All products"
              data={productOptions}
              value={productFilter}
              onChange={setProductFilter}
              searchable
              clearable
              size="sm"
              style={{ minWidth: 180 }}
            />
            <Select
              placeholder="All clients"
              data={clientOptions}
              value={clientFilter}
              onChange={setClientFilter}
              searchable
              clearable
              size="sm"
              style={{ minWidth: 180 }}
            />
          </Group>
        }
      />

      {r && (
        <>
          <SimpleGrid cols={{ base: 1, xs: 2, md: 5 }}>
            <StatCard label="Total Subscriptions" value={totalSubs ?? 0} icon={<IconLink size={24} />} color="blue" />
            <StatCard label="Active" value={byStatus?.active ?? 0} icon={<IconChartPie size={24} />} color="green" />
            <StatCard label="Suspended" value={byStatus?.suspended ?? 0} icon={<IconPlayerPause size={24} />} color="orange" />
            <StatCard label="Monthly Revenue" value={fmt(activeRevenue ?? 0)} icon={<IconCash size={24} />} color="teal" />
            <StatCard label="Monthly Forecast" value={fmt(r.monthly_forecast)} icon={<IconCalendarRepeat size={24} />} color="cyan" />
          </SimpleGrid>

          <SimpleGrid cols={{ base: 1, md: 2 }}>
            <Paper withBorder p="md">
              <Text fw={600} mb="md">Status Distribution</Text>
              <ResponsiveContainer width="100%" height={300}>
                <PieChart>
                  <Pie data={pieData} dataKey="value" nameKey="name" cx="50%" cy="50%" outerRadius={100} label>
                    {pieData.map((_, i) => (
                      <Cell key={i} fill={COLORS[i]} />
                    ))}
                  </Pie>
                  <Tooltip />
                  <Legend />
                </PieChart>
              </ResponsiveContainer>
            </Paper>

            <Paper withBorder p="md">
              <Group justify="space-between" mb="md">
                <Text fw={600}>Upcoming Renewals</Text>
                {r.upcoming_renewals.length > 0 && (
                  <Badge variant="light" size="sm">{r.upcoming_renewals.length} total</Badge>
                )}
              </Group>
              <div style={{ maxHeight: 280, overflowY: 'auto' }}>
                <Table striped highlightOnHover>
                  <Table.Thead style={{ position: 'sticky', top: 0, background: 'var(--mantine-color-body)', zIndex: 1 }}>
                    <Table.Tr>
                      <Table.Th>Client</Table.Th>
                      <Table.Th>Product</Table.Th>
                      <Table.Th ta="right">Price</Table.Th>
                      <Table.Th>In</Table.Th>
                    </Table.Tr>
                  </Table.Thead>
                  <Table.Tbody>
                    {r.upcoming_renewals.map((s, i) => (
                      <Table.Tr key={i}>
                        <Table.Td>
                          <Text size="sm" truncate maw={120}>{s.client_name}</Text>
                        </Table.Td>
                        <Table.Td>
                          <Text size="sm" truncate maw={100}>{s.product_name}</Text>
                        </Table.Td>
                        <Table.Td ta="right">{fmt(s.price)}</Table.Td>
                        <Table.Td>
                          <Badge color={s.days_until <= 3 ? 'red' : s.days_until <= 7 ? 'orange' : 'blue'} variant="light" size="sm">
                            {s.days_until}d
                          </Badge>
                        </Table.Td>
                      </Table.Tr>
                    ))}
                  </Table.Tbody>
                </Table>
              </div>
            </Paper>
          </SimpleGrid>

          {/* Revenue by Product */}
          {byProduct && byProduct.length > 0 && (
            <Paper withBorder p="md">
              <Text fw={600} mb="md">Revenue by Product</Text>
              <Accordion variant="separated">
                {[...byProduct]
                  .sort((a, b) => b.total_revenue - a.total_revenue)
                  .map((p, idx) => (
                    <Accordion.Item key={idx} value={p.product_name + idx}>
                      <Accordion.Control>
                        <Group justify="space-between" wrap="nowrap" pr="md">
                          <Group gap="sm">
                            <Text fw={500}>{p.product_name}</Text>
                            <Badge variant="light" size="sm">{cycleBadge(p.billing_cycle)}</Badge>
                          </Group>
                          <Group gap="lg">
                            <Text size="sm" c="dimmed">{p.total_subscriptions} sub{p.total_subscriptions !== 1 ? 's' : ''}</Text>
                            <Text size="sm" c="dimmed">
                              <Text span c="green">{p.active_count}</Text>
                              {p.suspended_count > 0 && <Text span c="orange"> / {p.suspended_count} susp</Text>}
                            </Text>
                            <Text fw={600}>{formatCurrency(p.total_revenue)}</Text>
                          </Group>
                        </Group>
                      </Accordion.Control>
                      <Accordion.Panel>
                        <Table.ScrollContainer minWidth={500}>
                          <Table striped highlightOnHover>
                            <Table.Thead>
                              <Table.Tr>
                                <Table.Th>Client</Table.Th>
                                <Table.Th>Label</Table.Th>
                                <Table.Th ta="center">Qty</Table.Th>
                                <Table.Th>Status</Table.Th>
                                <Table.Th>Start Date</Table.Th>
                                <Table.Th ta="right">Amount</Table.Th>
                              </Table.Tr>
                            </Table.Thead>
                            <Table.Tbody>
                              {p.clients.map((c, ci) => (
                                <Table.Tr key={ci}>
                                  <Table.Td>{c.client_name}</Table.Td>
                                  <Table.Td>{c.label || '-'}</Table.Td>
                                  <Table.Td ta="center">{c.quantity}</Table.Td>
                                  <Table.Td>
                                    <Badge color={STATUS_COLOR[c.status] || 'gray'} variant="light" size="sm">
                                      {c.status}
                                    </Badge>
                                  </Table.Td>
                                  <Table.Td>{c.start_date || '-'}</Table.Td>
                                  <Table.Td ta="right">{fmt(c.line_total)}</Table.Td>
                                </Table.Tr>
                              ))}
                            </Table.Tbody>
                          </Table>
                        </Table.ScrollContainer>
                      </Accordion.Panel>
                    </Accordion.Item>
                  ))}
              </Accordion>
            </Paper>
          )}

          {/* Yearly Collection Forecast */}
          {r.yearly_forecast && r.yearly_forecast.length > 0 && (
            <Paper withBorder p="md" radius="md">
              <Group justify="space-between" mb="md">
                <Group gap="sm">
                  <ThemeIcon variant="light" color="blue" size="lg" radius="md">
                    <IconCalendar size={20} />
                  </ThemeIcon>
                  <div>
                    <Text fw={600}>Yearly Collection Forecast ({new Date().getFullYear()})</Text>
                    <Text size="xs" c="dimmed">Expected collections per month based on active subscriptions</Text>
                  </div>
                </Group>
                <div style={{ textAlign: 'right' }}>
                  <Text size="xs" c="dimmed" tt="uppercase" fw={600}>Total Year</Text>
                  <Text fw={700} size="xl" c="blue">{formatCurrency(r.yearly_total)}</Text>
                </div>
              </Group>

              <ResponsiveContainer width="100%" height={300}>
                <BarChart data={r.yearly_forecast}>
                  <CartesianGrid strokeDasharray="3 3" />
                  <XAxis dataKey="month" tick={{ fontSize: 12 }} />
                  <YAxis tick={{ fontSize: 11 }} tickFormatter={(v) => (v >= 1000000 ? `${(v / 1000000).toFixed(1)}M` : v >= 1000 ? `${(v / 1000).toFixed(0)}K` : v)} />
                  <Tooltip formatter={(value) => [fmt(Number(value)), 'Expected']} />
                  <Bar
                    dataKey="amount"
                    fill="#228be6"
                    radius={[4, 4, 0, 0]}
                    label={{ position: 'top', fontSize: 10, formatter: (v) => { const n = Number(v); return n > 0 ? (n >= 1000000 ? `${(n / 1000000).toFixed(1)}M` : `${(n / 1000).toFixed(0)}K`) : ''; } }}
                  />
                </BarChart>
              </ResponsiveContainer>

              <Table striped highlightOnHover mt="md">
                <Table.Thead>
                  <Table.Tr>
                    {r.yearly_forecast.map((m) => (
                      <Table.Th key={m.month_num} ta="center" style={{ fontSize: 12 }}>
                        {m.month}
                      </Table.Th>
                    ))}
                    <Table.Th ta="center" fw={700} style={{ fontSize: 12 }}>Total</Table.Th>
                  </Table.Tr>
                </Table.Thead>
                <Table.Tbody>
                  <Table.Tr>
                    {r.yearly_forecast.map((m) => (
                      <Table.Td key={m.month_num} ta="right" style={{ fontSize: 12 }}>
                        {fmt(m.amount)}
                      </Table.Td>
                    ))}
                    <Table.Td ta="right" fw={700} style={{ fontSize: 12 }}>
                      {fmt(r.yearly_total)}
                    </Table.Td>
                  </Table.Tr>
                </Table.Tbody>
              </Table>
            </Paper>
          )}
        </>
      )}
    </Stack>
  );
}
