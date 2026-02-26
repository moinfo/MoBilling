import { Title, Table, Text, Group, Pagination, Badge, TextInput, ActionIcon, Drawer, Stack, NumberInput, Select, Textarea, Button, Tooltip } from '@mantine/core';
import { DateInput } from '@mantine/dates';
import { useDebouncedValue } from '@mantine/hooks';
import { useForm } from '@mantine/form';
import { modals } from '@mantine/modals';
import { notifications } from '@mantine/notifications';
import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { IconSearch, IconEdit, IconTrash, IconReceipt, IconFileInvoice } from '@tabler/icons-react';
import { getPaymentsIn, updatePaymentIn, deletePaymentIn, resendReceipt, resendInvoice, Payment } from '../api/documents';
import { usePaymentMethods } from '../hooks/usePaymentMethods';
import { formatCurrency } from '../utils/formatCurrency';
import { formatDate } from '../utils/formatDate';
import dayjs from 'dayjs';

type PaymentWithDoc = Payment & { document?: { document_number: string; type: string; total: string; client?: { name: string; email: string } } };

export default function PaymentsIn() {
  const queryClient = useQueryClient();
  const [page, setPage] = useState(1);
  const [search, setSearch] = useState('');
  const [debouncedSearch] = useDebouncedValue(search, 300);
  const [editPayment, setEditPayment] = useState<PaymentWithDoc | null>(null);

  const { methods: paymentMethods } = usePaymentMethods();

  const { data } = useQuery({
    queryKey: ['payments-in', page, debouncedSearch],
    queryFn: () => getPaymentsIn({ page, search: debouncedSearch || undefined } as any),
  });

  const payments: PaymentWithDoc[] = data?.data?.data || [];
  const meta = data?.data?.meta;

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
      document_id: editPayment!.document_id,
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
      </Group>

      <TextInput
        placeholder="Search by invoice or client..."
        leftSection={<IconSearch size={16} />}
        value={search}
        onChange={(e) => { setSearch(e.currentTarget.value); setPage(1); }}
        mb="md"
        maw={300}
      />

      {payments.length === 0 ? (
        <Text c="dimmed" ta="center" py="xl">No payments recorded yet</Text>
      ) : (
        <Table.ScrollContainer minWidth={750}>
          <Table striped highlightOnHover>
            <Table.Thead>
              <Table.Tr>
                <Table.Th>Date</Table.Th>
                <Table.Th>Invoice</Table.Th>
                <Table.Th>Client</Table.Th>
                <Table.Th>Amount</Table.Th>
                <Table.Th>Method</Table.Th>
                <Table.Th>Reference</Table.Th>
                <Table.Th w={140}>Actions</Table.Th>
              </Table.Tr>
            </Table.Thead>
          <Table.Tbody>
            {payments.map((p) => (
              <Table.Tr key={p.id}>
                <Table.Td>{formatDate(p.payment_date)}</Table.Td>
                <Table.Td fw={500}>{p.document?.document_number || '—'}</Table.Td>
                <Table.Td>{p.document?.client?.name || '—'}</Table.Td>
                <Table.Td fw={500}>{formatCurrency(p.amount)}</Table.Td>
                <Table.Td>
                  <Badge variant="light" size="sm">
                    {p.payment_method.replace('_', ' ')}
                  </Badge>
                </Table.Td>
                <Table.Td>{p.reference || '—'}</Table.Td>
                <Table.Td>
                  <Group gap={4}>
                    <Tooltip label="Resend Receipt">
                      <ActionIcon variant="subtle" color="green" size="sm" onClick={() => handleResendReceipt(p)}>
                        <IconReceipt size={16} />
                      </ActionIcon>
                    </Tooltip>
                    <Tooltip label="Resend Invoice">
                      <ActionIcon variant="subtle" color="cyan" size="sm" onClick={() => handleResendInvoice(p)}>
                        <IconFileInvoice size={16} />
                      </ActionIcon>
                    </Tooltip>
                    <Tooltip label="Edit">
                      <ActionIcon variant="subtle" color="blue" size="sm" onClick={() => handleEdit(p)}>
                        <IconEdit size={16} />
                      </ActionIcon>
                    </Tooltip>
                    <Tooltip label="Delete">
                      <ActionIcon variant="subtle" color="red" size="sm" onClick={() => handleDelete(p)}>
                        <IconTrash size={16} />
                      </ActionIcon>
                    </Tooltip>
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
