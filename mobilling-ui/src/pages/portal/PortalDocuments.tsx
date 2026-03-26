import { useState, useEffect, useMemo } from 'react';
import {
  Stack, Paper, Title, Table, Badge, TextInput, Group, Pagination, LoadingOverlay,
  Drawer, Text, Button, Alert, SegmentedControl, SimpleGrid, Divider, Tooltip,
} from '@mantine/core';
import { notifications } from '@mantine/notifications';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useSearchParams } from 'react-router-dom';
import {
  IconSearch, IconCreditCard, IconCheck, IconMail, IconArrowUp, IconArrowDown,
  IconArrowsSort, IconAlertTriangle, IconCash, IconFileInvoice,
} from '@tabler/icons-react';
import { getPortalDocuments, getPortalDocument, resendPortalDocument } from '../../api/portal';
import { portalCheckoutInvoice, getPaymentStatusByTracking } from '../../api/payment';

const fmt = (n: number) => n.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const fmtDate = (d: string | null) => d ? new Date(d).toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric' }) : '-';

const statusColor: Record<string, string> = {
  sent: 'blue', viewed: 'cyan', partial: 'orange', paid: 'green', overdue: 'red',
};

const statusLabels: Record<string, string> = {
  sent: 'Sent', viewed: 'Viewed', partial: 'Partial', paid: 'Paid', overdue: 'Overdue',
};

export default function PortalDocuments({ type = 'invoice' }: { type?: string }) {
  const [page, setPage] = useState(1);
  const [search, setSearch] = useState('');
  const [viewId, setViewId] = useState<string | null>(null);
  const [paying, setPaying] = useState(false);
  const [sending, setSending] = useState(false);
  const [paymentDone, setPaymentDone] = useState(false);
  const [searchParams, setSearchParams] = useSearchParams();
  const queryClient = useQueryClient();

  const title = type === 'invoice' ? 'Invoices' : 'Quotations';
  const isInvoice = type === 'invoice';

  // Handle Pesapal callback
  const trackingId = searchParams.get('OrderTrackingId');
  useEffect(() => {
    if (!trackingId) return;
    const interval = setInterval(() => {
      getPaymentStatusByTracking(trackingId).then((res) => {
        if (res.data.status === 'completed') {
          setPaymentDone(true);
          clearInterval(interval);
          queryClient.invalidateQueries({ queryKey: ['portal-documents'] });
          setSearchParams({});
        } else if (res.data.status === 'failed') {
          clearInterval(interval);
          setSearchParams({});
          notifications.show({ title: 'Payment failed', message: 'Please try again.', color: 'red' });
        }
      });
    }, 3000);
    return () => clearInterval(interval);
  }, [trackingId]);

  const handlePay = async (docId: string) => {
    setPaying(true);
    try {
      const res = await portalCheckoutInvoice(docId);
      if (res.data.redirect_url) {
        window.location.href = res.data.redirect_url;
      }
    } catch (err: any) {
      notifications.show({
        title: 'Error',
        message: err.response?.data?.message || 'Payment initiation failed.',
        color: 'red',
      });
    } finally {
      setPaying(false);
    }
  };

  const { data, isLoading } = useQuery({
    queryKey: ['portal-documents', type, page, search],
    queryFn: () => getPortalDocuments({ type, page, search: search || undefined, per_page: 100 }),
  });

  const { data: docDetail } = useQuery({
    queryKey: ['portal-document', viewId],
    queryFn: () => getPortalDocument(viewId!),
    enabled: !!viewId,
  });

  const docs: any[] = data?.data?.data || [];
  const lastPage = data?.data?.last_page || 1;
  const detail = docDetail?.data?.data;

  const [sortBy, setSortBy] = useState<string>('date');
  const [sortDir, setSortDir] = useState<'asc' | 'desc'>('desc');
  const [statusFilter, setStatusFilter] = useState('all');

  const toggleSort = (col: string) => {
    if (sortBy === col) {
      setSortDir((d) => (d === 'asc' ? 'desc' : 'asc'));
    } else {
      setSortBy(col);
      setSortDir('asc');
    }
  };

  const filtered = useMemo(() => {
    let list = docs;
    if (statusFilter !== 'all') {
      if (statusFilter === 'unpaid') list = list.filter((d) => ['sent', 'overdue', 'partial'].includes(d.status));
      else if (statusFilter === 'paid') list = list.filter((d) => d.status === 'paid');
      else if (statusFilter === 'overdue') list = list.filter((d) => d.status === 'overdue');
    }
    return [...list].sort((a, b) => {
      let cmp = 0;
      switch (sortBy) {
        case 'date': cmp = (a.date || '').localeCompare(b.date || ''); break;
        case 'due_date': cmp = (a.due_date || '').localeCompare(b.due_date || ''); break;
        case 'total': cmp = (parseFloat(a.total) || 0) - (parseFloat(b.total) || 0); break;
        case 'balance_due': cmp = (parseFloat(a.balance_due) || 0) - (parseFloat(b.balance_due) || 0); break;
        case 'status': cmp = (a.status || '').localeCompare(b.status || ''); break;
        default: cmp = 0;
      }
      return sortDir === 'asc' ? cmp : -cmp;
    });
  }, [docs, statusFilter, sortBy, sortDir]);

  const totals = useMemo(() => ({
    originalAmount: filtered.reduce((s: number, d: any) => s + (parseFloat(d.original_amount ?? d.total) || 0), 0),
    lateFee: filtered.reduce((s: number, d: any) => s + (parseFloat(d.late_fee) || 0), 0),
    total: filtered.reduce((s: number, d: any) => s + (parseFloat(d.total) || 0), 0),
    paid: filtered.reduce((s: number, d: any) => s + (parseFloat(d.paid_amount) || 0), 0),
    balance: filtered.reduce((s: number, d: any) => s + (parseFloat(d.balance_due) || 0), 0),
  }), [filtered]);

  // Summary stats from all docs (not just filtered)
  const summary = useMemo(() => {
    const unpaid = docs.filter((d) => ['sent', 'overdue', 'partial'].includes(d.status));
    return {
      totalBalance: unpaid.reduce((s: number, d: any) => s + (parseFloat(d.balance_due) || 0), 0),
      overdueCount: docs.filter((d) => d.status === 'overdue').length,
      unpaidCount: unpaid.length,
      paidCount: docs.filter((d) => d.status === 'paid').length,
    };
  }, [docs]);

  const SortHeader = ({ col, label, align }: { col: string; label: string; align?: 'right' }) => (
    <Table.Th style={{ cursor: 'pointer', userSelect: 'none', textAlign: align }} onClick={() => toggleSort(col)}>
      <Group gap={4} wrap="nowrap" justify={align === 'right' ? 'flex-end' : undefined}>
        {label}
        {sortBy !== col
          ? <IconArrowsSort size={14} style={{ opacity: 0.4 }} />
          : sortDir === 'asc' ? <IconArrowUp size={14} /> : <IconArrowDown size={14} />
        }
      </Group>
    </Table.Th>
  );

  const isDueDatePast = (d: string | null) => d && new Date(d) < new Date();

  return (
    <Stack gap="lg" pos="relative">
      <LoadingOverlay visible={isLoading} />
      {paymentDone && (
        <Alert color="green" icon={<IconCheck size={20} />} title="Payment Successful" withCloseButton onClose={() => setPaymentDone(false)}>
          Your payment has been received. Thank you!
        </Alert>
      )}
      {trackingId && !paymentDone && (
        <Alert color="blue" title="Processing Payment">
          Verifying your payment, please wait...
        </Alert>
      )}

      <Title order={3}>{title}</Title>

      {/* Summary Cards */}
      {isInvoice && docs.length > 0 && (
        <SimpleGrid cols={{ base: 2, sm: 4 }}>
          <StatCard label="Total Invoices" value={String(docs.length)} icon={<IconFileInvoice size={22} />} color="blue" />
          <StatCard label="Outstanding Balance" value={fmt(summary.totalBalance)} icon={<IconAlertTriangle size={22} />} color={summary.totalBalance > 0 ? 'orange' : 'green'} />
          <StatCard label="Overdue" value={String(summary.overdueCount)} icon={<IconAlertTriangle size={22} />} color={summary.overdueCount > 0 ? 'red' : 'green'} />
          <StatCard label="Paid" value={String(summary.paidCount)} icon={<IconCash size={22} />} color="green" />
        </SimpleGrid>
      )}

      <Group justify="space-between" wrap="wrap">
        <Group gap="sm" wrap="wrap">
          {isInvoice && docs.length > 0 && (
            <SegmentedControl
              size="xs"
              value={statusFilter}
              onChange={setStatusFilter}
              data={[
                { label: 'All', value: 'all' },
                { label: `Unpaid (${summary.unpaidCount})`, value: 'unpaid' },
                { label: 'Paid', value: 'paid' },
                { label: 'Overdue', value: 'overdue' },
              ]}
            />
          )}
        </Group>
        <TextInput
          placeholder="Search by number..."
          leftSection={<IconSearch size={16} />}
          value={search}
          onChange={(e) => { setSearch(e.currentTarget.value); setPage(1); }}
          w={250}
        />
      </Group>

      <Paper withBorder p="md">
        <Table.ScrollContainer minWidth={800}>
          <Table striped highlightOnHover>
            <Table.Thead>
              <Table.Tr>
                <Table.Th w={40}>#</Table.Th>
                <Table.Th>Invoice</Table.Th>
                <Table.Th>Description</Table.Th>
                <SortHeader col="date" label="Date" />
                <SortHeader col="due_date" label="Due Date" />
                {isInvoice ? (
                  <>
                    <SortHeader col="total" label="Amount" align="right" />
                    <Table.Th ta="right">Late Fee</Table.Th>
                    <Table.Th ta="right">Total</Table.Th>
                    <Table.Th ta="right">Paid</Table.Th>
                    <SortHeader col="balance_due" label="Balance" align="right" />
                  </>
                ) : (
                  <Table.Th ta="right">Total</Table.Th>
                )}
                <SortHeader col="status" label="Status" />
                {isInvoice && <Table.Th w={60}></Table.Th>}
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {filtered.map((doc: any, index: number) => {
                const desc = doc.items?.[0]?.description || doc.notes || '-';
                const hasBalance = (doc.balance_due || 0) > 0;
                return (
                  <Table.Tr key={doc.id} onClick={() => setViewId(doc.id)} style={{ cursor: 'pointer' }}>
                    <Table.Td><Text size="sm" c="dimmed">{index + 1}</Text></Table.Td>
                    <Table.Td fw={600}>{doc.document_number}</Table.Td>
                    <Table.Td c="dimmed" maw={180} style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                      {desc}
                    </Table.Td>
                    <Table.Td>{fmtDate(doc.date)}</Table.Td>
                    <Table.Td>
                      {doc.due_date ? (() => {
                        const daysLeft = Math.ceil((new Date(doc.due_date).getTime() - Date.now()) / 86400000);
                        return (
                          <>
                            <Text size="sm" c={daysLeft < 0 && hasBalance ? 'red' : undefined} fw={daysLeft < 0 && hasBalance ? 600 : undefined}>
                              {fmtDate(doc.due_date)}
                            </Text>
                            {hasBalance && (
                              <Badge
                                variant="light"
                                size="xs"
                                color={daysLeft < 0 ? 'red' : daysLeft <= 3 ? 'orange' : daysLeft <= 7 ? 'yellow' : 'blue'}
                              >
                                {daysLeft < 0 ? `${Math.abs(daysLeft)}d overdue` : daysLeft === 0 ? 'Due today' : `${daysLeft}d left`}
                              </Badge>
                            )}
                          </>
                        );
                      })() : '-'}
                    </Table.Td>
                    {isInvoice ? (
                      <>
                        <Table.Td ta="right">{fmt(parseFloat(doc.original_amount ?? doc.total) || 0)}</Table.Td>
                        <Table.Td ta="right">
                          {(parseFloat(doc.late_fee) || 0) > 0
                            ? <Text size="sm" c="red" fw={500}>{fmt(parseFloat(doc.late_fee))}</Text>
                            : <Text size="sm" c="dimmed">—</Text>
                          }
                        </Table.Td>
                        <Table.Td ta="right" fw={500}>{fmt(parseFloat(doc.total) || 0)}</Table.Td>
                        <Table.Td ta="right">
                          <Text size="sm" c="green">{(parseFloat(doc.paid_amount) || 0) > 0 ? fmt(parseFloat(doc.paid_amount)) : '—'}</Text>
                        </Table.Td>
                        <Table.Td ta="right">
                          <Text size="sm" fw={600} c={hasBalance ? 'red' : 'green'}>
                            {fmt(parseFloat(doc.balance_due) || 0)}
                          </Text>
                        </Table.Td>
                      </>
                    ) : (
                      <Table.Td ta="right">{fmt(doc.total)}</Table.Td>
                    )}
                    <Table.Td>
                      <Badge color={statusColor[doc.status] || 'gray'} variant="light" size="sm">
                        {statusLabels[doc.status] || doc.status}
                      </Badge>
                    </Table.Td>
                    {isInvoice && (
                      <Table.Td>
                        {hasBalance && (
                          <Tooltip label={`Pay ${fmt(doc.balance_due)}`}>
                            <Button
                              variant="light"
                              color="green"
                              size="compact-xs"
                              leftSection={<IconCreditCard size={14} />}
                              onClick={(e) => { e.stopPropagation(); handlePay(doc.id); }}
                              loading={paying}
                            >
                              Pay
                            </Button>
                          </Tooltip>
                        )}
                      </Table.Td>
                    )}
                  </Table.Tr>
                );
              })}
              {filtered.length === 0 && (
                <Table.Tr>
                  <Table.Td colSpan={isInvoice ? 12 : 7} ta="center" c="dimmed">No {title.toLowerCase()} found</Table.Td>
                </Table.Tr>
              )}
            </Table.Tbody>
            {isInvoice && filtered.length > 0 && (
              <Table.Tfoot>
                <Table.Tr style={{ fontWeight: 700, borderTop: '2px solid var(--mantine-color-dark-4)' }}>
                  <Table.Td colSpan={5} ta="right">
                    <Text fw={700} size="sm">Totals ({filtered.length} invoices)</Text>
                  </Table.Td>
                  <Table.Td ta="right"><Text fw={700} size="sm">{fmt(totals.originalAmount)}</Text></Table.Td>
                  <Table.Td ta="right">
                    <Text fw={700} size="sm" c={totals.lateFee > 0 ? 'red' : undefined}>
                      {totals.lateFee > 0 ? fmt(totals.lateFee) : '—'}
                    </Text>
                  </Table.Td>
                  <Table.Td ta="right"><Text fw={700} size="sm">{fmt(totals.total)}</Text></Table.Td>
                  <Table.Td ta="right"><Text fw={700} size="sm" c="green">{fmt(totals.paid)}</Text></Table.Td>
                  <Table.Td ta="right">
                    <Text fw={700} size="sm" c={totals.balance > 0 ? 'red' : 'green'}>{fmt(totals.balance)}</Text>
                  </Table.Td>
                  <Table.Td />
                  <Table.Td />
                </Table.Tr>
              </Table.Tfoot>
            )}
          </Table>
        </Table.ScrollContainer>
        {lastPage > 1 && (
          <Group justify="center" mt="md">
            <Pagination value={page} onChange={setPage} total={lastPage} />
          </Group>
        )}
      </Paper>

      {/* Invoice Detail Drawer */}
      <Drawer opened={!!viewId} onClose={() => setViewId(null)} title="Invoice Details" size="lg" position="right">
        {detail && (
          <Stack gap="md">
            {/* Header */}
            <Group justify="space-between">
              <div>
                <Text fw={700} size="lg">{detail.document_number}</Text>
                <Text size="sm" c="dimmed">
                  {fmtDate(detail.date)}
                  {detail.due_date && ` — Due: ${fmtDate(detail.due_date)}`}
                </Text>
              </div>
              <Badge color={statusColor[detail.status] || 'gray'} variant="light" size="lg">
                {statusLabels[detail.status] || detail.status}
              </Badge>
            </Group>

            {/* Overdue warning */}
            {detail.status === 'overdue' && (
              <Alert color="red" variant="light" icon={<IconAlertTriangle size={18} />}>
                This invoice is overdue. Please make payment as soon as possible to avoid service disruption.
              </Alert>
            )}

            {/* Line Items */}
            <Table striped withTableBorder>
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>Description</Table.Th>
                  <Table.Th ta="right">Qty</Table.Th>
                  <Table.Th ta="right">Price</Table.Th>
                  <Table.Th ta="right">Discount</Table.Th>
                  <Table.Th ta="right">Amount</Table.Th>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {detail.items?.map((item: any) => (
                  <Table.Tr key={item.id}>
                    <Table.Td>
                      <Text size="sm">{item.description}</Text>
                      {item.service_from && item.service_to && (
                        <Text size="xs" c="dimmed">{fmtDate(item.service_from)} — {fmtDate(item.service_to)}</Text>
                      )}
                    </Table.Td>
                    <Table.Td ta="right">{item.quantity}</Table.Td>
                    <Table.Td ta="right">{fmt(item.price)}</Table.Td>
                    <Table.Td ta="right">
                      {item.discount_value > 0
                        ? <Text size="sm" c="green">
                            {item.discount_type === 'flat' || item.discount_type === 'fixed'
                              ? fmt(item.discount_value)
                              : `${item.discount_value}%`}
                          </Text>
                        : <Text size="sm" c="dimmed">—</Text>
                      }
                    </Table.Td>
                    <Table.Td ta="right" fw={500}>{fmt(item.total)}</Table.Td>
                  </Table.Tr>
                ))}
              </Table.Tbody>
            </Table>

            {/* Totals */}
            <Paper withBorder p="md" radius="md">
              <Stack gap={6}>
                {detail.subtotal !== undefined && parseFloat(detail.discount_amount || '0') > 0 && (
                  <>
                    <Group justify="space-between">
                      <Text size="sm" c="dimmed">Subtotal</Text>
                      <Text size="sm">{fmt(detail.subtotal)}</Text>
                    </Group>
                    <Group justify="space-between">
                      <Text size="sm" c="dimmed">Discount</Text>
                      <Text size="sm" c="green">-{fmt(parseFloat(detail.discount_amount || '0'))}</Text>
                    </Group>
                  </>
                )}
                {parseFloat(detail.tax_amount || '0') > 0 && (
                  <Group justify="space-between">
                    <Text size="sm" c="dimmed">Tax</Text>
                    <Text size="sm">{fmt(parseFloat(detail.tax_amount || '0'))}</Text>
                  </Group>
                )}
                <Divider />
                <Group justify="space-between">
                  <Text fw={600}>Total</Text>
                  <Text fw={700} size="lg">{fmt(detail.total)}</Text>
                </Group>
                {detail.paid_amount !== undefined && (
                  <>
                    <Group justify="space-between">
                      <Text size="sm" c="dimmed">Paid</Text>
                      <Text fw={600} c="green">{fmt(detail.paid_amount)}</Text>
                    </Group>
                    <Group justify="space-between">
                      <Text fw={600}>Balance Due</Text>
                      <Text fw={700} size="lg" c={(detail.balance_due || 0) > 0 ? 'red' : 'green'}>
                        {fmt(detail.balance_due || 0)}
                      </Text>
                    </Group>
                  </>
                )}
              </Stack>
            </Paper>

            {/* Pay Now */}
            {isInvoice && (detail.balance_due ?? 0) > 0 && (
              <Button
                fullWidth
                size="lg"
                color="green"
                leftSection={<IconCreditCard size={20} />}
                loading={paying}
                onClick={() => handlePay(detail.id)}
              >
                Pay {fmt(detail.balance_due ?? 0)} Now
              </Button>
            )}

            {/* Payment History */}
            {detail.payments && detail.payments.length > 0 && (
              <Paper withBorder p="md" radius="md">
                <Text fw={600} mb="sm">Payment History</Text>
                <Table striped>
                  <Table.Thead>
                    <Table.Tr>
                      <Table.Th>Date</Table.Th>
                      <Table.Th ta="right">Amount</Table.Th>
                      <Table.Th>Method</Table.Th>
                      <Table.Th>Reference</Table.Th>
                    </Table.Tr>
                  </Table.Thead>
                  <Table.Tbody>
                    {detail.payments.map((p: any) => (
                      <Table.Tr key={p.id}>
                        <Table.Td>{fmtDate(p.payment_date)}</Table.Td>
                        <Table.Td ta="right" fw={600} c="green">{fmt(parseFloat(p.amount))}</Table.Td>
                        <Table.Td><Badge variant="light" size="xs">{(p.payment_method || '').replace('_', ' ')}</Badge></Table.Td>
                        <Table.Td>{p.reference || '—'}</Table.Td>
                      </Table.Tr>
                    ))}
                  </Table.Tbody>
                </Table>
              </Paper>
            )}

            {/* Notes */}
            {detail.notes && (
              <Paper withBorder p="md" radius="md">
                <Text size="sm" fw={600} mb={4}>Notes</Text>
                <Text size="sm" c="dimmed">{detail.notes}</Text>
              </Paper>
            )}

            {/* Actions */}
            <Button
              variant="light"
              fullWidth
              leftSection={<IconMail size={18} />}
              loading={sending}
              onClick={async () => {
                setSending(true);
                try {
                  await resendPortalDocument(detail.id);
                  notifications.show({ title: 'Sent', message: 'Document sent to your email.', color: 'green' });
                } catch {
                  notifications.show({ title: 'Error', message: 'Failed to send document.', color: 'red' });
                } finally {
                  setSending(false);
                }
              }}
            >
              Resend to My Email
            </Button>
          </Stack>
        )}
      </Drawer>
    </Stack>
  );
}

function StatCard({ label, value, icon, color }: { label: string; value: string; icon: React.ReactNode; color: string }) {
  return (
    <Paper withBorder p="md" radius="md">
      <Group justify="space-between">
        <div>
          <Text size="xs" c="dimmed" tt="uppercase" fw={700}>{label}</Text>
          <Text fw={700} size="xl">{value}</Text>
        </div>
        <Text c={color}>{icon}</Text>
      </Group>
    </Paper>
  );
}
