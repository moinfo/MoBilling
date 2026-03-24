import { Title, Table, Text, Group, Pagination, Badge, TextInput, ActionIcon, Drawer, Stack, NumberInput, Select, Textarea, Button, Tooltip, Loader, Center, Divider, Anchor, Paper } from '@mantine/core';
import { DateInput } from '@mantine/dates';
import { useDebouncedValue } from '@mantine/hooks';
import { useForm } from '@mantine/form';
import { modals } from '@mantine/modals';
import { notifications } from '@mantine/notifications';
import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { IconSearch, IconEdit, IconTrash, IconReceipt, IconFileInvoice, IconEye, IconDownload, IconPaperclip, IconPlus } from '@tabler/icons-react';
import { getPaymentsIn, getDocuments, createPaymentIn, updatePaymentIn, deletePaymentIn, resendReceipt, resendInvoice, downloadPaymentReceipt, Payment } from '../api/documents';
import { getClients } from '../api/clients';
import { usePaymentMethods } from '../hooks/usePaymentMethods';
import { usePermissions } from '../hooks/usePermissions';
import { formatCurrency } from '../utils/formatCurrency';
import { formatDate } from '../utils/formatDate';
import dayjs from 'dayjs';

type PaymentWithDoc = Payment & { document?: { document_number: string; type: string; total: string; client?: { name: string; email: string } } | null };

export default function PaymentsIn() {
  const queryClient = useQueryClient();
  const { can } = usePermissions();
  const canChangeDateRange = can('payments_in.date_range');
  const today = dayjs().format('YYYY-MM-DD');
  const [page, setPage] = useState(1);
  const [search, setSearch] = useState('');
  const [debouncedSearch] = useDebouncedValue(search, 300);
  const [dateFrom, setDateFrom] = useState<string>(today);
  const [dateTo, setDateTo] = useState<string>(today);
  const [editPayment, setEditPayment] = useState<PaymentWithDoc | null>(null);
  const [viewPayment, setViewPayment] = useState<PaymentWithDoc | null>(null);
  const [addDrawerOpen, setAddDrawerOpen] = useState(false);

  const { methods: paymentMethods } = usePaymentMethods();

  const { data, isLoading } = useQuery({
    queryKey: ['payments-in', page, debouncedSearch, dateFrom, dateTo],
    queryFn: () => getPaymentsIn({
      page,
      search: debouncedSearch || undefined,
      date_from: dateFrom || undefined,
      date_to: dateTo || undefined,
    }),
  });

  const payments: PaymentWithDoc[] = data?.data?.data || [];
  const meta = data?.data?.meta;

  const addForm = useForm({
    initialValues: {
      client_id: '',
      document_id: '',
      amount: 0,
      payment_date: new Date(),
      payment_method: 'bank',
      reference: '',
      notes: '',
    },
  });

  // Fetch clients for the add form
  const { data: clientsData } = useQuery({
    queryKey: ['clients-list'],
    queryFn: () => getClients({ per_page: 500 }),
    enabled: addDrawerOpen,
  });
  const clientOptions = (clientsData?.data?.data || []).map((c: any) => ({ value: c.id, label: c.name }));

  // Fetch unpaid invoices for selected client
  const selectedClientId = addForm.values.client_id;
  const { data: invoicesData } = useQuery({
    queryKey: ['client-unpaid-invoices', selectedClientId],
    queryFn: () => getDocuments({ type: 'invoice', status: 'sent', client_id: selectedClientId, per_page: 100 }),
    enabled: !!selectedClientId,
  });
  const invoiceOptions = [
    { value: '', label: '— No invoice (standalone payment) —' },
    ...(invoicesData?.data?.data || []).map((d: any) => ({
      value: d.id,
      label: `${d.document_number} — ${formatCurrency(d.total)} (due: ${formatCurrency(d.balance_due)})`,
    })),
  ];

  const createMutation = useMutation({
    mutationFn: (values: typeof addForm.values) => createPaymentIn({
      client_id: values.client_id,
      document_id: values.document_id || undefined,
      amount: values.amount,
      payment_date: dayjs(values.payment_date).format('YYYY-MM-DD'),
      payment_method: values.payment_method,
      reference: values.reference || undefined,
      notes: values.notes || undefined,
    }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['payments-in'] });
      queryClient.invalidateQueries({ queryKey: ['documents'] });
      setAddDrawerOpen(false);
      addForm.reset();
      notifications.show({ title: 'Success', message: 'Payment recorded', color: 'green' });
    },
    onError: () => notifications.show({ title: 'Error', message: 'Failed to record payment', color: 'red' }),
  });

  const editForm = useForm({
    initialValues: {
      amount: 0,
      payment_date: new Date(),
      payment_method: 'bank',
      reference: '',
      notes: '',
    },
  });

  const updateMutation = useMutation({
    mutationFn: (values: any) => updatePaymentIn(editPayment!.id, {
      client_id: editPayment!.client_id!,
      document_id: editPayment!.document_id || undefined,
      amount: values.amount,
      payment_date: dayjs(values.payment_date).format('YYYY-MM-DD'),
      payment_method: values.payment_method,
      reference: values.reference || undefined,
      notes: values.notes || undefined,
    }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['payments-in'] });
      queryClient.invalidateQueries({ queryKey: ['documents'] });
      setEditPayment(null);
      notifications.show({ title: 'Success', message: 'Payment updated', color: 'green' });
    },
    onError: () => notifications.show({ title: 'Error', message: 'Failed to update payment', color: 'red' }),
  });

  const deleteMutation = useMutation({
    mutationFn: (id: string) => deletePaymentIn(id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['payments-in'] });
      queryClient.invalidateQueries({ queryKey: ['documents'] });
      notifications.show({ title: 'Success', message: 'Payment deleted', color: 'green' });
    },
    onError: () => notifications.show({ title: 'Error', message: 'Failed to delete payment', color: 'red' }),
  });

  const handleEdit = (p: PaymentWithDoc) => {
    editForm.setValues({
      amount: parseFloat(p.amount),
      payment_date: new Date(p.payment_date),
      payment_method: p.payment_method,
      reference: p.reference || '',
      notes: p.notes || '',
    });
    setEditPayment(p);
  };

  const handleResendReceipt = async (p: PaymentWithDoc) => {
    try {
      await resendReceipt(p.id);
      notifications.show({ title: 'Sent', message: 'Receipt email sent to client', color: 'green' });
    } catch {
      notifications.show({ title: 'Error', message: 'Failed to send receipt', color: 'red' });
    }
  };

  const handleResendInvoice = async (p: PaymentWithDoc) => {
    if (!p.document_id) return;
    try {
      await resendInvoice(p.document_id);
      notifications.show({ title: 'Sent', message: 'Invoice email sent to client', color: 'green' });
    } catch {
      notifications.show({ title: 'Error', message: 'Failed to send invoice', color: 'red' });
    }
  };

  const handleDelete = (p: PaymentWithDoc) => {
    modals.openConfirmModal({
      title: 'Delete Payment',
      children: `Delete payment of ${formatCurrency(p.amount)} for ${p.document?.document_number || 'invoice'}? This will update the invoice balance.`,
      labels: { confirm: 'Delete', cancel: 'Cancel' },
      confirmProps: { color: 'red' },
      onConfirm: () => deleteMutation.mutate(p.id),
    });
  };

  return (
    <>
      <Group justify="space-between" mb="md">
        <Title order={2}>Payments Received</Title>
        {can('payments_in.create') && (
          <Button leftSection={<IconPlus size={16} />} onClick={() => setAddDrawerOpen(true)}>
            Add Payment
          </Button>
        )}
      </Group>

      <Group mb="md" wrap="wrap" align="flex-end">
        <TextInput
          placeholder="Search by invoice or client..."
          leftSection={<IconSearch size={16} />}
          value={search}
          onChange={(e) => { setSearch(e.currentTarget.value); setPage(1); }}
          maw={300}
        />
        <DateInput
          label="From"
          value={dateFrom ? new Date(dateFrom) : null}
          onChange={(v) => { setDateFrom(v ? dayjs(v).format('YYYY-MM-DD') : today); setPage(1); }}
          disabled={!canChangeDateRange}
          maw={160}
          size="sm"
        />
        <DateInput
          label="To"
          value={dateTo ? new Date(dateTo) : null}
          onChange={(v) => { setDateTo(v ? dayjs(v).format('YYYY-MM-DD') : today); setPage(1); }}
          disabled={!canChangeDateRange}
          maw={160}
          size="sm"
        />
      </Group>

      {isLoading ? (
        <Center py="xl"><Loader /></Center>
      ) : payments.length === 0 ? (
        <Text c="dimmed" ta="center" py="xl">No payments recorded yet</Text>
      ) : (
        <Table.ScrollContainer minWidth={750}>
          <Table striped highlightOnHover>
            <Table.Thead>
              <Table.Tr>
                <Table.Th w={50}>#</Table.Th>
                <Table.Th>Date</Table.Th>
                <Table.Th>Invoice</Table.Th>
                <Table.Th>Client</Table.Th>
                <Table.Th>Amount</Table.Th>
                <Table.Th>Method</Table.Th>
                <Table.Th>Reference</Table.Th>
                <Table.Th>Received By</Table.Th>
                <Table.Th w={170}>Actions</Table.Th>
              </Table.Tr>
            </Table.Thead>
          <Table.Tbody>
            {payments.map((p, index) => (
              <Table.Tr key={p.id}>
                <Table.Td><Text size="sm" c="dimmed">{(meta ? (meta.current_page - 1) * meta.per_page : 0) + index + 1}</Text></Table.Td>
                <Table.Td>{formatDate(p.payment_date)}</Table.Td>
                <Table.Td fw={500}>{p.document?.document_number || '—'}</Table.Td>
                <Table.Td>{p.document?.client?.name || p.client?.name || '—'}</Table.Td>
                <Table.Td fw={500}>{formatCurrency(p.amount)}</Table.Td>
                <Table.Td>
                  <Badge variant="light" size="sm">
                    {p.payment_method.replace('_', ' ')}
                  </Badge>
                </Table.Td>
                <Table.Td>{p.reference || '—'}</Table.Td>
                <Table.Td>
                  <Text size="sm">{p.received_by?.name || '—'}</Text>
                </Table.Td>
                <Table.Td>
                  <Group gap={4} wrap="nowrap">
                    <Tooltip label="Preview">
                      <ActionIcon variant="subtle" color="gray" size="sm" onClick={() => setViewPayment(p)}>
                        <IconEye size={16} />
                      </ActionIcon>
                    </Tooltip>
                    {can('payments_in.resend_receipt') && (
                      <Tooltip label="Resend Receipt">
                        <ActionIcon variant="subtle" color="green" size="sm" onClick={() => handleResendReceipt(p)}>
                          <IconReceipt size={16} />
                        </ActionIcon>
                      </Tooltip>
                    )}
                    {can('documents.send') && (
                      <Tooltip label="Resend Invoice">
                        <ActionIcon variant="subtle" color="cyan" size="sm" onClick={() => handleResendInvoice(p)}>
                          <IconFileInvoice size={16} />
                        </ActionIcon>
                      </Tooltip>
                    )}
                    {can('payments_in.update') && (
                      <Tooltip label="Edit">
                        <ActionIcon variant="subtle" color="blue" size="sm" onClick={() => handleEdit(p)}>
                          <IconEdit size={16} />
                        </ActionIcon>
                      </Tooltip>
                    )}
                    {can('payments_in.delete') && (
                      <Tooltip label="Delete">
                        <ActionIcon variant="subtle" color="red" size="sm" onClick={() => handleDelete(p)}>
                          <IconTrash size={16} />
                        </ActionIcon>
                      </Tooltip>
                    )}
                  </Group>
                </Table.Td>
              </Table.Tr>
            ))}
            </Table.Tbody>
          </Table>
        </Table.ScrollContainer>
      )}

      {meta && meta.last_page > 1 && (
        <Group justify="center" mt="md">
          <Pagination total={meta.last_page} value={page} onChange={setPage} />
        </Group>
      )}

      {/* Preview Payment Drawer */}
      <Drawer
        opened={!!viewPayment}
        onClose={() => setViewPayment(null)}
        title="Payment Receipt"
        position="right"
        size="md"
      >
        {viewPayment && (
          <Stack>
            <Paper p="md" withBorder>
              <Stack gap="xs">
                <Group justify="space-between">
                  <Text size="sm" c="dimmed">Invoice</Text>
                  <Text fw={600}>{viewPayment.document?.document_number || '—'}</Text>
                </Group>
                <Group justify="space-between">
                  <Text size="sm" c="dimmed">Client</Text>
                  <Text fw={500}>{viewPayment.document?.client?.name || viewPayment.client?.name || '—'}</Text>
                </Group>
                <Divider />
                <Group justify="space-between">
                  <Text size="sm" c="dimmed">Payment Date</Text>
                  <Text>{formatDate(viewPayment.payment_date)}</Text>
                </Group>
                <Group justify="space-between">
                  <Text size="sm" c="dimmed">Amount</Text>
                  <Text fw={700} size="lg" c="green">{formatCurrency(viewPayment.amount)}</Text>
                </Group>
                <Group justify="space-between">
                  <Text size="sm" c="dimmed">Method</Text>
                  <Badge variant="light">{viewPayment.payment_method.replace('_', ' ')}</Badge>
                </Group>
                {viewPayment.reference && (
                  <Group justify="space-between">
                    <Text size="sm" c="dimmed">Reference</Text>
                    <Text>{viewPayment.reference}</Text>
                  </Group>
                )}
                {viewPayment.notes && (
                  <>
                    <Divider />
                    <Text size="sm" c="dimmed">Notes</Text>
                    <Text size="sm">{viewPayment.notes}</Text>
                  </>
                )}
                <Group justify="space-between">
                  <Text size="sm" c="dimmed">Invoice Total</Text>
                  <Text>{viewPayment.document?.total ? formatCurrency(viewPayment.document.total) : '—'}</Text>
                </Group>
                {viewPayment.received_by && (
                  <Group justify="space-between">
                    <Text size="sm" c="dimmed">Received By</Text>
                    <Text>{viewPayment.received_by.name}</Text>
                  </Group>
                )}
              </Stack>
            </Paper>

            {viewPayment.attachment_url && (
              <Paper p="md" withBorder>
                <Text size="sm" fw={600} mb="xs">Attachment</Text>
                <Anchor href={viewPayment.attachment_url} target="_blank" size="sm">
                  <Group gap={6}>
                    <IconPaperclip size={16} />
                    View Attachment
                  </Group>
                </Anchor>
              </Paper>
            )}

            <Group>
              <Button
                variant="light"
                leftSection={<IconDownload size={16} />}
                onClick={() => downloadPaymentReceipt(viewPayment.id)}
              >
                Download Receipt PDF
              </Button>
              {can('payments_in.resend_receipt') && (
                <Button
                  variant="light"
                  color="green"
                  leftSection={<IconReceipt size={16} />}
                  onClick={() => handleResendReceipt(viewPayment)}
                >
                  Resend Receipt
                </Button>
              )}
            </Group>
          </Stack>
        )}
      </Drawer>

      {/* Add Payment Drawer */}
      <Drawer
        opened={addDrawerOpen}
        onClose={() => { setAddDrawerOpen(false); addForm.reset(); }}
        title="Add Payment"
        position="right"
        size="md"
      >
        <form onSubmit={addForm.onSubmit((values) => createMutation.mutate(values))}>
          <Stack>
            <Select
              label="Client"
              placeholder="Select a client"
              data={clientOptions}
              searchable
              required
              {...addForm.getInputProps('client_id')}
              onChange={(v) => {
                addForm.setFieldValue('client_id', v || '');
                addForm.setFieldValue('document_id', '');
              }}
            />
            {selectedClientId && (
              <Select
                label="Invoice (optional)"
                placeholder="Link to an invoice or leave empty"
                data={invoiceOptions}
                searchable
                clearable
                {...addForm.getInputProps('document_id')}
              />
            )}
            <NumberInput label="Amount" min={0.01} decimalScale={2} required {...addForm.getInputProps('amount')} />
            <DateInput label="Payment Date" required {...addForm.getInputProps('payment_date')} />
            <Select label="Method" data={paymentMethods} {...addForm.getInputProps('payment_method')} />
            <TextInput label="Reference" placeholder="Transaction ref / M-Pesa code" {...addForm.getInputProps('reference')} />
            <Textarea label="Notes" {...addForm.getInputProps('notes')} />
            <Group justify="flex-end">
              <Button variant="light" onClick={() => { setAddDrawerOpen(false); addForm.reset(); }}>Cancel</Button>
              <Button type="submit" loading={createMutation.isPending}>Record Payment</Button>
            </Group>
          </Stack>
        </form>
      </Drawer>

      {/* Edit Payment Drawer */}
      <Drawer
        opened={!!editPayment}
        onClose={() => setEditPayment(null)}
        title={`Edit Payment — ${editPayment?.document?.document_number || ''}`}
        position="right"
      >
        <form onSubmit={editForm.onSubmit((values) => updateMutation.mutate(values))}>
          <Stack>
            <NumberInput label="Amount" min={0.01} decimalScale={2} required {...editForm.getInputProps('amount')} />
            <DateInput label="Payment Date" required {...editForm.getInputProps('payment_date')} />
            <Select label="Method" data={paymentMethods} {...editForm.getInputProps('payment_method')} />
            <TextInput label="Reference" placeholder="Transaction ref" {...editForm.getInputProps('reference')} />
            <Textarea label="Notes" {...editForm.getInputProps('notes')} />
            <Group justify="flex-end">
              <Button variant="light" onClick={() => setEditPayment(null)}>Cancel</Button>
              <Button type="submit" loading={updateMutation.isPending}>Save Changes</Button>
            </Group>
          </Stack>
        </form>
      </Drawer>
    </>
  );
}
